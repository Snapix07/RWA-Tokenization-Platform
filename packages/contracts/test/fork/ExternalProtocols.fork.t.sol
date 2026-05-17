// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {IERC20Metadata} from
    "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

interface IChainlinkAggregatorV3 {
    function decimals() external view returns (uint8);

    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );
}

interface IUniswapV2Router02 {
    function factory() external pure returns (address);
    function WETH() external pure returns (address);

    function getAmountsOut(uint256 amountIn, address[] calldata path)
        external
        view
        returns (uint256[] memory amounts);
}

interface IUniswapV2Factory {
    function getPair(address tokenA, address tokenB)
        external
        view
        returns (address pair);
}

interface IUniswapV2Pair {
    function token0() external view returns (address);
    function token1() external view returns (address);

    function getReserves()
        external
        view
        returns (
            uint112 reserve0,
            uint112 reserve1,
            uint32 blockTimestampLast
        );
}

contract ExternalProtocolsForkTest is Test {

    address internal constant BASE_USDC =
        0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;

    address internal constant BASE_CHAINLINK_ETH_USD =
        0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70;

    address internal constant BASE_UNISWAP_V2_ROUTER =
        0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24;

    address internal constant BASE_UNISWAP_V2_FACTORY =
        0x8909Dc15e40173Ff4699343b6eB8132c65e18eC6;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("base"));
    }


    function testFork_BaseUSDC_HasExpectedMetadataAndLiveSupply() public view {
        IERC20Metadata usdc = IERC20Metadata(BASE_USDC);

        assertGt(BASE_USDC.code.length, 0);

        assertEq(usdc.name(), "USD Coin");
        assertEq(usdc.symbol(), "USDC");
        assertEq(usdc.decimals(), 6);

        assertGt(usdc.totalSupply(), 0);
    }

    function testFork_ChainlinkEthUsdFeed_ReturnsPositiveLivePrice() public view {
        IChainlinkAggregatorV3 feed =
            IChainlinkAggregatorV3(BASE_CHAINLINK_ETH_USD);

        assertGt(BASE_CHAINLINK_ETH_USD.code.length, 0);
        assertEq(feed.decimals(), 8);

        (
            uint80 roundId,
            int256 answer,
            ,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = feed.latestRoundData();

        assertGt(roundId, 0);
        assertGt(answer, 0);
        assertGt(updatedAt, 0);
        assertLe(updatedAt, block.timestamp);
        assertGt(answeredInRound, 0);
    }

    function testFork_UniswapV2Router_QuotesWethToUsdcThroughLivePool() public view {
        IUniswapV2Router02 router =
            IUniswapV2Router02(BASE_UNISWAP_V2_ROUTER);

        assertGt(BASE_UNISWAP_V2_ROUTER.code.length, 0);
        assertEq(router.factory(), BASE_UNISWAP_V2_FACTORY);

        address weth = router.WETH();

        assertGt(weth.code.length, 0);

        address pair = IUniswapV2Factory(BASE_UNISWAP_V2_FACTORY)
            .getPair(weth, BASE_USDC);

        assertTrue(pair != address(0));
        assertGt(pair.code.length, 0);

        IUniswapV2Pair livePair = IUniswapV2Pair(pair);

        address token0 = livePair.token0();
        address token1 = livePair.token1();

        bool hasCorrectTokens =
            (token0 == weth && token1 == BASE_USDC) ||
            (token0 == BASE_USDC && token1 == weth);

        assertTrue(hasCorrectTokens);

        (uint112 reserve0, uint112 reserve1,) = livePair.getReserves();

        assertGt(reserve0, 0);
        assertGt(reserve1, 0);

        address[] memory path = new address[](2);
        path[0] = weth;
        path[1] = BASE_USDC;

        uint256[] memory amounts =
            router.getAmountsOut(1 ether, path);

        assertEq(amounts.length, 2);
        assertEq(amounts[0], 1 ether);
        assertGt(amounts[1], 0);
    }
}
