// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AssetTokenV1} from "./AssetTokenV1.sol";
import {KYCRequired, ZeroAddress} from "./interfaces/IRWATypes.sol";

/// @title AssetTokenV2
/// @notice UUPS upgrade of AssetTokenV1. Adds per-address KYC approval and an
///         optional protocol fee on minting. New storage is in a separate ERC-7201
///         namespace so it never collides with V1 slots.
///
/// Upgrade path: deploy this contract as a new implementation, then call
/// `upgradeToAndCall(address(v2Impl), abi.encodeCall(AssetTokenV2.initializeV2, (...)))`
/// through the proxy. The `reinitializer(2)` modifier prevents re-execution.
contract AssetTokenV2 is AssetTokenV1 {
    // -------------------------------------------------------------------------
    // Roles (added in V2)
    // -------------------------------------------------------------------------

    bytes32 public constant COMPLIANCE_ROLE = keccak256("COMPLIANCE_ROLE");

    // -------------------------------------------------------------------------
    // ERC-7201 namespaced storage (separate namespace from V1 — no collision)
    // -------------------------------------------------------------------------

    /// @custom:storage-location erc7201:rwa.AssetTokenV2
    struct AssetTokenV2Storage {
        mapping(address => bool) kycApproved;
        uint256 mintFeeBps; // basis points, e.g. 50 = 0.5%
        address feeRecipient;
        bool kycEnabled; // allows disabling KYC check without revoking all approvals
    }

    function _getV2Storage() internal pure returns (AssetTokenV2Storage storage $) {
        // keccak256(abi.encode(uint256(keccak256("rwa.AssetTokenV2")) - 1)) & ~bytes32(uint256(0xff))
        bytes32 slot =
            keccak256(abi.encode(uint256(keccak256(bytes("rwa.AssetTokenV2"))) - 1)) & ~bytes32(uint256(0xff));
        // solhint-disable-next-line no-inline-assembly
        assembly {
            $.slot := slot
        }
    }

    // -------------------------------------------------------------------------
    // V2 initializer
    // -------------------------------------------------------------------------

    /// @notice Called via upgradeToAndCall immediately after upgrading to V2.
    ///         The reinitializer(2) modifier ensures it can only run once.
    function initializeV2(address feeRecipient_, uint256 mintFeeBps_, bool kycEnabled_) external reinitializer(2) {
        if (mintFeeBps_ > 0 && feeRecipient_ == address(0)) revert ZeroAddress();

        AssetTokenV2Storage storage $ = _getV2Storage();
        $.feeRecipient = feeRecipient_;
        $.mintFeeBps = mintFeeBps_;
        $.kycEnabled = kycEnabled_;

        _grantRole(COMPLIANCE_ROLE, msg.sender);
    }

    // -------------------------------------------------------------------------
    // KYC management
    // -------------------------------------------------------------------------

    function approveKYC(address account) external onlyRole(COMPLIANCE_ROLE) {
        _getV2Storage().kycApproved[account] = true;
    }

    function revokeKYC(address account) external onlyRole(COMPLIANCE_ROLE) {
        _getV2Storage().kycApproved[account] = false;
    }

    function setKYCEnabled(bool enabled) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _getV2Storage().kycEnabled = enabled;
    }

    function isKYCApproved(address account) external view returns (bool) {
        return _getV2Storage().kycApproved[account];
    }

    // -------------------------------------------------------------------------
    // Fee management
    // -------------------------------------------------------------------------

    function setMintFee(uint256 bps) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(bps <= 1000, "fee > 10%");
        _getV2Storage().mintFeeBps = bps;
    }

    function setFeeRecipient(address recipient) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (recipient == address(0)) revert ZeroAddress();
        _getV2Storage().feeRecipient = recipient;
    }

    // -------------------------------------------------------------------------
    // Overrides
    // -------------------------------------------------------------------------

    /// @dev Overrides V1 mint to deduct a protocol fee before minting to the recipient.
    function mint(address to, uint256 amount) external override onlyRole(ISSUER_ROLE) whenNotPaused nonReentrant {
        if (to == address(0)) revert ZeroAddress();

        AssetTokenV2Storage storage $ = _getV2Storage();

        // Check KYC if enabled
        if ($.kycEnabled && !$.kycApproved[to]) revert KYCRequired(to);

        // Deduct protocol fee
        uint256 fee = (amount * $.mintFeeBps) / 10_000;
        if (fee > 0 && $.feeRecipient != address(0)) {
            _mint($.feeRecipient, fee);
        }
        _mint(to, amount - fee);
    }

    /// @dev Adds KYC check on transfers. Pausing is enforced by V1's _update override.
    function _update(address from, address to, uint256 value) internal override(AssetTokenV1) {
        AssetTokenV2Storage storage $ = _getV2Storage();
        // KYC check on transfers (not on burns: to == address(0))
        if (to != address(0) && $.kycEnabled && !$.kycApproved[to]) revert KYCRequired(to);
        super._update(from, to, value);
    }
}
