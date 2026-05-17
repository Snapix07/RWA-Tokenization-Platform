// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {IChainlinkAggregator} from "./interfaces/IChainlinkAggregator.sol";
import {IChainlinkOracleAdapter} from "./interfaces/IChainlinkOracleAdapter.sol";
import {InvalidAsset, OracleFeedUpdated, StalePrice, ZeroAddress} from "./interfaces/IRWATypes.sol";

/// @title ChainlinkOracleAdapter
/// @notice Wraps Chainlink AggregatorV3 feeds with staleness checks and 18-decimal
///         normalization. Acts as the single oracle interface for all platform contracts.
///
/// Design patterns: OracleAdapter (interface abstraction), Pausable (circuit breaker).
contract ChainlinkOracleAdapter is IChainlinkOracleAdapter, Ownable, Pausable {
    // -------------------------------------------------------------------------
    // Storage
    // -------------------------------------------------------------------------

    struct FeedConfig {
        address feed; // 20 bytes
        uint96 maxStaleness; // 12 bytes — packed with feed into one 32-byte slot
    }

    mapping(bytes32 => FeedConfig) private _feeds;

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    event FeedAdded(bytes32 indexed assetId, address feed, uint96 maxStaleness);
    event FeedRemoved(bytes32 indexed assetId, address removedFeed);

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    constructor(address initialOwner) Ownable(initialOwner) {}

    // -------------------------------------------------------------------------
    // Feed management (owner only)
    // -------------------------------------------------------------------------

    function addFeed(bytes32 assetId, address feed, uint96 maxStaleness) external onlyOwner {
        if (feed == address(0)) revert ZeroAddress();
        address old = _feeds[assetId].feed;
        _feeds[assetId] = FeedConfig({feed: feed, maxStaleness: maxStaleness});
        emit OracleFeedUpdated(assetId, old, feed);
        emit FeedAdded(assetId, feed, maxStaleness);
    }

    function removeFeed(bytes32 assetId) external onlyOwner {
        address old = _feeds[assetId].feed;
        if (old == address(0)) revert InvalidAsset(assetId);
        delete _feeds[assetId];
        emit OracleFeedUpdated(assetId, old, address(0));
        emit FeedRemoved(assetId, old);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // -------------------------------------------------------------------------
    // Price query
    // -------------------------------------------------------------------------

    /// @notice Returns the latest price for an asset, normalized to 18 decimals.
    /// @param  assetId   The keccak256 asset identifier registered via addFeed.
    /// @return price18   Price scaled to 18 decimals.
    /// @return updatedAt Timestamp of the latest Chainlink round.
    function getPrice(bytes32 assetId) external view whenNotPaused returns (uint256 price18, uint256 updatedAt) {
        FeedConfig memory cfg = _feeds[assetId];
        if (cfg.feed == address(0)) revert InvalidAsset(assetId);

        (, int256 answer,, uint256 ts,) = IChainlinkAggregator(cfg.feed).latestRoundData();

        // Checks: validate answer and staleness before any state reads
        if (answer <= 0) revert InvalidAsset(assetId);
        //slither-disable-next-line timestamp
        if (block.timestamp - ts > cfg.maxStaleness) revert StalePrice(ts, cfg.maxStaleness);

        uint8 feedDecimals = IChainlinkAggregator(cfg.feed).decimals();
        price18 = _normalizePriceAssembly(answer, feedDecimals);
        updatedAt = ts;
    }

    function getFeedConfig(bytes32 assetId) external view returns (address feed, uint96 maxStaleness) {
        FeedConfig memory cfg = _feeds[assetId];
        feed = cfg.feed;
        maxStaleness = cfg.maxStaleness;
    }

    // -------------------------------------------------------------------------
    // Price normalization — Yul assembly vs pure-Solidity benchmark
    //
    // _normalizePriceAssembly saves ~40 gas per call by using the EVM EXP opcode
    // directly and skipping Solidity's checked-arithmetic JUMPI instructions that
    // wrap every ** operation in 0.8.x. Benchmarked with forge test --gas-report
    // on solc 0.8.24 -O200; results are recorded in the gas optimization report.
    //
    // Both functions are internal so the test suite can inherit this contract and
    // call both variants to produce the before/after comparison table.
    // -------------------------------------------------------------------------

    /// @dev Production path — normalizes answer from feedDecimals to 18 using inline Yul.
    ///      Uses the EVM EXP opcode directly; no Solidity overflow-check boilerplate.
    function _normalizePriceAssembly(int256 answer, uint8 feedDecimals) internal pure returns (uint256 result) {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            switch lt(feedDecimals, 18)
            case 1 { result := mul(answer, exp(10, sub(18, feedDecimals))) }
            default {
                switch gt(feedDecimals, 18)
                case 1 { result := div(answer, exp(10, sub(feedDecimals, 18))) }
                default { result := answer }
            }
        }
    }

    //slither-disable-next-line dead-code
    /// @dev Benchmark baseline — pure-Solidity equivalent of _normalizePriceAssembly.
    ///      Kept alongside the assembly version for the gas report; not called in production.
    function _normalizePriceSolidity(int256 answer, uint8 feedDecimals) internal pure returns (uint256) {
        if (feedDecimals < 18) {
            // casting to uint256 is safe: caller validates answer > 0 before this call
            // forge-lint: disable-next-line(unsafe-typecast)
            return uint256(answer) * (10 ** (18 - feedDecimals));
        }
        if (feedDecimals > 18) {
            // forge-lint: disable-next-line(unsafe-typecast)
            return uint256(answer) / (10 ** (feedDecimals - 18));
        }
        // forge-lint: disable-next-line(unsafe-typecast)
        return uint256(answer);
    }
}
