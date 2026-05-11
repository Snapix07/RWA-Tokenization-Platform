// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IChainlinkAggregator
/// @notice Minimal interface for Chainlink AggregatorV3 price feeds.
///         Defined inline to avoid a Chainlink npm dependency — the standard Foundry approach.
interface IChainlinkAggregator {
    /// @notice Returns the latest round data from the feed.
    /// @return roundId       The round ID.
    /// @return answer        The price answer (may be negative for some feeds — always validate > 0).
    /// @return startedAt     Timestamp when the round started.
    /// @return updatedAt     Timestamp of the last update; used for staleness checks.
    /// @return answeredInRound The round in which the answer was computed.
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);

    /// @notice Returns the number of decimals in the feed's answer (typically 8 for USD feeds).
    function decimals() external view returns (uint8);

    /// @notice Human-readable description of the feed (e.g. "ETH / USD").
    function description() external view returns (string memory);
}
