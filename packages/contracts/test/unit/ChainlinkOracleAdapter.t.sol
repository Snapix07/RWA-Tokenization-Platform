// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {ChainlinkOracleAdapter} from "../../src/ChainlinkOracleAdapter.sol";
import {MockAggregator} from "../../src/mocks/MockAggregator.sol";

import {
    InvalidAsset,
    StalePrice,
    ZeroAddress
} from "../../src/interfaces/IRWATypes.sol";

contract ChainlinkOracleAdapterHarness is ChainlinkOracleAdapter {
    constructor(address initialOwner) ChainlinkOracleAdapter(initialOwner) {}

    function normalizeAssemblyExternal(int256 answer, uint8 feedDecimals)
        external
        pure
        returns (uint256)
    {
        return _normalizePriceAssembly(answer, feedDecimals);
    }

    function normalizeSolidityExternal(int256 answer, uint8 feedDecimals)
        external
        pure
        returns (uint256)
    {
        return _normalizePriceSolidity(answer, feedDecimals);
    }
}

contract ChainlinkOracleAdapterTest is Test {
    ChainlinkOracleAdapter internal oracle;
    ChainlinkOracleAdapterHarness internal harness;

    MockAggregator internal feed8;
    MockAggregator internal feed18;
    MockAggregator internal feed20;

    address internal owner = makeAddr("owner");
    address internal attacker = makeAddr("attacker");

    bytes32 internal constant ASSET_ID_1 = keccak256("RWA_REAL_ESTATE_001");
    bytes32 internal constant ASSET_ID_2 = keccak256("RWA_COMMODITY_002");
    bytes32 internal constant ASSET_ID_3 = keccak256("RWA_CREDIT_003");
    bytes32 internal constant UNKNOWN_ASSET = keccak256("UNKNOWN_ASSET");

    uint96 internal constant MAX_STALENESS = 1 days;

    event OracleFeedUpdated(bytes32 indexed assetId, address oldFeed, address newFeed);
    event FeedAdded(bytes32 indexed assetId, address feed, uint96 maxStaleness);
    event FeedRemoved(bytes32 indexed assetId, address removedFeed);

    function setUp() public {
        vm.warp(1_700_000_000);

        oracle = new ChainlinkOracleAdapter(owner);
        harness = new ChainlinkOracleAdapterHarness(owner);

        feed8 = new MockAggregator(int256(2_000e8), 8);
        feed18 = new MockAggregator(int256(3_000 ether), 18);
        feed20 = new MockAggregator(int256(2_500 * 10 ** 20), 20);

        _addFeed(ASSET_ID_1, address(feed8), MAX_STALENESS);
    }

    function _addFeed(bytes32 assetId, address feed, uint96 staleness) internal {
        vm.prank(owner);
        oracle.addFeed(assetId, feed, staleness);
    }

    function test_Constructor_SetsInitialOwner() public view {
        assertEq(oracle.owner(), owner);
    }

    function test_AddFeed_StoresFeedConfiguration() public {
        _addFeed(ASSET_ID_2, address(feed18), uint96(2 days));

        (address storedFeed, uint96 storedStaleness) = oracle.getFeedConfig(ASSET_ID_2);

        assertEq(storedFeed, address(feed18));
        assertEq(storedStaleness, uint96(2 days));
    }

    function test_AddFeed_UpdatesExistingFeedConfiguration() public {
        _addFeed(ASSET_ID_1, address(feed18), uint96(3 days));

        (address storedFeed, uint96 storedStaleness) = oracle.getFeedConfig(ASSET_ID_1);

        assertEq(storedFeed, address(feed18));
        assertEq(storedStaleness, uint96(3 days));
    }

    function test_AddFeed_EmitsOracleAndFeedAddedEvents() public {
        vm.expectEmit(true, false, false, true, address(oracle));
        emit OracleFeedUpdated(ASSET_ID_2, address(0), address(feed18));

        vm.expectEmit(true, false, false, true, address(oracle));
        emit FeedAdded(ASSET_ID_2, address(feed18), uint96(2 days));

        vm.prank(owner);
        oracle.addFeed(ASSET_ID_2, address(feed18), uint96(2 days));
    }

    function test_AddFeed_RevertsWhenFeedIsZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector));

        oracle.addFeed(ASSET_ID_2, address(0), MAX_STALENESS);
    }

    function test_AddFeed_RevertsWhenCallerIsNotOwner() public {
        vm.prank(attacker);
        vm.expectRevert();

        oracle.addFeed(ASSET_ID_2, address(feed18), MAX_STALENESS);
    }

    function test_RemoveFeed_DeletesStoredConfiguration() public {
        vm.prank(owner);
        oracle.removeFeed(ASSET_ID_1);

        (address storedFeed, uint96 storedStaleness) = oracle.getFeedConfig(ASSET_ID_1);

        assertEq(storedFeed, address(0));
        assertEq(storedStaleness, 0);
    }

    function test_RemoveFeed_EmitsOracleAndFeedRemovedEvents() public {
        vm.expectEmit(true, false, false, true, address(oracle));
        emit OracleFeedUpdated(ASSET_ID_1, address(feed8), address(0));

        vm.expectEmit(true, false, false, true, address(oracle));
        emit FeedRemoved(ASSET_ID_1, address(feed8));

        vm.prank(owner);
        oracle.removeFeed(ASSET_ID_1);
    }

    function test_RemoveFeed_RevertsForUnknownAsset() public {
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(InvalidAsset.selector, UNKNOWN_ASSET)
        );

        oracle.removeFeed(UNKNOWN_ASSET);
    }

    function test_RemoveFeed_RevertsWhenCallerIsNotOwner() public {
        vm.prank(attacker);
        vm.expectRevert();

        oracle.removeFeed(ASSET_ID_1);
    }

    function test_GetFeedConfig_ReturnsZeroValuesForUnknownAsset() public view {
        (address storedFeed, uint96 storedStaleness) =
            oracle.getFeedConfig(UNKNOWN_ASSET);

        assertEq(storedFeed, address(0));
        assertEq(storedStaleness, 0);
    }

    function test_PauseAndUnpause_OwnerControlsCircuitBreaker() public {
        assertFalse(oracle.paused());

        vm.prank(owner);
        oracle.pause();

        assertTrue(oracle.paused());

        vm.prank(owner);
        oracle.unpause();

        assertFalse(oracle.paused());
    }

    function test_Pause_RevertsWhenCallerIsNotOwner() public {
        vm.prank(attacker);
        vm.expectRevert();

        oracle.pause();
    }

    function test_Unpause_RevertsWhenCallerIsNotOwner() public {
        vm.prank(owner);
        oracle.pause();

        vm.prank(attacker);
        vm.expectRevert();

        oracle.unpause();
    }

    function test_GetPrice_NormalizesEightDecimalFeedToEighteenDecimals() public view {
        (uint256 price18, uint256 updatedAt) = oracle.getPrice(ASSET_ID_1);

        assertEq(price18, 2_000 ether);
        assertEq(updatedAt, block.timestamp);
    }

    function test_GetPrice_KeepsEighteenDecimalFeedUnchanged() public {
        _addFeed(ASSET_ID_2, address(feed18), MAX_STALENESS);

        (uint256 price18, uint256 updatedAt) = oracle.getPrice(ASSET_ID_2);

        assertEq(price18, 3_000 ether);
        assertEq(updatedAt, block.timestamp);
    }

    function test_GetPrice_DownscalesFeedWithMoreThanEighteenDecimals() public {
        _addFeed(ASSET_ID_3, address(feed20), MAX_STALENESS);

        (uint256 price18, uint256 updatedAt) = oracle.getPrice(ASSET_ID_3);

        assertEq(price18, 2_500 ether);
        assertEq(updatedAt, block.timestamp);
    }

    function test_GetPrice_ReflectsLatestMockAggregatorAnswer() public {
        feed8.setAnswer(int256(2_750e8));

        (uint256 price18,) = oracle.getPrice(ASSET_ID_1);

        assertEq(price18, 2_750 ether);
    }

    function test_GetPrice_SucceedsExactlyAtStalenessBoundary() public {
        uint256 boundaryTimestamp = block.timestamp - uint256(MAX_STALENESS);
        feed8.setUpdatedAt(boundaryTimestamp);

        (uint256 price18, uint256 updatedAt) = oracle.getPrice(ASSET_ID_1);

        assertEq(price18, 2_000 ether);
        assertEq(updatedAt, boundaryTimestamp);
    }

    function test_GetPrice_RevertsForUnknownAsset() public {
        vm.expectRevert(
            abi.encodeWithSelector(InvalidAsset.selector, UNKNOWN_ASSET)
        );

        oracle.getPrice(UNKNOWN_ASSET);
    }

    function test_GetPrice_RevertsWhenAggregatorAnswerIsZero() public {
        feed8.setAnswer(0);

        vm.expectRevert(
            abi.encodeWithSelector(InvalidAsset.selector, ASSET_ID_1)
        );

        oracle.getPrice(ASSET_ID_1);
    }

    function test_GetPrice_RevertsWhenAggregatorAnswerIsNegative() public {
        feed8.setAnswer(-1);

        vm.expectRevert(
            abi.encodeWithSelector(InvalidAsset.selector, ASSET_ID_1)
        );

        oracle.getPrice(ASSET_ID_1);
    }

    function test_GetPrice_RevertsWhenPriceIsStale() public {
        uint256 staleTimestamp =
            block.timestamp - uint256(MAX_STALENESS) - 1;

        feed8.setUpdatedAt(staleTimestamp);

        vm.expectRevert(
            abi.encodeWithSelector(
                StalePrice.selector,
                staleTimestamp,
                uint256(MAX_STALENESS)
            )
        );

        oracle.getPrice(ASSET_ID_1);
    }

    function test_GetPrice_RevertsWhenOracleIsPaused() public {
        vm.prank(owner);
        oracle.pause();

        vm.expectRevert();

        oracle.getPrice(ASSET_ID_1);
    }

    function test_Normalization_AssemblyMatchesSolidityForEightDecimals() public view {
        uint256 assemblyResult =
            harness.normalizeAssemblyExternal(int256(2_000e8), 8);

        uint256 solidityResult =
            harness.normalizeSolidityExternal(int256(2_000e8), 8);

        assertEq(assemblyResult, solidityResult);
        assertEq(assemblyResult, 2_000 ether);
    }

    function test_Normalization_AssemblyMatchesSolidityForEighteenDecimals() public view {
        uint256 assemblyResult =
            harness.normalizeAssemblyExternal(int256(3_000 ether), 18);

        uint256 solidityResult =
            harness.normalizeSolidityExternal(int256(3_000 ether), 18);

        assertEq(assemblyResult, solidityResult);
        assertEq(assemblyResult, 3_000 ether);
    }

    function test_Normalization_AssemblyMatchesSolidityForTwentyDecimals() public view {
        uint256 assemblyResult =
            harness.normalizeAssemblyExternal(int256(2_500 * 10 ** 20), 20);

        uint256 solidityResult =
            harness.normalizeSolidityExternal(int256(2_500 * 10 ** 20), 20);

        assertEq(assemblyResult, solidityResult);
        assertEq(assemblyResult, 2_500 ether);
    }

    function test_Harness_OwnerMatchesConfiguredOwner() public view {
        assertEq(harness.owner(), owner);
    }
}
