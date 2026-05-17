// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {AssetTokenV1} from "../../src/AssetTokenV1.sol";
import {AssetTokenV2} from "../../src/AssetTokenV2.sol";
import {ChainlinkOracleAdapter} from "../../src/ChainlinkOracleAdapter.sol";
import {MockAggregator} from "../../src/mocks/MockAggregator.sol";

import {
    KYCRequired,
    ZeroAddress
} from "../../src/interfaces/IRWATypes.sol";

contract AssetTokenV2UpgradeTest is Test {
    AssetTokenV1 internal v1Implementation;
    AssetTokenV2 internal v2Implementation;

    AssetTokenV1 internal tokenV1;
    AssetTokenV2 internal tokenV2;
    ERC1967Proxy internal proxy;

    ChainlinkOracleAdapter internal oracle;
    MockAggregator internal mockFeed;

    address internal admin = makeAddr("admin");
    address internal oracleOwner = makeAddr("oracleOwner");
    address internal issuer = makeAddr("issuer");
    address internal pauser = makeAddr("pauser");
    address internal upgrader = makeAddr("upgrader");

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal attacker = makeAddr("attacker");

    address internal feeRecipient = makeAddr("feeRecipient");
    address internal newFeeRecipient = makeAddr("newFeeRecipient");

    bytes32 internal constant ASSET_ID = keccak256("RWA_ASSET_UPGRADE_001");

    uint96 internal constant MAX_STALENESS = 1 days;
    uint256 internal constant MAX_SUPPLY = 1_000_000 ether;
    uint256 internal constant PRE_UPGRADE_MINT = 50_000 ether;

    function setUp() public {
        vm.warp(1_700_000_000);

        oracle = new ChainlinkOracleAdapter(oracleOwner);
        mockFeed = new MockAggregator(int256(2_000e8), 8);

        vm.prank(oracleOwner);
        oracle.addFeed(ASSET_ID, address(mockFeed), MAX_STALENESS);

        v1Implementation = new AssetTokenV1();

        bytes memory initData = abi.encodeCall(
            AssetTokenV1.initialize,
            (
                "Upgradeable RWA Token",
                "URWA",
                address(oracle),
                ASSET_ID,
                MAX_SUPPLY,
                admin
            )
        );

        proxy = new ERC1967Proxy(address(v1Implementation), initData);
        tokenV1 = AssetTokenV1(address(proxy));

        vm.startPrank(admin);
        tokenV1.grantRole(tokenV1.ISSUER_ROLE(), issuer);
        tokenV1.grantRole(tokenV1.PAUSER_ROLE(), pauser);
        tokenV1.grantRole(tokenV1.UPGRADER_ROLE(), upgrader);
        vm.stopPrank();

        vm.prank(issuer);
        tokenV1.mint(alice, PRE_UPGRADE_MINT);
    }

    function _upgradeToV2(
        address feeRecipient_,
        uint256 mintFeeBps_,
        bool kycEnabled_
    ) internal {
        v2Implementation = new AssetTokenV2();

        bytes memory upgradeCall = abi.encodeCall(
            AssetTokenV2.initializeV2,
            (feeRecipient_, mintFeeBps_, kycEnabled_)
        );

        vm.prank(upgrader);
        tokenV1.upgradeToAndCall(address(v2Implementation), upgradeCall);

        tokenV2 = AssetTokenV2(address(proxy));
    }

    function _upgradeWithDefaultKYC() internal {
        _upgradeToV2(feeRecipient, 0, true);
    }

    // -------------------------------------------------------------------------
    // Upgrade path and storage preservation
    // -------------------------------------------------------------------------

    function test_UpgradeToV2_PreservesV1StorageAndBalances() public {
        _upgradeWithDefaultKYC();

        assertEq(tokenV2.name(), "Upgradeable RWA Token");
        assertEq(tokenV2.symbol(), "URWA");
        assertEq(tokenV2.assetId(), ASSET_ID);
        assertEq(tokenV2.oracle(), address(oracle));

        assertEq(tokenV2.balanceOf(alice), PRE_UPGRADE_MINT);
        assertEq(tokenV2.totalSupply(), PRE_UPGRADE_MINT);

        assertTrue(tokenV2.hasRole(tokenV2.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(tokenV2.hasRole(tokenV2.ISSUER_ROLE(), issuer));
        assertTrue(tokenV2.hasRole(tokenV2.PAUSER_ROLE(), pauser));
        assertTrue(tokenV2.hasRole(tokenV2.UPGRADER_ROLE(), upgrader));
    }

    function test_UpgradeToV2_GrantsComplianceRoleToUpgradeCaller() public {
        _upgradeWithDefaultKYC();

        assertTrue(tokenV2.hasRole(tokenV2.COMPLIANCE_ROLE(), upgrader));
    }

    function test_InitializeV2_RevertsWhenCalledAgain() public {
        _upgradeWithDefaultKYC();

        vm.expectRevert();

        tokenV2.initializeV2(feeRecipient, 0, true);
    }

    function test_UpgradeToV2_RevertsWhenPositiveFeeUsesZeroRecipient() public {
        AssetTokenV2 freshV2Implementation = new AssetTokenV2();

        bytes memory upgradeCall = abi.encodeCall(
            AssetTokenV2.initializeV2,
            (address(0), 100, true)
        );

        vm.prank(upgrader);
        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector));

        tokenV1.upgradeToAndCall(address(freshV2Implementation), upgradeCall);
    }

    function test_UpgradeToV2_AllowsZeroFeeRecipientWhenFeeIsZero() public {
        _upgradeToV2(address(0), 0, true);

        assertTrue(tokenV2.hasRole(tokenV2.COMPLIANCE_ROLE(), upgrader));
    }

    // -------------------------------------------------------------------------
    // KYC management
    // -------------------------------------------------------------------------

    function test_ApproveKYC_ComplianceOfficerApprovesAccount() public {
        _upgradeWithDefaultKYC();

        vm.prank(upgrader);
        tokenV2.approveKYC(alice);

        assertTrue(tokenV2.isKYCApproved(alice));
    }

    function test_ApproveKYC_RevertsWhenCallerLacksComplianceRole() public {
        _upgradeWithDefaultKYC();

        vm.prank(attacker);
        vm.expectRevert();

        tokenV2.approveKYC(alice);
    }

    function test_RevokeKYC_ComplianceOfficerRevokesAccount() public {
        _upgradeWithDefaultKYC();

        vm.startPrank(upgrader);
        tokenV2.approveKYC(alice);
        tokenV2.revokeKYC(alice);
        vm.stopPrank();

        assertFalse(tokenV2.isKYCApproved(alice));
    }

    function test_RevokeKYC_RevertsWhenCallerLacksComplianceRole() public {
        _upgradeWithDefaultKYC();

        vm.prank(attacker);
        vm.expectRevert();

        tokenV2.revokeKYC(alice);
    }

    function test_SetKYCEnabled_AdminCanDisableRestriction() public {
        _upgradeWithDefaultKYC();

        vm.prank(admin);
        tokenV2.setKYCEnabled(false);

        vm.prank(issuer);
        tokenV2.mint(bob, 100 ether);

        assertEq(tokenV2.balanceOf(bob), 100 ether);
    }

    function test_SetKYCEnabled_RevertsWhenCallerIsNotAdmin() public {
        _upgradeWithDefaultKYC();

        vm.prank(attacker);
        vm.expectRevert();

        tokenV2.setKYCEnabled(false);
    }

    // -------------------------------------------------------------------------
    // Minting with KYC
    // -------------------------------------------------------------------------

    function test_Mint_RevertsWhenRecipientIsNotKYCApproved() public {
        _upgradeWithDefaultKYC();

        vm.prank(issuer);
        vm.expectRevert(
            abi.encodeWithSelector(KYCRequired.selector, bob)
        );

        tokenV2.mint(bob, 100 ether);
    }

    function test_Mint_SucceedsWhenRecipientIsKYCApproved() public {
        _upgradeWithDefaultKYC();

        vm.prank(upgrader);
        tokenV2.approveKYC(bob);

        vm.prank(issuer);
        tokenV2.mint(bob, 100 ether);

        assertEq(tokenV2.balanceOf(bob), 100 ether);
    }

    function test_Mint_SucceedsForUnapprovedRecipientWhenKYCDisabled() public {
        _upgradeToV2(feeRecipient, 0, false);

        vm.prank(issuer);
        tokenV2.mint(bob, 100 ether);

        assertEq(tokenV2.balanceOf(bob), 100 ether);
    }

    // -------------------------------------------------------------------------
    // Mint fee management
    // -------------------------------------------------------------------------

    function test_Mint_DeductsFeeAndCreditsFeeRecipient() public {
        _upgradeToV2(feeRecipient, 1_000, true); // 10%

        vm.startPrank(upgrader);
        tokenV2.approveKYC(alice);
        tokenV2.approveKYC(feeRecipient);
        vm.stopPrank();

        vm.prank(issuer);
        tokenV2.mint(alice, 1_000 ether);

        assertEq(tokenV2.balanceOf(alice), PRE_UPGRADE_MINT + 900 ether);
        assertEq(tokenV2.balanceOf(feeRecipient), 100 ether);
    }

    function test_Mint_WithFeeRevertsIfFeeRecipientIsNotKYCApproved() public {
        _upgradeToV2(feeRecipient, 1_000, true); // 10%

        vm.prank(upgrader);
        tokenV2.approveKYC(alice);

        vm.prank(issuer);
        vm.expectRevert(
            abi.encodeWithSelector(KYCRequired.selector, feeRecipient)
        );

        tokenV2.mint(alice, 1_000 ether);
    }

    function test_SetMintFee_AdminChangesFeeRate() public {
        _upgradeToV2(feeRecipient, 0, true);

        vm.prank(admin);
        tokenV2.setMintFee(500); // 5%

        vm.startPrank(upgrader);
        tokenV2.approveKYC(bob);
        tokenV2.approveKYC(feeRecipient);
        vm.stopPrank();

        vm.prank(issuer);
        tokenV2.mint(bob, 1_000 ether);

        assertEq(tokenV2.balanceOf(bob), 950 ether);
        assertEq(tokenV2.balanceOf(feeRecipient), 50 ether);
    }

    function test_SetMintFee_RevertsWhenFeeExceedsTenPercent() public {
        _upgradeToV2(feeRecipient, 0, true);

        vm.prank(admin);
        vm.expectRevert(bytes("fee > 10%"));

        tokenV2.setMintFee(1_001);
    }

    function test_SetMintFee_RevertsWhenCallerIsNotAdmin() public {
        _upgradeToV2(feeRecipient, 0, true);

        vm.prank(attacker);
        vm.expectRevert();

        tokenV2.setMintFee(500);
    }

    function test_SetFeeRecipient_AdminUpdatesRecipientUsedForFutureFees() public {
        _upgradeToV2(feeRecipient, 500, true); // 5%

        vm.prank(admin);
        tokenV2.setFeeRecipient(newFeeRecipient);

        vm.startPrank(upgrader);
        tokenV2.approveKYC(bob);
        tokenV2.approveKYC(newFeeRecipient);
        vm.stopPrank();

        vm.prank(issuer);
        tokenV2.mint(bob, 1_000 ether);

        assertEq(tokenV2.balanceOf(bob), 950 ether);
        assertEq(tokenV2.balanceOf(newFeeRecipient), 50 ether);
        assertEq(tokenV2.balanceOf(feeRecipient), 0);
    }

    function test_SetFeeRecipient_RevertsWhenRecipientIsZeroAddress() public {
        _upgradeToV2(feeRecipient, 0, true);

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector));

        tokenV2.setFeeRecipient(address(0));
    }

    function test_SetFeeRecipient_RevertsWhenCallerIsNotAdmin() public {
        _upgradeToV2(feeRecipient, 0, true);

        vm.prank(attacker);
        vm.expectRevert();

        tokenV2.setFeeRecipient(newFeeRecipient);
    }

    // -------------------------------------------------------------------------
    // Transfer restrictions after upgrade
    // -------------------------------------------------------------------------

    function test_Transfer_RevertsWhenRecipientIsNotKYCApproved() public {
        _upgradeWithDefaultKYC();

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(KYCRequired.selector, bob)
        );

        tokenV2.transfer(bob, 1_000 ether);
    }

    function test_Transfer_SucceedsWhenRecipientIsKYCApproved() public {
        _upgradeWithDefaultKYC();

        vm.prank(upgrader);
        tokenV2.approveKYC(bob);

        vm.prank(alice);
        tokenV2.transfer(bob, 1_000 ether);

        assertEq(tokenV2.balanceOf(alice), PRE_UPGRADE_MINT - 1_000 ether);
        assertEq(tokenV2.balanceOf(bob), 1_000 ether);
    }

    function test_Transfer_SucceedsForUnapprovedRecipientWhenKYCDisabled() public {
        _upgradeToV2(feeRecipient, 0, false);

        vm.prank(alice);
        tokenV2.transfer(bob, 1_000 ether);

        assertEq(tokenV2.balanceOf(bob), 1_000 ether);
    }

    // -------------------------------------------------------------------------
    // Burn path: to == address(0) skips recipient KYC check
    // -------------------------------------------------------------------------

    function test_Burn_SucceedsEvenIfHolderIsNotCurrentlyKYCApproved() public {
        _upgradeWithDefaultKYC();

        vm.prank(issuer);
        tokenV2.burn(alice, 1_000 ether);

        assertEq(tokenV2.balanceOf(alice), PRE_UPGRADE_MINT - 1_000 ether);
        assertEq(tokenV2.totalSupply(), PRE_UPGRADE_MINT - 1_000 ether);
    }
}
