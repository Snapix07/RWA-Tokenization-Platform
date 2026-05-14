// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {ERC4626Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IChainlinkOracleAdapter} from "./interfaces/IChainlinkOracleAdapter.sol";
import {DepositCapExceeded, ZeroAddress, ZeroAmount} from "./interfaces/IRWATypes.sol";

/// @title RWAVault
/// @notice UUPS-upgradeable ERC-4626 tokenized yield vault. Accepts an AssetToken as
///         the underlying asset and issues vault shares. Yield is injected by a trusted
///         YIELD_MANAGER_ROLE (e.g. a yield aggregator or the DAO Timelock).
///         Rounding always favours the vault: deposits/mints round down, withdrawals/redeems
///         round up — enforced by OZ ERC4626's Math.mulDiv with explicit Rounding flags.
///
/// Design patterns: UUPS Proxy, ERC-4626, AccessControl, Pausable, CEI, ReentrancyGuard.
contract RWAVault is
    ERC4626Upgradeable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20 for IERC20;

    // -------------------------------------------------------------------------
    // Roles
    // -------------------------------------------------------------------------

    bytes32 public constant YIELD_MANAGER_ROLE = keccak256("YIELD_MANAGER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    // -------------------------------------------------------------------------
    // ERC-7201 namespaced storage
    // -------------------------------------------------------------------------

    /// @custom:storage-location erc7201:rwa.RWAVault
    struct RWAVaultStorage {
        IChainlinkOracleAdapter oracle;
        bytes32 assetId;
        uint256 accruedYield; // yield injected by YIELD_MANAGER, included in totalAssets
        uint256 depositCap; // max underlying tokens the vault accepts; 0 = uncapped
    }

    function _getStorage() private pure returns (RWAVaultStorage storage $) {
        bytes32 slot = keccak256(abi.encode(uint256(keccak256(bytes("rwa.RWAVault"))) - 1)) & ~bytes32(uint256(0xff));
        // solhint-disable-next-line no-inline-assembly
        assembly {
            $.slot := slot
        }
    }

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    event YieldCollected(address indexed manager, uint256 amount);
    event DepositCapUpdated(uint256 newCap);

    // -------------------------------------------------------------------------
    // Initializer
    // -------------------------------------------------------------------------

    function initialize(
        address asset_,
        string calldata shareName_,
        string calldata shareSymbol_,
        address oracle_,
        bytes32 assetId_,
        uint256 depositCap_,
        address admin_
    ) external initializer {
        if (asset_ == address(0) || admin_ == address(0)) revert ZeroAddress();

        __ERC20_init(shareName_, shareSymbol_);
        __ERC4626_init(IERC20(asset_));
        __AccessControl_init();
        __Pausable_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();

        RWAVaultStorage storage $ = _getStorage();
        $.oracle = IChainlinkOracleAdapter(oracle_);
        $.assetId = assetId_;
        $.depositCap = depositCap_;

        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
        _grantRole(YIELD_MANAGER_ROLE, admin_);
        _grantRole(PAUSER_ROLE, admin_);
        _grantRole(UPGRADER_ROLE, admin_);
    }

    // -------------------------------------------------------------------------
    // ERC-4626 core overrides
    // -------------------------------------------------------------------------

    /// @dev totalAssets includes both the underlying token balance and any accrued yield.
    function totalAssets() public view override returns (uint256) {
        return IERC20(asset()).balanceOf(address(this)) + _getStorage().accruedYield;
    }

    /// @dev Blocks deposits when paused or when the deposit cap would be exceeded.
    function _deposit(address caller, address receiver, uint256 assets, uint256 shares)
        internal
        override
        whenNotPaused
        nonReentrant
    {
        if (assets == 0) revert ZeroAmount();
        RWAVaultStorage storage $ = _getStorage();
        if ($.depositCap > 0 && totalAssets() + assets > $.depositCap) {
            revert DepositCapExceeded(assets, $.depositCap - totalAssets());
        }
        // CEI: effects (share minting) happen inside super._deposit before the transfer
        super._deposit(caller, receiver, assets, shares);
    }

    /// @dev Blocks withdrawals when paused.
    function _withdraw(address caller, address receiver, address owner, uint256 assets, uint256 shares)
        internal
        override
        whenNotPaused
        nonReentrant
    {
        super._withdraw(caller, receiver, owner, assets, shares);
    }

    // -------------------------------------------------------------------------
    // Yield management
    // -------------------------------------------------------------------------

    /// @notice Injects yield into the vault. Increases totalAssets without minting shares,
    ///         which appreciates the share price for existing holders.
    function collectYield(uint256 amount) external onlyRole(YIELD_MANAGER_ROLE) {
        if (amount == 0) revert ZeroAmount();
        // Effects first (CEI)
        _getStorage().accruedYield += amount;
        // Interaction: pull yield tokens from the manager
        IERC20(asset()).safeTransferFrom(msg.sender, address(this), amount);
        emit YieldCollected(msg.sender, amount);
    }

    // -------------------------------------------------------------------------
    // Oracle / NAV
    // -------------------------------------------------------------------------

    /// @notice Returns the current NAV per share in USD (18 decimals) via the oracle.
    function navPerShare() external view returns (uint256) {
        RWAVaultStorage storage $ = _getStorage();
        (uint256 price18,) = $.oracle.getPrice($.assetId);
        uint256 supply = totalSupply();
        if (supply == 0) return price18;
        return Math.mulDiv(price18, totalAssets(), supply);
    }

    // -------------------------------------------------------------------------
    // Admin
    // -------------------------------------------------------------------------

    function setDepositCap(uint256 cap) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _getStorage().depositCap = cap;
        emit DepositCapUpdated(cap);
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    // -------------------------------------------------------------------------
    // UUPS
    // -------------------------------------------------------------------------

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) {}
}
