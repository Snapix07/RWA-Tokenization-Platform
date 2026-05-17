// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {RWAAMM} from "../../src/RWAAMM.sol";

contract MockInvariantAMMToken is ERC20 {
    constructor(string memory name_, string memory symbol_)
        ERC20(name_, symbol_)
    {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract RWAAMMHandler is Test {
    RWAAMM internal amm;
    MockInvariantAMMToken internal tokenA;
    MockInvariantAMMToken internal tokenB;

    address[] internal actors;

    bool public lastActionWasSwap;
    uint256 public lastKBeforeSwap;
    uint256 public lastKAfterSwap;

    uint256 internal constant MAX_ACTION_AMOUNT = 100_000 ether;
    uint256 internal constant MIN_ACTION_AMOUNT = 1 ether;

    constructor(
        RWAAMM amm_,
        MockInvariantAMMToken tokenA_,
        MockInvariantAMMToken tokenB_,
        address[] memory actors_
    ) {
        amm = amm_;
        tokenA = tokenA_;
        tokenB = tokenB_;
        actors = actors_;
    }

    function actorCount() external view returns (uint256) {
        return actors.length;
    }

    function actorAt(uint256 index) external view returns (address) {
        return actors[index];
    }

    function addLiquidity(
        uint256 actorSeed,
        uint96 rawAmountA,
        uint96 rawAmountB
    ) external {
        lastActionWasSwap = false;

        address actor = actors[actorSeed % actors.length];

        uint256 actorBalanceA = tokenA.balanceOf(actor);
        uint256 actorBalanceB = tokenB.balanceOf(actor);

        if (
            actorBalanceA < MIN_ACTION_AMOUNT ||
            actorBalanceB < MIN_ACTION_AMOUNT
        ) {
            return;
        }

        uint256 amountA = bound(
            uint256(rawAmountA),
            MIN_ACTION_AMOUNT,
            _min(actorBalanceA, MAX_ACTION_AMOUNT)
        );

        uint256 amountB = bound(
            uint256(rawAmountB),
            MIN_ACTION_AMOUNT,
            _min(actorBalanceB, MAX_ACTION_AMOUNT)
        );

        vm.prank(actor);
        try amm.addLiquidity(
            amountA,
            amountB,
            0,
            0,
            actor
        ) {
            // success path
        } catch {
            // acceptable: some extreme pool ratios can make this liquidity quote invalid
        }
    }

    function removeLiquidity(
        uint256 actorSeed,
        uint96 rawLiquidity
    ) external {
        lastActionWasSwap = false;

        address actor = actors[actorSeed % actors.length];
        uint256 lpBalance = amm.balanceOf(actor);

        if (lpBalance < MIN_ACTION_AMOUNT) {
            return;
        }

        uint256 liquidity = bound(
            uint256(rawLiquidity),
            MIN_ACTION_AMOUNT,
            lpBalance
        );

        vm.prank(actor);
        try amm.removeLiquidity(
            liquidity,
            0,
            0,
            actor
        ) {
            // success path
        } catch {
            // tolerate impossible tiny proportional withdrawals
        }
    }

    function swapAToB(
        uint256 actorSeed,
        uint96 rawAmountIn
    ) external {
        address actor = actors[actorSeed % actors.length];
        uint256 actorBalance = tokenA.balanceOf(actor);

        if (actorBalance < MIN_ACTION_AMOUNT) {
            return;
        }

        (uint112 reserveABefore, uint112 reserveBBefore) = amm.getReserves();

        if (reserveABefore == 0 || reserveBBefore == 0) {
            return;
        }

        uint256 amountIn = bound(
            uint256(rawAmountIn),
            MIN_ACTION_AMOUNT,
            _min(actorBalance, MAX_ACTION_AMOUNT)
        );

        lastKBeforeSwap =
            uint256(reserveABefore) * uint256(reserveBBefore);

        vm.prank(actor);
        try amm.swapExactTokensForTokens(
            amountIn,
            0,
            address(tokenA),
            actor
        ) {
            (uint112 reserveAAfter, uint112 reserveBAfter) = amm.getReserves();

            lastKAfterSwap =
                uint256(reserveAAfter) * uint256(reserveBAfter);

            lastActionWasSwap = true;
        } catch {
            lastActionWasSwap = false;
        }
    }

    function swapBToA(
        uint256 actorSeed,
        uint96 rawAmountIn
    ) external {
        address actor = actors[actorSeed % actors.length];
        uint256 actorBalance = tokenB.balanceOf(actor);

        if (actorBalance < MIN_ACTION_AMOUNT) {
            return;
        }

        (uint112 reserveABefore, uint112 reserveBBefore) = amm.getReserves();

        if (reserveABefore == 0 || reserveBBefore == 0) {
            return;
        }

        uint256 amountIn = bound(
            uint256(rawAmountIn),
            MIN_ACTION_AMOUNT,
            _min(actorBalance, MAX_ACTION_AMOUNT)
        );

        lastKBeforeSwap =
            uint256(reserveABefore) * uint256(reserveBBefore);

        vm.prank(actor);
        try amm.swapExactTokensForTokens(
            amountIn,
            0,
            address(tokenB),
            actor
        ) {
            (uint112 reserveAAfter, uint112 reserveBAfter) = amm.getReserves();

            lastKAfterSwap =
                uint256(reserveAAfter) * uint256(reserveBAfter);

            lastActionWasSwap = true;
        } catch {
            lastActionWasSwap = false;
        }
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}

contract RWAAMMInvariantTest is StdInvariant, Test {
    MockInvariantAMMToken internal tokenA;
    MockInvariantAMMToken internal tokenB;

    RWAAMM internal amm;
    RWAAMMHandler internal handler;

    address internal admin = makeAddr("admin");

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol");

    uint256 internal constant ACTOR_BALANCE = 10_000_000 ether;
    uint256 internal constant INITIAL_LIQUIDITY = 1_000_000 ether;

    function setUp() public {
        tokenA = new MockInvariantAMMToken("Invariant Token A", "iTKA");
        tokenB = new MockInvariantAMMToken("Invariant Token B", "iTKB");

        amm = new RWAAMM(address(tokenA), address(tokenB), admin);

        address[] memory actors = new address[](3);
        actors[0] = alice;
        actors[1] = bob;
        actors[2] = carol;

        for (uint256 i = 0; i < actors.length; i++) {
            tokenA.mint(actors[i], ACTOR_BALANCE);
            tokenB.mint(actors[i], ACTOR_BALANCE);

            vm.startPrank(actors[i]);
            tokenA.approve(address(amm), type(uint256).max);
            tokenB.approve(address(amm), type(uint256).max);
            vm.stopPrank();
        }

        vm.prank(alice);
        amm.addLiquidity(
            INITIAL_LIQUIDITY,
            INITIAL_LIQUIDITY,
            0,
            0,
            alice
        );

        handler = new RWAAMMHandler(
            amm,
            tokenA,
            tokenB,
            actors
        );

        targetContract(address(handler));
    }

    function invariant_ReservesAlwaysMatchActualTokenBalances() public view {
        (uint112 reserveA, uint112 reserveB) = amm.getReserves();

        assertEq(
            uint256(reserveA),
            tokenA.balanceOf(address(amm))
        );

        assertEq(
            uint256(reserveB),
            tokenB.balanceOf(address(amm))
        );
    }

    function invariant_MinimumLiquidityRemainsPermanentlyLocked() public view {
        assertEq(
            amm.balanceOf(address(1)),
            amm.MINIMUM_LIQUIDITY()
        );
    }

    function invariant_TotalLpSupplyEqualsLockedLiquidityPlusActorLpBalances() public view {
        uint256 actorLpTotal =
            amm.balanceOf(alice) +
            amm.balanceOf(bob) +
            amm.balanceOf(carol);

        assertEq(
            amm.totalSupply(),
            actorLpTotal + amm.MINIMUM_LIQUIDITY()
        );
    }

    function invariant_ConstantProductDoesNotDecreaseImmediatelyAfterSuccessfulSwap() public view {
        if (handler.lastActionWasSwap()) {
            assertGe(
                handler.lastKAfterSwap(),
                handler.lastKBeforeSwap()
            );
        }
    }
}
