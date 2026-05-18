// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {
    ERC20PermitUpgradeable
} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IChainlinkOracleAdapter} from "./interfaces/IChainlinkOracleAdapter.sol";
import {InvalidAsset, TransferRestricted, ZeroAddress} from "./interfaces/IRWATypes.sol";

/// @title AssetTokenV1
/// @notice UUPS-upgradeable ERC-20 representing a real-world asset backed by collateral.
///         Minting is role-gated to authorized issuers. Transfers pause when the contract
///         is paused. Price is fetched on-demand from the ChainlinkOracleAdapter.
///
/// Design patterns: UUPS Proxy, AccessControl, Pausable, CEI, ReentrancyGuard.
///
/// Storage layout: ERC-7201 namespaced struct — safe to extend in V2 without collision.
contract AssetTokenV1 is
    ERC20Upgradeable,
    ERC20PermitUpgradeable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable
{
    // -------------------------------------------------------------------------
    // Roles
    // -------------------------------------------------------------------------

    bytes32 public constant ISSUER_ROLE = keccak256("ISSUER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    // -------------------------------------------------------------------------
    // ERC-7201 namespaced storage
    // -------------------------------------------------------------------------

    /// @custom:storage-location erc7201:rwa.AssetTokenV1
    struct AssetTokenV1Storage {
        IChainlinkOracleAdapter oracle;
        bytes32 assetId;
        uint256 maxSupply; // 0 = uncapped
    }

    function _getStorage() internal pure returns (AssetTokenV1Storage storage $) {
        // keccak256(abi.encode(uint256(keccak256("rwa.AssetTokenV1")) - 1)) & ~bytes32(uint256(0xff))
        bytes32 slot =
            keccak256(abi.encode(uint256(keccak256(bytes("rwa.AssetTokenV1"))) - 1)) & ~bytes32(uint256(0xff));
        // solhint-disable-next-line no-inline-assembly
        assembly {
            $.slot := slot
        }
    }

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // -------------------------------------------------------------------------
    // Initializer
    // -------------------------------------------------------------------------

    /// @notice Initializes the proxy. Called once by the factory or deploy script.
    function initialize(
        string calldata name_,
        string calldata symbol_,
        address oracle_,
        bytes32 assetId_,
        uint256 maxSupply_,
        address admin_
    ) external initializer {
        if (oracle_ == address(0) || admin_ == address(0)) revert ZeroAddress();

        __ERC20_init(name_, symbol_);
        __ERC20Permit_init(name_);
        __AccessControl_init();
        __Pausable_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();

        AssetTokenV1Storage storage $ = _getStorage();
        $.oracle = IChainlinkOracleAdapter(oracle_);
        $.assetId = assetId_;
        $.maxSupply = maxSupply_;

        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
        _grantRole(ISSUER_ROLE, admin_);
        _grantRole(PAUSER_ROLE, admin_);
        _grantRole(UPGRADER_ROLE, admin_);
    }

    // -------------------------------------------------------------------------
    // Issuance
    // -------------------------------------------------------------------------

    /// @notice Mints asset tokens to `to`. Checks-Effects-Interactions: state written
    ///         before any external call (transfer to recipient is the sole interaction).
    function mint(address to, uint256 amount) external virtual onlyRole(ISSUER_ROLE) whenNotPaused nonReentrant {
        if (to == address(0)) revert ZeroAddress();
        AssetTokenV1Storage storage $ = _getStorage();
        // Check: cap not exceeded
        if ($.maxSupply > 0 && totalSupply() + amount > $.maxSupply) revert InvalidAsset($.assetId);
        // Effects + Interaction (ERC20._mint emits Transfer)
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external virtual onlyRole(ISSUER_ROLE) {
        _burn(from, amount);
    }

    // -------------------------------------------------------------------------
    // Oracle
    // -------------------------------------------------------------------------

    function getAssetPrice() external view virtual returns (uint256 price18, uint256 updatedAt) {
        AssetTokenV1Storage storage $ = _getStorage();
        return $.oracle.getPrice($.assetId);
    }

    function assetId() external view returns (bytes32) {
        return _getStorage().assetId;
    }

    function oracle() external view returns (address) {
        return address(_getStorage().oracle);
    }

    // -------------------------------------------------------------------------
    // Admin
    // -------------------------------------------------------------------------

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    function setOracle(address oracle_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (oracle_ == address(0)) revert ZeroAddress();
        _getStorage().oracle = IChainlinkOracleAdapter(oracle_);
    }

    // -------------------------------------------------------------------------
    // OZ v5 required overrides
    // -------------------------------------------------------------------------

    /// @dev Blocks all transfers (including mint/burn) when paused.
    function _update(address from, address to, uint256 value)
        internal
        virtual
        override(ERC20Upgradeable)
        whenNotPaused
    {
        super._update(from, to, value);
    }

    /// @dev Only UPGRADER_ROLE (should be the DAO Timelock) can authorize upgrades.
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) {}
}
