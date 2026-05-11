// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IChainlinkAggregator} from "../interfaces/IChainlinkAggregator.sol";

/// @title MockAggregator
/// @notice Test double for Chainlink AggregatorV3. Lets tests and testnet scripts
///         set arbitrary price/timestamp values without needing a live feed.
contract MockAggregator is IChainlinkAggregator {
    int256 private _answer;
    uint256 private _updatedAt;
    uint8 private _decimals;
    uint80 private _roundId;
    address public owner;

    error NotOwner();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    constructor(int256 initialAnswer, uint8 decimals_) {
        owner = msg.sender;
        _answer = initialAnswer;
        _decimals = decimals_;
        _updatedAt = block.timestamp;
        _roundId = 1;
    }

    // -------------------------------------------------------------------------
    // IChainlinkAggregator
    // -------------------------------------------------------------------------

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (_roundId, _answer, _updatedAt, _updatedAt, _roundId);
    }

    function decimals() external view returns (uint8) {
        return _decimals;
    }

    function description() external pure returns (string memory) {
        return "MockAggregator";
    }

    // -------------------------------------------------------------------------
    // Test helpers
    // -------------------------------------------------------------------------

    /// @notice Update price and advance the round counter.
    function setAnswer(int256 answer) external onlyOwner {
        _answer = answer;
        _updatedAt = block.timestamp;
        _roundId++;
    }

    /// @notice Simulate a stale feed by backdating the update timestamp.
    function setUpdatedAt(uint256 updatedAt) external onlyOwner {
        _updatedAt = updatedAt;
    }

    function setDecimals(uint8 decimals_) external onlyOwner {
        _decimals = decimals_;
    }
}
