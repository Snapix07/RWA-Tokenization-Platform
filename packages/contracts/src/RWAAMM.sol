// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {InsufficientLiquidity, SlippageExceeded, ZeroAddress, ZeroAmount} from "./interfaces/IRWATypes.sol";

/// @title RWAAMM
/// @notice Constant-product AMM (x·y = k) built from scratch for the RWA token pair.
///         The contract itself is the LP token (ERC-20). Fee: 0.3% (997/1000 ratio).
///
/// Yul benchmark: _sqrt uses the Babylonian method in inline assembly; _sqrtSolidity is
///         the pure-Solidity baseline. Gas delta is documented in the gas report.
///
/// Design patterns: CEI, ReentrancyGuard, Pausable.
contract RWAAMM is ERC20, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    // -------------------------------------------------------------------------
    // Constants
    // -------------------------------------------------------------------------

    uint256 public constant FEE_NUMERATOR = 997;
    uint256 public constant FEE_DENOMINATOR = 1000;
    /// @dev Locked in address(1) on first deposit to prevent price-manipulation via
    ///      tiny initial liquidity. Equal to Uniswap V2's MINIMUM_LIQUIDITY.
    uint256 public constant MINIMUM_LIQUIDITY = 1000;

    // -------------------------------------------------------------------------
    // State
    // -------------------------------------------------------------------------

    address public immutable tokenA;
    address public immutable tokenB;
    address public immutable admin;

    uint112 private _reserveA;
    uint112 private _reserveB;
    bool private _initialized;

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    event LiquidityAdded(address indexed provider, uint256 amountA, uint256 amountB, uint256 liquidity);
    event LiquidityRemoved(address indexed provider, uint256 amountA, uint256 amountB, uint256 liquidity);
    event Swap(address indexed sender, address indexed tokenIn, uint256 amountIn, uint256 amountOut);
    event Sync(uint112 reserveA, uint112 reserveB);

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    constructor(address tokenA_, address tokenB_, address admin_) ERC20("RWA AMM LP", "RWAMMLP") {
        if (tokenA_ == address(0) || tokenB_ == address(0) || admin_ == address(0)) revert ZeroAddress();
        require(tokenA_ != tokenB_, "identical tokens");
        tokenA = tokenA_;
        tokenB = tokenB_;
        admin = admin_;
    }

    // -------------------------------------------------------------------------
    // Liquidity
    // -------------------------------------------------------------------------

    /// @notice Adds liquidity to the pool. Caller must approve both tokens first.
    /// @param  amountADesired  Max tokenA to deposit.
    /// @param  amountBDesired  Max tokenB to deposit.
    /// @param  amountAMin      Minimum tokenA to accept (slippage guard).
    /// @param  amountBMin      Minimum tokenB to accept (slippage guard).
    function addLiquidity(
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to
    ) external whenNotPaused nonReentrant returns (uint256 amountA, uint256 amountB, uint256 liquidity) {
        if (amountADesired == 0 || amountBDesired == 0) revert ZeroAmount();

        (uint112 rA, uint112 rB) = getReserves();

        if (rA == 0 && rB == 0) {
            // First deposit: accept desired amounts exactly
            (amountA, amountB) = (amountADesired, amountBDesired);
        } else {
            // Subsequent: maintain the current ratio
            uint256 amountBOptimal = (amountADesired * rB) / rA;
            if (amountBOptimal <= amountBDesired) {
                if (amountBOptimal < amountBMin) revert SlippageExceeded(amountBOptimal, amountBMin);
                (amountA, amountB) = (amountADesired, amountBOptimal);
            } else {
                uint256 amountAOptimal = (amountBDesired * rA) / rB;
                if (amountAOptimal < amountAMin) revert SlippageExceeded(amountAOptimal, amountAMin);
                (amountA, amountB) = (amountAOptimal, amountBDesired);
            }
        }

        // Effects: transfer tokens in, update reserves, mint LP
        IERC20(tokenA).safeTransferFrom(msg.sender, address(this), amountA);
        IERC20(tokenB).safeTransferFrom(msg.sender, address(this), amountB);

        uint256 supply = totalSupply();
        if (supply == 0) {
            // Lock MINIMUM_LIQUIDITY to address(1) permanently
            liquidity = _sqrt(amountA * amountB) - MINIMUM_LIQUIDITY;
            _mint(address(1), MINIMUM_LIQUIDITY);
        } else {
            uint256 lA = (amountA * supply) / rA;
            uint256 lB = (amountB * supply) / rB;
            liquidity = lA < lB ? lA : lB;
        }

        if (liquidity == 0) revert InsufficientLiquidity();
        _mint(to, liquidity);
        _sync();

        emit LiquidityAdded(msg.sender, amountA, amountB, liquidity);
    }

    /// @notice Burns LP tokens and returns the proportional share of reserves.
    function removeLiquidity(uint256 liquidity, uint256 amountAMin, uint256 amountBMin, address to)
        external
        whenNotPaused
        nonReentrant
        returns (uint256 amountA, uint256 amountB)
    {
        if (liquidity == 0) revert ZeroAmount();

        uint256 supply = totalSupply();
        (uint112 rA, uint112 rB) = getReserves();

        amountA = (liquidity * rA) / supply;
        amountB = (liquidity * rB) / supply;

        if (amountA < amountAMin) revert SlippageExceeded(amountA, amountAMin);
        if (amountB < amountBMin) revert SlippageExceeded(amountB, amountBMin);
        if (amountA == 0 || amountB == 0) revert InsufficientLiquidity();

        // Effects: burn LP then transfer (CEI — burn before external call)
        _burn(msg.sender, liquidity);
        IERC20(tokenA).safeTransfer(to, amountA);
        IERC20(tokenB).safeTransfer(to, amountB);
        _sync();

        emit LiquidityRemoved(msg.sender, amountA, amountB, liquidity);
    }

    // -------------------------------------------------------------------------
    // Swap
    // -------------------------------------------------------------------------

    /// @notice Swaps an exact amount of tokenIn for at least amountOutMin of the other token.
    function swapExactTokensForTokens(uint256 amountIn, uint256 amountOutMin, address tokenIn, address to)
        external
        whenNotPaused
        nonReentrant
        returns (uint256 amountOut)
    {
        if (amountIn == 0) revert ZeroAmount();
        require(tokenIn == tokenA || tokenIn == tokenB, "invalid tokenIn");

        (uint112 rA, uint112 rB) = getReserves();
        bool aToB = tokenIn == tokenA;
        (uint256 reserveIn, uint256 reserveOut) = aToB ? (uint256(rA), uint256(rB)) : (uint256(rB), uint256(rA));

        amountOut = getAmountOut(amountIn, reserveIn, reserveOut);
        if (amountOut < amountOutMin) revert SlippageExceeded(amountOut, amountOutMin);
        if (amountOut == 0 || amountOut >= reserveOut) revert InsufficientLiquidity();

        // CEI: transfer in first, then out
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
        address tokenOut = aToB ? tokenB : tokenA;
        IERC20(tokenOut).safeTransfer(to, amountOut);
        _sync();

        emit Swap(msg.sender, tokenIn, amountIn, amountOut);
    }

    // -------------------------------------------------------------------------
    // View helpers
    // -------------------------------------------------------------------------

    function getReserves() public view returns (uint112 reserveA, uint112 reserveB) {
        return (_reserveA, _reserveB);
    }

    /// @notice Computes output amount for a given input, applying the 0.3% fee.
    ///         Formula: amountOut = (amountIn * 997 * reserveOut) / (reserveIn * 1000 + amountIn * 997)
    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut)
        public
        pure
        returns (uint256 amountOut)
    {
        if (reserveIn == 0 || reserveOut == 0) revert InsufficientLiquidity();
        uint256 amountInWithFee = amountIn * FEE_NUMERATOR;
        amountOut = (amountInWithFee * reserveOut) / (reserveIn * FEE_DENOMINATOR + amountInWithFee);
    }

    // -------------------------------------------------------------------------
    // Admin
    // -------------------------------------------------------------------------

    function pause() external {
        require(msg.sender == admin, "not admin");
        _pause();
    }

    function unpause() external {
        require(msg.sender == admin, "not admin");
        _unpause();
    }

    // -------------------------------------------------------------------------
    // Internal
    // -------------------------------------------------------------------------

    function _sync() internal {
        _reserveA = uint112(IERC20(tokenA).balanceOf(address(this)));
        _reserveB = uint112(IERC20(tokenB).balanceOf(address(this)));
        emit Sync(_reserveA, _reserveB);
    }

    // -------------------------------------------------------------------------
    // Square root — Yul assembly vs pure-Solidity benchmark
    //
    // _sqrt (assembly) saves ~30 gas per call over _sqrtSolidity by using direct
    // EVM DIV/ADD opcodes without Solidity's bounds-checking wrappers.
    // Benchmarks are in the gas optimization report.
    // -------------------------------------------------------------------------

    /// @dev Production path — Babylonian square root in inline Yul.
    function _sqrt(uint256 x) internal pure returns (uint256 z) {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            switch x
            case 0 { z := 0 }
            default {
                z := x
                let y := add(div(x, 2), 1)
                for {} lt(y, z) {} {
                    z := y
                    y := div(add(div(x, y), y), 2)
                }
            }
        }
    }

    /// @dev Benchmark baseline — pure-Solidity equivalent of _sqrt. Not called in production.
    function _sqrtSolidity(uint256 x) internal pure returns (uint256 z) {
        if (x == 0) return 0;
        z = x;
        uint256 y = x / 2 + 1;
        while (y < z) {
            z = y;
            y = (x / y + y) / 2;
        }
    }
}
