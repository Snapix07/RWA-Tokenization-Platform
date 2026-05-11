// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IRWATypes
/// @notice Shared enums, structs, custom errors, and events for the RWA Tokenization Platform.
///         All contracts import from here to ensure naming consistency across the system.

// ---------------------------------------------------------------------------
// Enums
// ---------------------------------------------------------------------------

enum AssetClass {
    REAL_ESTATE,
    COMMODITY,
    PRIVATE_CREDIT,
    INFRASTRUCTURE
}

// ---------------------------------------------------------------------------
// Structs
// ---------------------------------------------------------------------------

/// @dev Metadata attached to every onboarded real-world asset.
struct AssetMetadata {
    bytes32 isin; // ISO 6166 identifier (or platform-specific ISIN equivalent)
    AssetClass class;
    uint256 faceValueUSD; // face value in USD, scaled to 18 decimals
    string metadataURI; // IPFS/Arweave URI pointing to legal document hash
}

// ---------------------------------------------------------------------------
// Custom Errors
// ---------------------------------------------------------------------------

/// @dev Caller does not have the required role or permission.
error Unauthorized();

/// @dev Chainlink price feed returned data older than the configured max staleness.
error StalePrice(uint256 updatedAt, uint256 maxStaleness);

/// @dev AMM swap output fell below the caller-supplied minimum.
error SlippageExceeded(uint256 amountOut, uint256 amountOutMin);

/// @dev The referenced asset has not been onboarded or is in an invalid state.
error InvalidAsset(bytes32 assetId);

/// @dev A zero-value was supplied where a non-zero value is required.
error ZeroAmount();

/// @dev A deposit would push the vault TVL above the configured cap.
error DepositCapExceeded(uint256 requested, uint256 remaining);

/// @dev Token transfers are restricted (e.g. asset is paused or compliance freeze).
error TransferRestricted(address from, address to);

/// @dev Recipient has not passed KYC approval.
error KYCRequired(address account);

/// @dev AMM reserves are insufficient for the requested swap or liquidity removal.
error InsufficientLiquidity();

/// @dev A contract has already been initialized and cannot be re-initialized at this version.
error AlreadyInitialized();

/// @dev The supplied address is the zero address where a non-zero address is required.
error ZeroAddress();

/// @dev Factory CREATE2 deployment: an asset token already exists for this assetId.
error AssetAlreadyDeployed(bytes32 assetId);

/// @dev The requested upgrade is not authorized.
error UpgradeNotAuthorized();

// ---------------------------------------------------------------------------
// Events
// ---------------------------------------------------------------------------

/// @dev Emitted when a new real-world asset is onboarded to the platform.
event AssetOnboarded(bytes32 indexed assetId, AssetClass class, address indexed token, address indexed nft);

/// @dev Emitted when the Chainlink oracle feed for an asset is added or updated.
event OracleFeedUpdated(bytes32 indexed assetId, address oldFeed, address newFeed);

/// @dev Emitted when an authorized issuer completes an issuance (mints tokens against collateral).
event IssuanceCompleted(bytes32 indexed assetId, address indexed issuer, address indexed recipient, uint256 amount);
