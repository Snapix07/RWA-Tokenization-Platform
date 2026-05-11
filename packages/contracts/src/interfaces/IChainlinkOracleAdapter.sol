// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IChainlinkOracleAdapter
/// @notice Minimal interface consumed by AssetTokenV1 and RWAVault to fetch asset prices.
interface IChainlinkOracleAdapter {
    function getPrice(bytes32 assetId) external view returns (uint256 price18, uint256 updatedAt);
}
