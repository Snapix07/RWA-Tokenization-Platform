// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {RWAAMM} from "../../src/RWAAMM.sol";

contract MockAMMFuzzToken is ERC20 {
    constructor(string memory name_, string memory symbol_)
        ERC20(name_, symbol_)
    {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract RWAAMMFuzzTest is Test {
    MockAMMFuzzToken internal tokenA;
    MockAMMFuzzToken internal tokenB;
    RWAAMM internal amm;

    address internal admin = makeAddr("admin");
    address internal liquidityProvider = makeAddr("liquidityProvider");
    address internal secondProvider = makeAddr("secondProvider");
    address internal trader = makeAddr("trader");

    uint256 internal constant INITIAL_LIQUIDITY = 1_000_000 ether;
    uint256 internal constant USER_TOKEN_BALANCE = 10_000_000 ether;

    function setUp() public {
        tokenA = new MockAMMFuzzToken("Token A", "TKA");
        tokenB = new MockAMMFuzzToken("Token B", "TKB");

        amm = new RWAAMM(address(tokenA), address(tokenB), admin);

        tokenA.mint(liquidityProvider, USER_TOKEN_BALANCE);
        tokenB.mint(liquidityProvider, USER_TOKEN_BALANCE);

        tokenA.mint(secondProvider, USER_TOKEN_BALANCE);
        tokenB.mint(secondProvider, USER_TOKEN_BALANCE);

        tokenA.mint(trader, USER_TOKEN_BALANCE);
        tokenB.mint(trader, USER_TOKEN_BALANCE);

        vm.startPrank(liquidityProvider);
        tokenA.approve(address(amm), type(uint256).max);
        tokenB.approve(address(amm), type(uint256).max);

        amm.addLiquidity(
            INITIAL_LIQUIDITY,
            INITIAL_LIQUIDITY,
            0,
            0,
            liquidityProvider
        );
        vm.stopPrank();

        vm.startPrank(secondProvider);
        tokenA.approve(address(amm), type(uint256).max);
        tokenB.approve(address(amm), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(trader);
        tokenA.approve(address(amm), type(uint256).max);
        tokenB.approve(address(amm), type(uint256).max);
        vm.stopPrank();
    }

    function testFuzz_SwapAToB_OutputPositiveAndKDoesNotDecrease(uint96 rawAmountIn) public {
        uint256 amountIn = bound(
            uint256(rawAmountIn),
            1 ether,
            100_000 ether
        );

        (uint112 reserveABefore, uint112 reserveBBefore) = amm.getReserves();
        uint256 kBefore = uint256(reserveABefore) * uint256(reserveBBefore);

        uint256 expectedOut = amm.getAmountOut(
            amountIn,
            reserveABefore,
            reserveBBefore
        );

        vm.prank(trader);
        uint256 actualOut = amm.swapExactTokensForTokens(
            amountIn,
            0,
            address(tokenA),
            trader
        );

        (uint112 reserveAAfter, uint112 reserveBAfter) = amm.getReserves();
        uint256 kAfter = uint256(reserveAAfter) * uint256(reserveBAfter);

        assertEq(actualOut, expectedOut);
        assertGt(actualOut, 0);
        assertGe(kAfter, kBefore);
    }

    function testFuzz_SwapBToA_OutputPositiveAndKDoesNotDecrease(uint96 rawAmountIn) public {
        uint256 amountIn = bound(
            uint256(rawAmountIn),
            1 ether,
            100_000 ether
        );

        (uint112 reserveABefore, uint112 reserveBBefore) = amm.getReserves();
        uint256 kBefore = uint256(reserveABefore) * uint256(reserveBBefore);

        uint256 expectedOut = amm.getAmountOut(
            amountIn,
            reserveBBefore,
            reserveABefore
        );

        vm.prank(trader);
        uint256 actualOut = amm.swapExactTokensForTokens(
            amountIn,
            0,
            address(tokenB),
            trader
        );

        (uint112 reserveAAfter, uint112 reserveBAfter) = amm.getReserves();
        uint256 kAfter = uint256(reserveAAfter) * uint256(reserveBAfter);

        assertEq(actualOut, expectedOut);
        assertGt(actualOut, 0);
        assertGe(kAfter, kBefore);
    }

    function testFuzz_GetAmountOut_Matches997Over1000Formula(
        uint96 rawAmountIn,
        uint96 rawReserveIn,
        uint96 rawReserveOut
    ) public view {
        uint256 amountIn = bound(
            uint256(rawAmountIn),
            1,
            1_000_000 ether
        );

        uint256 reserveIn = bound(
            uint256(rawReserveIn),
            1 ether,
            10_000_000 ether
        );

        uint256 reserveOut = bound(
            uint256(rawReserveOut),
            1 ether,
            10_000_000 ether
        );

        uint256 amountInWithFee = amountIn * amm.FEE_NUMERATOR();

        uint256 expectedOut =
            (amountInWithFee * reserveOut) /
            (reserveIn * amm.FEE_DENOMINATOR() + amountInWithFee);

        uint256 actualOut = amm.getAmountOut(
            amountIn,
            reserveIn,
            reserveOut
        );

        assertEq(actualOut, expectedOut);
    }

    function testFuzz_AddLiquidity_EqualReservePoolKeepsOneToOneRatio(uint96 rawAmount) public {
        uint256 amount = bound(
            uint256(rawAmount),
            1 ether,
            100_000 ether
        );

        vm.prank(secondProvider);
        (uint256 amountA, uint256 amountB, uint256 liquidityMinted) =
            amm.addLiquidity(
                amount,
                amount,
                0,
                0,
                secondProvider
            );

        assertEq(amountA, amount);
        assertEq(amountB, amount);
        assertGt(liquidityMinted, 0);

        (uint112 reserveA, uint112 reserveB) = amm.getReserves();
        assertEq(reserveA, reserveB);
    }

    function testFuzz_RemoveLiquidity_ReturnsProportionalAssets(uint96 rawLiquidity) public {
        uint256 providerLpBalance = amm.balanceOf(liquidityProvider);

        uint256 liquidityToRemove = bound(
            uint256(rawLiquidity),
            1 ether,
            providerLpBalance
        );

        (uint112 reserveABefore, uint112 reserveBBefore) = amm.getReserves();
        uint256 totalSupplyBefore = amm.totalSupply();

        uint256 expectedA =
            (liquidityToRemove * uint256(reserveABefore)) / totalSupplyBefore;

        uint256 expectedB =
            (liquidityToRemove * uint256(reserveBBefore)) / totalSupplyBefore;

        vm.prank(liquidityProvider);
        (uint256 amountA, uint256 amountB) =
            amm.removeLiquidity(
                liquidityToRemove,
                0,
                0,
                liquidityProvider
            );

        assertEq(amountA, expectedA);
        assertEq(amountB, expectedB);
        assertGt(amountA, 0);
        assertGt(amountB, 0);
    }
}
