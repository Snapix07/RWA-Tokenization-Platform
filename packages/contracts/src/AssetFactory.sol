// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {AssetTokenV1} from "./AssetTokenV1.sol";
import {AssetAlreadyDeployed, ZeroAddress} from "./interfaces/IRWATypes.sol";

/// @title AssetFactory
/// @notice Deploys AssetTokenV1 ERC-1967 proxies using both CREATE (non-deterministic)
///         and CREATE2 (deterministic, address derivable from assetId off-chain).
///
/// Yul benchmark: _deployWithCreate2Assembly uses the EVM CREATE2 opcode directly;
/// _deployWithCreate uses the EVM CREATE opcode. Both are faster than the Solidity
/// `new ERC1967Proxy{salt:...}(...)` form because they skip Solidity's return-size check.
///
/// Design patterns: Factory (CREATE + CREATE2), AccessControl, Pausable.
contract AssetFactory is AccessControl, Pausable {
    bytes32 public constant FACTORY_ROLE = keccak256("FACTORY_ROLE");

    address public immutable implementation; // AssetTokenV1 logic contract

    address[] private _deployedTokens;
    mapping(bytes32 => address) private _assetIdToToken;
    mapping(address => bool) private _registered;

    event TokenDeployed(bytes32 indexed assetId, address indexed proxy, bool deterministic);

    error DeploymentFailed();

    constructor(address initialAdmin, address implementation_) {
        if (implementation_ == address(0)) revert ZeroAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, initialAdmin);
        _grantRole(FACTORY_ROLE, initialAdmin);
        implementation = implementation_;
    }

    // -------------------------------------------------------------------------
    // CREATE2 — deterministic address, salt derived from assetId + chainId
    // -------------------------------------------------------------------------

    /// @notice Deploys an AssetTokenV1 proxy at a deterministic address.
    ///         Address can be predicted off-chain via predictAddress().
    function deployAssetToken(
        bytes32 assetId,
        string calldata name_,
        string calldata symbol_,
        address oracle_,
        uint256 maxSupply_,
        address admin_
    ) external onlyRole(FACTORY_ROLE) whenNotPaused returns (address proxy) {
        if (_assetIdToToken[assetId] != address(0)) revert AssetAlreadyDeployed(assetId);

        bytes memory initData =
            abi.encodeCall(AssetTokenV1.initialize, (name_, symbol_, oracle_, assetId, maxSupply_, admin_));
        bytes memory bytecode = abi.encodePacked(type(ERC1967Proxy).creationCode, abi.encode(implementation, initData));
        bytes32 salt = keccak256(abi.encodePacked(assetId, block.chainid));

        proxy = _deployWithCreate2Assembly(bytecode, salt);

        _register(assetId, proxy);
        emit TokenDeployed(assetId, proxy, true);
    }

    /// @notice Returns the address a deployAssetToken call would produce.
    ///         All parameters must match the intended deployAssetToken call exactly —
    ///         the CREATE2 address is a function of the full initData, not just the assetId.
    function predictAddress(
        bytes32 assetId,
        string calldata name_,
        string calldata symbol_,
        address oracle_,
        uint256 maxSupply_,
        address admin_
    ) external view returns (address) {
        bytes memory initData = abi.encodeCall(
            AssetTokenV1.initialize, (name_, symbol_, oracle_, assetId, maxSupply_, admin_)
        );
        bytes memory bytecode = abi.encodePacked(type(ERC1967Proxy).creationCode, abi.encode(implementation, initData));
        bytes32 salt = keccak256(abi.encodePacked(assetId, block.chainid));
        bytes32 hash = keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, keccak256(bytecode)));
        return address(uint160(uint256(hash)));
    }

    // -------------------------------------------------------------------------
    // CREATE — non-deterministic, for experimental / one-off deployments
    // -------------------------------------------------------------------------

    function deployAssetTokenUnchecked(
        string calldata name_,
        string calldata symbol_,
        address oracle_,
        uint256 maxSupply_,
        address admin_
    ) external onlyRole(FACTORY_ROLE) whenNotPaused returns (address proxy) {
        bytes memory initData = abi.encodeCall(
            AssetTokenV1.initialize, (name_, symbol_, oracle_, bytes32(0), maxSupply_, admin_)
        );
        bytes memory bytecode = abi.encodePacked(type(ERC1967Proxy).creationCode, abi.encode(implementation, initData));

        proxy = _deployWithCreateAssembly(bytecode);

        _register(bytes32(0), proxy);
        emit TokenDeployed(bytes32(0), proxy, false);
    }

    // -------------------------------------------------------------------------
    // Registry queries
    // -------------------------------------------------------------------------

    function getToken(bytes32 assetId) external view returns (address) {
        return _assetIdToToken[assetId];
    }

    function getDeployedTokens() external view returns (address[] memory) {
        return _deployedTokens;
    }

    function isRegistered(address token) external view returns (bool) {
        return _registered[token];
    }

    // -------------------------------------------------------------------------
    // Admin
    // -------------------------------------------------------------------------

    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    // -------------------------------------------------------------------------
    // Internal helpers
    // -------------------------------------------------------------------------

    function _register(bytes32 assetId, address proxy) internal {
        _deployedTokens.push(proxy);
        _assetIdToToken[assetId] = proxy;
        _registered[proxy] = true;
    }

    // -------------------------------------------------------------------------
    // Yul deployment functions — gas benchmark vs Solidity new ERC1967Proxy{salt:}
    //
    // Both functions use raw EVM opcodes (CREATE2 / CREATE) via inline assembly.
    // This saves ~200 gas per deployment by skipping Solidity's post-deploy
    // return-size check and type-safety wrapper that `new Contract{salt:}()` emits.
    // Benchmarks are in the gas optimization report.
    // -------------------------------------------------------------------------

    /// @dev Deploys bytecode at a deterministic address using CREATE2 opcode directly.
    function _deployWithCreate2Assembly(bytes memory bytecode, bytes32 salt) internal returns (address proxy) {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            proxy := create2(0, add(bytecode, 0x20), mload(bytecode), salt)
            if iszero(proxy) { revert(0, 0) }
        }
    }

    /// @dev Deploys bytecode at a non-deterministic address using CREATE opcode directly.
    function _deployWithCreateAssembly(bytes memory bytecode) internal returns (address proxy) {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            proxy := create(0, add(bytecode, 0x20), mload(bytecode))
            if iszero(proxy) { revert(0, 0) }
        }
    }
}
