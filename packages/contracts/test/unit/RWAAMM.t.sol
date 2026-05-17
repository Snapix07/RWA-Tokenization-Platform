// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {RWAAMM} from "../../src/RWAAMM.sol";

import {
    InsufficientLiquidity,
    SlippageExceeded,
    ZeroAddress,
    ZeroAmount
} from "../../src/interfaces/IRWATypes.sol";

contract MockAMMToken is ERC20 {
    constructor(string memory name_, string memory symbol_)
        ERC20(name_, symbol_)
    {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract RWAAMMHarness is RWAAMM {
    constructor(address tokenA_, address tokenB_, address admin_)
        RWAAMM(tokenA_, tokenB_, admin_)
    {}

    function sqrtAssemblyExternal(uint256 x) external pure returns (uint256) {
        return _sqrt(x);
    }

    function sqrtSolidityExternal(uint256 x) external pure returns (uint256) {
        return _sqrtSolidity(x);
    }
}

contract RWAAMMTest is Test {
    MockAMMToken internal tokenA;
    MockAMMToken internal tokenB;

    RWAAMM internal amm;
    RWAAMMHarness internal harness;

    address internal admin = makeAddr("admin");
    address internal liquidityProvider = makeAddr("liquidityProvider");
    address internal secondProvider = makeAddr("secondProvider");
    address internal trader = makeAddr("trader");
    address internal attacker = makeAddr("attacker");
    address internal recipient = makeAddr("recipient");

    uint256 internal constant INITIAL_A = 1_000 ether;
    uint256 internal constant INITIAL_B = 1_000 ether;

    function setUp() public {
        tokenA = new MockAMMToken("Token A", "TKA");
        tokenB = new MockAMMToken("Token B", "TKB");

        amm = new RWAAMM(address(tokenA), address(tokenB), admin);
        harness = new RWAAMMHarness(address(tokenA), address(tokenB), admin);

        tokenA.mint(liquidityProvider, 2_000_000 ether);
        tokenB.mint(liquidityProvider, 2_000_000 ether);

        tokenA.mint(secondProvider, 2_000_000 ether);
        tokenB.mint(secondProvider, 2_000_000 ether);

        tokenA.mint(trader, 2_000_000 ether);
        tokenB.mint(trader, 2_000_000 ether);

        vm.startPrank(liquidityProvider);
        tokenA.approve(address(amm), type(uint256).max);
        tokenB.approve(address(amm), type(uint256).max);
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

    function _addDefaultLiquidity() internal returns (uint256 liquidity) {
        vm.prank(liquidityProvider);
        (, , liquidity) = amm.addLiquidity(
            INITIAL_A,
            INITIAL_B,
            0,
            0,
            liquidityProvider
        );
    }

    function _addSkewedLiquidity() internal {
        vm.prank(liquidityProvider);
        amm.addLiquidity(
            1_000 ether,
            500 ether,
            0,
            0,
            liquidityProvider
        );
    }

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    function test_Constructor_SetsMetadataTokensAndAdmin() public view {
        assertEq(amm.name(), "RWA AMM LP");
        assertEq(amm.symbol(), "RWAMMLP");

        assertEq(amm.tokenA(), address(tokenA));
        assertEq(amm.tokenB(), address(tokenB));
        assertEq(amm.admin(), admin);
    }

    function test_Constructor_RevertsWhenTokenAIsZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector));
        new RWAAMM(address(0), address(tokenB), admin);
    }

    function test_Constructor_RevertsWhenTokenBIsZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector));
        new RWAAMM(address(tokenA), address(0), admin);
    }

    function test_Constructor_RevertsWhenAdminIsZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector));
        new RWAAMM(address(tokenA), address(tokenB), address(0));
    }

    function test_Constructor_RevertsWhenTokensAreIdentical() public {
        vm.expectRevert(bytes("identical tokens"));
        new RWAAMM(address(tokenA), address(tokenA), admin);
    }

    // -------------------------------------------------------------------------
    // Reserves before liquidity
    // -------------------------------------------------------------------------

    function test_GetReserves_ReturnsZeroBeforeLiquidity() public view {
        (uint112 reserveA, uint112 reserveB) = amm.getReserves();

        assertEq(reserveA, 0);
        assertEq(reserveB, 0);
    }

    // -------------------------------------------------------------------------
    // addLiquidity: first deposit
    // -------------------------------------------------------------------------

    function test_AddLiquidity_FirstDepositTransfersAssetsMintsLPAndSyncsReserves() public {
        vm.prank(liquidityProvider);
        (uint256 amountA, uint256 amountB, uint256 liquidity) =
            amm.addLiquidity(
                INITIAL_A,
                INITIAL_B,
                0,
                0,
                liquidityProvider
            );

        assertEq(amountA, INITIAL_A);
        assertEq(amountB, INITIAL_B);

        assertEq(liquidity, 1_000 ether - amm.MINIMUM_LIQUIDITY());
        assertEq(amm.balanceOf(liquidityProvider), liquidity);

        assertEq(tokenA.balanceOf(address(amm)), INITIAL_A);
        assertEq(tokenB.balanceOf(address(amm)), INITIAL_B);

        (uint112 reserveA, uint112 reserveB) = amm.getReserves();

        assertEq(reserveA, INITIAL_A);
        assertEq(reserveB, INITIAL_B);
    }

    function test_AddLiquidity_FirstDepositLocksMinimumLiquidityForever() public {
        _addDefaultLiquidity();

        assertEq(amm.balanceOf(address(1)), amm.MINIMUM_LIQUIDITY());
        assertEq(amm.totalSupply(), 1_000 ether);
    }

    function test_AddLiquidity_RevertsWhenAmountAIsZero() public {
        vm.prank(liquidityProvider);
        vm.expectRevert(abi.encodeWithSelector(ZeroAmount.selector));

        amm.addLiquidity(
            0,
            INITIAL_B,
            0,
            0,
            liquidityProvider
        );
    }

    function test_AddLiquidity_RevertsWhenAmountBIsZero() public {
        vm.prank(liquidityProvider);
        vm.expectRevert(abi.encodeWithSelector(ZeroAmount.selector));

        amm.addLiquidity(
            INITIAL_A,
            0,
            0,
            0,
            liquidityProvider
        );
    }

    // -------------------------------------------------------------------------
    // addLiquidity: subsequent deposits and ratio control
    // -------------------------------------------------------------------------

    function test_AddLiquidity_SubsequentDepositUsesOptimalAmountB() public {
        _addSkewedLiquidity();

        vm.prank(secondProvider);
        (uint256 amountA, uint256 amountB,) =
            amm.addLiquidity(
                100 ether,
                100 ether,
                0,
                0,
                secondProvider
            );

        assertEq(amountA, 100 ether);
        assertEq(amountB, 50 ether);

        (uint112 reserveA, uint112 reserveB) = amm.getReserves();

        assertEq(reserveA, 1_100 ether);
        assertEq(reserveB, 550 ether);
    }

    function test_AddLiquidity_SubsequentDepositUsesOptimalAmountA() public {
        _addSkewedLiquidity();

        vm.prank(secondProvider);
        (uint256 amountA, uint256 amountB,) =
            amm.addLiquidity(
                100 ether,
                20 ether,
                0,
                0,
                secondProvider
            );

        assertEq(amountA, 40 ether);
        assertEq(amountB, 20 ether);

        (uint112 reserveA, uint112 reserveB) = amm.getReserves();

        assertEq(reserveA, 1_040 ether);
        assertEq(reserveB, 520 ether);
    }

    function test_AddLiquidity_RevertsWhenOptimalBIsBelowAmountBMin() public {
        _addSkewedLiquidity();

        vm.prank(secondProvider);
        vm.expectRevert(
            abi.encodeWithSelector(
                SlippageExceeded.selector,
                50 ether,
                51 ether
            )
        );

        amm.addLiquidity(
            100 ether,
            100 ether,
            0,
            51 ether,
            secondProvider
        );
    }

    function test_AddLiquidity_RevertsWhenOptimalAIsBelowAmountAMin() public {
        _addSkewedLiquidity();

        vm.prank(secondProvider);
        vm.expectRevert(
            abi.encodeWithSelector(
                SlippageExceeded.selector,
                40 ether,
                41 ether
            )
        );

        amm.addLiquidity(
            100 ether,
            20 ether,
            41 ether,
            0,
            secondProvider
        );
    }

    // -------------------------------------------------------------------------
    // removeLiquidity
    // -------------------------------------------------------------------------

    function test_RemoveLiquidity_BurnsLPAndReturnsProportionalTokens() public {
        _addDefaultLiquidity();

        uint256 providerTokenABefore = tokenA.balanceOf(liquidityProvider);
        uint256 providerTokenBBefore = tokenB.balanceOf(liquidityProvider);

        vm.prank(liquidityProvider);
        (uint256 amountA, uint256 amountB) =
            amm.removeLiquidity(
                100 ether,
                0,
                0,
                liquidityProvider
            );

        assertEq(amountA, 100 ether);
        assertEq(amountB, 100 ether);

        assertEq(
            tokenA.balanceOf(liquidityProvider),
            providerTokenABefore + 100 ether
        );
        assertEq(
            tokenB.balanceOf(liquidityProvider),
            providerTokenBBefore + 100 ether
        );

        (uint112 reserveA, uint112 reserveB) = amm.getReserves();

        assertEq(reserveA, 900 ether);
        assertEq(reserveB, 900 ether);
    }

    function test_RemoveLiquidity_RevertsWhenLiquidityIsZero() public {
        _addDefaultLiquidity();

        vm.prank(liquidityProvider);
        vm.expectRevert(abi.encodeWithSelector(ZeroAmount.selector));

        amm.removeLiquidity(
            0,
            0,
            0,
            liquidityProvider
        );
    }

    function test_RemoveLiquidity_RevertsWhenAmountAIsBelowMinimum() public {
        _addDefaultLiquidity();

        vm.prank(liquidityProvider);
        vm.expectRevert(
            abi.encodeWithSelector(
                SlippageExceeded.selector,
                100 ether,
                101 ether
            )
        );

        amm.removeLiquidity(
            100 ether,
            101 ether,
            0,
            liquidityProvider
        );
    }

    function test_RemoveLiquidity_RevertsWhenAmountBIsBelowMinimum() public {
        _addDefaultLiquidity();

        vm.prank(liquidityProvider);
        vm.expectRevert(
            abi.encodeWithSelector(
                SlippageExceeded.selector,
                100 ether,
                101 ether
            )
        );

        amm.removeLiquidity(
            100 ether,
            0,
            101 ether,
            liquidityProvider
        );
    }

    // -------------------------------------------------------------------------
    // swapExactTokensForTokens
    // -------------------------------------------------------------------------

    function test_SwapExactTokensForTokens_AtoBTransfersOutputAndUpdatesReserves() public {
        _addDefaultLiquidity();

        uint256 amountIn = 100 ether;
        (uint112 reserveABefore, uint112 reserveBBefore) = amm.getReserves();

        uint256 expectedOut = amm.getAmountOut(
            amountIn,
            reserveABefore,
            reserveBBefore
        );

        uint256 traderTokenBBefore = tokenB.balanceOf(trader);

        vm.prank(trader);
        uint256 amountOut = amm.swapExactTokensForTokens(
            amountIn,
            0,
            address(tokenA),
            trader
        );

        assertEq(amountOut, expectedOut);
        assertEq(tokenB.balanceOf(trader), traderTokenBBefore + expectedOut);

        (uint112 reserveAAfter, uint112 reserveBAfter) = amm.getReserves();

        assertEq(reserveAAfter, reserveABefore + amountIn);
        assertEq(reserveBAfter, reserveBBefore - expectedOut);
    }

    function test_SwapExactTokensForTokens_BtoATransfersOutputAndUpdatesReserves() public {
        _addDefaultLiquidity();

        uint256 amountIn = 100 ether;
        (uint112 reserveABefore, uint112 reserveBBefore) = amm.getReserves();

        uint256 expectedOut = amm.getAmountOut(
            amountIn,
            reserveBBefore,
            reserveABefore
        );

        uint256 traderTokenABefore = tokenA.balanceOf(trader);

        vm.prank(trader);
        uint256 amountOut = amm.swapExactTokensForTokens(
            amountIn,
            0,
            address(tokenB),
            trader
        );

        assertEq(amountOut, expectedOut);
        assertEq(tokenA.balanceOf(trader), traderTokenABefore + expectedOut);

        (uint112 reserveAAfter, uint112 reserveBAfter) = amm.getReserves();

        assertEq(reserveAAfter, reserveABefore - expectedOut);
        assertEq(reserveBAfter, reserveBBefore + amountIn);
    }

    function test_SwapExactTokensForTokens_RevertsWhenAmountInIsZero() public {
        _addDefaultLiquidity();

        vm.prank(trader);
        vm.expectRevert(abi.encodeWithSelector(ZeroAmount.selector));

        amm.swapExactTokensForTokens(
            0,
            0,
            address(tokenA),
            trader
        );
    }

    function test_SwapExactTokensForTokens_RevertsWhenTokenInIsInvalid() public {
        _addDefaultLiquidity();

        vm.prank(trader);
        vm.expectRevert(bytes("invalid tokenIn"));

        amm.swapExactTokensForTokens(
            100 ether,
            0,
            attacker,
            trader
        );
    }

    function test_SwapExactTokensForTokens_RevertsWhenPoolHasNoLiquidity() public {
        vm.prank(trader);
        vm.expectRevert(abi.encodeWithSelector(InsufficientLiquidity.selector));

        amm.swapExactTokensForTokens(
            100 ether,
            0,
            address(tokenA),
            trader
        );
    }

    function test_SwapExactTokensForTokens_RevertsWhenOutputIsBelowMinimum() public {
        _addDefaultLiquidity();

        uint256 amountIn = 100 ether;
        (uint112 reserveA, uint112 reserveB) = amm.getReserves();

        uint256 expectedOut = amm.getAmountOut(
            amountIn,
            reserveA,
            reserveB
        );

        vm.prank(trader);
        vm.expectRevert(
            abi.encodeWithSelector(
                SlippageExceeded.selector,
                expectedOut,
                expectedOut + 1
            )
        );

        amm.swapExactTokensForTokens(
            amountIn,
            expectedOut + 1,
            address(tokenA),
            trader
        );
    }

    function test_SwapExactTokensForTokens_RevertsWhenTinyInputProducesZeroOutput() public {
        _addDefaultLiquidity();

        vm.prank(trader);
        vm.expectRevert(abi.encodeWithSelector(InsufficientLiquidity.selector));

        amm.swapExactTokensForTokens(
            1,
            0,
            address(tokenA),
            trader
        );
    }

    // -------------------------------------------------------------------------
    // getAmountOut
    // -------------------------------------------------------------------------

    function test_GetAmountOut_Uses997Over1000FeeFormula() public view {
        uint256 amountIn = 100 ether;
        uint256 reserveIn = 1_000 ether;
        uint256 reserveOut = 1_000 ether;

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

    function test_GetAmountOut_RevertsWhenReserveInIsZero() public {
        vm.expectRevert(abi.encodeWithSelector(InsufficientLiquidity.selector));

        amm.getAmountOut(
            100 ether,
            0,
            1_000 ether
        );
    }

    function test_GetAmountOut_RevertsWhenReserveOutIsZero() public {
        vm.expectRevert(abi.encodeWithSelector(InsufficientLiquidity.selector));

        amm.getAmountOut(
            100 ether,
            1_000 ether,
            0
        );
    }

    // -------------------------------------------------------------------------
    // Pause / unpause
    // -------------------------------------------------------------------------

    function test_PauseAndUnpause_AdminControlsAMMState() public {
        assertFalse(amm.paused());

        vm.prank(admin);
        amm.pause();

        assertTrue(amm.paused());

        vm.prank(admin);
        amm.unpause();

        assertFalse(amm.paused());
    }

    function test_Pause_RevertsWhenCallerIsNotAdmin() public {
        vm.prank(attacker);
        vm.expectRevert(bytes("not admin"));

        amm.pause();
    }

    function test_Unpause_RevertsWhenCallerIsNotAdmin() public {
        vm.prank(admin);
        amm.pause();

        vm.prank(attacker);
        vm.expectRevert(bytes("not admin"));

        amm.unpause();
    }

    function test_AddLiquidity_RevertsWhenAMMIsPaused() public {
        vm.prank(admin);
        amm.pause();

        vm.prank(liquidityProvider);
        vm.expectRevert();

        amm.addLiquidity(
            INITIAL_A,
            INITIAL_B,
            0,
            0,
            liquidityProvider
        );
    }

    function test_RemoveLiquidity_RevertsWhenAMMIsPaused() public {
        _addDefaultLiquidity();

        vm.prank(admin);
        amm.pause();

        vm.prank(liquidityProvider);
        vm.expectRevert();

        amm.removeLiquidity(
            100 ether,
            0,
            0,
            liquidityProvider
        );
    }

    function test_SwapExactTokensForTokens_RevertsWhenAMMIsPaused() public {
        _addDefaultLiquidity();

        vm.prank(admin);
        amm.pause();

        vm.prank(trader);
        vm.expectRevert();

        amm.swapExactTokensForTokens(
            100 ether,
            0,
            address(tokenA),
            trader
        );
    }

    // -------------------------------------------------------------------------
    // Yul sqrt benchmark helper coverage
    // -------------------------------------------------------------------------

    function test_SqrtAssembly_MatchesSolidityForZero() public view {
        assertEq(
            harness.sqrtAssemblyExternal(0),
            harness.sqrtSolidityExternal(0)
        );
    }

    function test_SqrtAssembly_MatchesSolidityForPerfectSquare() public view {
        uint256 value = 10_000;

        assertEq(
            harness.sqrtAssemblyExternal(value),
            harness.sqrtSolidityExternal(value)
        );
        assertEq(harness.sqrtAssemblyExternal(value), 100);
    }

    function test_SqrtAssembly_MatchesSolidityForLargeNonPerfectSquare() public view {
        uint256 value = 987_654_321_123_456_789;

        assertEq(
            harness.sqrtAssemblyExternal(value),
            harness.sqrtSolidityExternal(value)
        );
    }
}
