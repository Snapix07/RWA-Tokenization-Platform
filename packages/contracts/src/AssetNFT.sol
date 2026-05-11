// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import {ERC721URIStorage} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {TransferRestricted} from "./interfaces/IRWATypes.sol";

/// @title AssetNFT
/// @notice ERC-721 certificate representing a unique onboarded real-world asset.
///         Each token maps to one legal document hash stored at a metadata URI.
///
/// Design patterns: AccessControl, Pausable (circuit breaker).
contract AssetNFT is ERC721, ERC721URIStorage, ERC721Enumerable, AccessControl, Pausable {
    bytes32 public constant ISSUER_ROLE = keccak256("ISSUER_ROLE");
    bytes32 public constant COMPLIANCE_ROLE = keccak256("COMPLIANCE_ROLE");

    uint256 private _nextTokenId;
    mapping(uint256 => bytes32) private _tokenAssetId;
    mapping(uint256 => bool) private _frozen;

    event AssetCertificateMinted(uint256 indexed tokenId, bytes32 indexed assetId, address indexed to);
    event TokenFrozen(uint256 indexed tokenId);
    event TokenUnfrozen(uint256 indexed tokenId);

    error TokenIsFrozen(uint256 tokenId);

    constructor(address initialAdmin) ERC721("RWA Asset Certificate", "RWANFT") {
        _grantRole(DEFAULT_ADMIN_ROLE, initialAdmin);
        _grantRole(ISSUER_ROLE, initialAdmin);
        _grantRole(COMPLIANCE_ROLE, initialAdmin);
    }

    function mint(address to, string calldata tokenURI_, bytes32 assetId)
        external
        onlyRole(ISSUER_ROLE)
        whenNotPaused
        returns (uint256 tokenId)
    {
        tokenId = _nextTokenId++;
        _safeMint(to, tokenId);
        _setTokenURI(tokenId, tokenURI_);
        _tokenAssetId[tokenId] = assetId;
        emit AssetCertificateMinted(tokenId, assetId, to);
    }

    function freeze(uint256 tokenId) external onlyRole(COMPLIANCE_ROLE) {
        _frozen[tokenId] = true;
        emit TokenFrozen(tokenId);
    }

    function unfreeze(uint256 tokenId) external onlyRole(COMPLIANCE_ROLE) {
        _frozen[tokenId] = false;
        emit TokenUnfrozen(tokenId);
    }

    function getAssetId(uint256 tokenId) external view returns (bytes32) {
        return _tokenAssetId[tokenId];
    }

    function isFrozen(uint256 tokenId) external view returns (bool) {
        return _frozen[tokenId];
    }

    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    // -------------------------------------------------------------------------
    // OZ v5 required overrides
    // -------------------------------------------------------------------------

    function _update(address to, uint256 tokenId, address auth)
        internal
        override(ERC721, ERC721Enumerable)
        returns (address)
    {
        // Block transfers of frozen tokens (allow burning: to == address(0))
        if (_frozen[tokenId] && to != address(0)) revert TokenIsFrozen(tokenId);
        return super._update(to, tokenId, auth);
    }

    function _increaseBalance(address account, uint128 value) internal override(ERC721, ERC721Enumerable) {
        super._increaseBalance(account, value);
    }

    function tokenURI(uint256 tokenId) public view override(ERC721, ERC721URIStorage) returns (string memory) {
        return super.tokenURI(tokenId);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721URIStorage, ERC721Enumerable, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
