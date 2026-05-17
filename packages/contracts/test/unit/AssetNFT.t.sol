// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {AssetNFT} from "../../src/AssetNFT.sol";

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC721Metadata} from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import {IERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

contract AssetNFTTest is Test {
    AssetNFT internal assetNFT;

    address internal admin = makeAddr("admin");
    address internal issuer = makeAddr("issuer");
    address internal complianceOfficer = makeAddr("complianceOfficer");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal attacker = makeAddr("attacker");

    bytes32 internal constant ASSET_ID_1 = keccak256("ASSET_ID_1");
    bytes32 internal constant ASSET_ID_2 = keccak256("ASSET_ID_2");

    string internal constant TOKEN_URI_1 = "ipfs://asset-one.json";
    string internal constant TOKEN_URI_2 = "ipfs://asset-two.json";

    event AssetCertificateMinted(uint256 indexed tokenId, bytes32 indexed assetId, address indexed to);
    event TokenFrozen(uint256 indexed tokenId);
    event TokenUnfrozen(uint256 indexed tokenId);

    function setUp() public {
        assetNFT = new AssetNFT(admin);

        vm.startPrank(admin);
        assetNFT.grantRole(assetNFT.ISSUER_ROLE(), issuer);
        assetNFT.grantRole(assetNFT.COMPLIANCE_ROLE(), complianceOfficer);
        vm.stopPrank();
    }

    function _mintDefaultTokenToAlice() internal returns (uint256 tokenId) {
        vm.prank(issuer);
        tokenId = assetNFT.mint(alice, TOKEN_URI_1, ASSET_ID_1);
    }

    function test_Constructor_AssignsInitialRolesToAdmin() public view {
        assertTrue(assetNFT.hasRole(assetNFT.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(assetNFT.hasRole(assetNFT.ISSUER_ROLE(), admin));
        assertTrue(assetNFT.hasRole(assetNFT.COMPLIANCE_ROLE(), admin));
    }

    function test_Mint_IssuerCreatesCertificateAndStoresMetadata() public {
        vm.prank(issuer);
        uint256 tokenId = assetNFT.mint(alice, TOKEN_URI_1, ASSET_ID_1);

        assertEq(tokenId, 0);
        assertEq(assetNFT.ownerOf(tokenId), alice);
        assertEq(assetNFT.tokenURI(tokenId), TOKEN_URI_1);
        assertEq(assetNFT.getAssetId(tokenId), ASSET_ID_1);
        assertEq(assetNFT.totalSupply(), 1);
    }

    function test_Mint_AssignsSequentialTokenIds() public {
        vm.prank(issuer);
        uint256 firstTokenId = assetNFT.mint(alice, TOKEN_URI_1, ASSET_ID_1);

        vm.prank(issuer);
        uint256 secondTokenId = assetNFT.mint(bob, TOKEN_URI_2, ASSET_ID_2);

        assertEq(firstTokenId, 0);
        assertEq(secondTokenId, 1);
        assertEq(assetNFT.totalSupply(), 2);
        assertEq(assetNFT.ownerOf(firstTokenId), alice);
        assertEq(assetNFT.ownerOf(secondTokenId), bob);
    }

    function test_Mint_EmitsAssetCertificateMintedEvent() public {
        vm.expectEmit(true, true, true, true, address(assetNFT));
        emit AssetCertificateMinted(0, ASSET_ID_1, alice);

        vm.prank(issuer);
        assetNFT.mint(alice, TOKEN_URI_1, ASSET_ID_1);
    }

    function test_Mint_RevertsWhenCallerLacksIssuerRole() public {
        vm.prank(attacker);
        vm.expectRevert();

        assetNFT.mint(alice, TOKEN_URI_1, ASSET_ID_1);
    }

    function test_Mint_RevertsWhenContractIsPaused() public {
        vm.prank(admin);
        assetNFT.pause();

        vm.prank(issuer);
        vm.expectRevert();

        assetNFT.mint(alice, TOKEN_URI_1, ASSET_ID_1);
    }

    function test_Mint_RevertsWhenReceiverIsZeroAddress() public {
        vm.prank(issuer);
        vm.expectRevert();

        assetNFT.mint(address(0), TOKEN_URI_1, ASSET_ID_1);
    }

    function test_PauseAndUnpause_AdminControlsEmergencyState() public {
        assertFalse(assetNFT.paused());

        vm.prank(admin);
        assetNFT.pause();

        assertTrue(assetNFT.paused());

        vm.prank(admin);
        assetNFT.unpause();

        assertFalse(assetNFT.paused());
    }

    function test_Pause_RevertsWhenCallerIsNotAdmin() public {
        vm.prank(attacker);
        vm.expectRevert();

        assetNFT.pause();
    }

    function test_Unpause_RevertsWhenCallerIsNotAdmin() public {
        vm.prank(admin);
        assetNFT.pause();

        vm.prank(attacker);
        vm.expectRevert();

        assetNFT.unpause();
    }

    function test_IsFrozen_DefaultsToFalseAfterMint() public {
        uint256 tokenId = _mintDefaultTokenToAlice();

        assertFalse(assetNFT.isFrozen(tokenId));
    }

    function test_Freeze_ComplianceOfficerMarksTokenFrozenAndEmitsEvent() public {
        uint256 tokenId = _mintDefaultTokenToAlice();

        vm.expectEmit(true, false, false, true, address(assetNFT));
        emit TokenFrozen(tokenId);

        vm.prank(complianceOfficer);
        assetNFT.freeze(tokenId);

        assertTrue(assetNFT.isFrozen(tokenId));
    }

    function test_Unfreeze_ComplianceOfficerClearsFrozenStateAndEmitsEvent() public {
        uint256 tokenId = _mintDefaultTokenToAlice();

        vm.prank(complianceOfficer);
        assetNFT.freeze(tokenId);

        vm.expectEmit(true, false, false, true, address(assetNFT));
        emit TokenUnfrozen(tokenId);

        vm.prank(complianceOfficer);
        assetNFT.unfreeze(tokenId);

        assertFalse(assetNFT.isFrozen(tokenId));
    }

    function test_Freeze_RevertsWhenCallerLacksComplianceRole() public {
        uint256 tokenId = _mintDefaultTokenToAlice();

        vm.prank(attacker);
        vm.expectRevert();

        assetNFT.freeze(tokenId);
    }

    function test_Unfreeze_RevertsWhenCallerLacksComplianceRole() public {
        uint256 tokenId = _mintDefaultTokenToAlice();

        vm.prank(complianceOfficer);
        assetNFT.freeze(tokenId);

        vm.prank(attacker);
        vm.expectRevert();

        assetNFT.unfreeze(tokenId);
    }

    function test_TransferFrozenToken_RevertsWithTokenIsFrozen() public {
        uint256 tokenId = _mintDefaultTokenToAlice();

        vm.prank(complianceOfficer);
        assetNFT.freeze(tokenId);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(AssetNFT.TokenIsFrozen.selector, tokenId));

        assetNFT.transferFrom(alice, bob, tokenId);
    }

    function test_TransferUnfrozenToken_Succeeds() public {
        uint256 tokenId = _mintDefaultTokenToAlice();

        vm.prank(alice);
        assetNFT.transferFrom(alice, bob, tokenId);

        assertEq(assetNFT.ownerOf(tokenId), bob);
    }

    function test_SupportsRequiredInterfaces() public view {
        assertTrue(assetNFT.supportsInterface(type(IERC721).interfaceId));
        assertTrue(assetNFT.supportsInterface(type(IERC721Metadata).interfaceId));
        assertTrue(assetNFT.supportsInterface(type(IERC721Enumerable).interfaceId));
        assertTrue(assetNFT.supportsInterface(type(IAccessControl).interfaceId));
    }
}
