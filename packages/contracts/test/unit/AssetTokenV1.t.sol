// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {AssetTokenV1} from "../../src/AssetTokenV1.sol";
import {AssetTokenV2} from "../../src/AssetTokenV2.sol";
import {ChainlinkOracleAdapter} from "../../src/ChainlinkOracleAdapter.sol";
import {MockAggregator} from "../../src/mocks/MockAggregator.sol";

import {
    InvalidAsset,
    ZeroAddress
} from "../../src/interfaces/IRWATypes.sol";

contract AssetTokenV1Test is Test {
    AssetTokenV1 internal implementation;
    AssetTokenV1 internal token;
    ERC1967Proxy internal proxy;

    ChainlinkOracleAdapter internal oracle;
    ChainlinkOracleAdapter internal secondOracle;
    MockAggregator internal mockFeed;
    MockAggregator internal secondMockFeed;

    address internal admin = makeAddr("admin");
    address internal oracleOwner = makeAddr("oracleOwner");
    address internal issuer = makeAddr("issuer");
    address internal pauser = makeAddr("pauser");
    address internal upgrader = makeAddr("upgrader");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal attacker = makeAddr("attacker");

    bytes32 internal constant ASSET_ID = keccak256("RWA_ASSET_001");
    uint96 internal constant MAX_STALENESS = 1 days;
    uint256 internal constant MAX_SUPPLY = 1_000_000 ether;
    uint256 internal constant MINT_AMOUNT = 100_000 ether;

    function setUp() public {
        vm.warp(1_700_000_000);

        oracle = new ChainlinkOracleAdapter(oracleOwner);
        secondOracle = new ChainlinkOracleAdapter(oracleOwner);

        mockFeed = new MockAggregator(int256(2_000e8), 8);
        secondMockFeed = new MockAggregator(int256(2_500e8), 8);

        vm.startPrank(oracleOwner);
        oracle.addFeed(ASSET_ID, address(mockFeed), MAX_STALENESS);
        secondOracle.addFeed(ASSET_ID, address(secondMockFeed), MAX_STALENESS);
        vm.stopPrank();

        implementation = new AssetTokenV1();

        bytes memory initData = abi.encodeCall(
            AssetTokenV1.initialize,
            (
                "RWA Real Estate Token",
                "RWA-RET",
                address(oracle),
                ASSET_ID,
                MAX_SUPPLY,
                admin
            )
        );

        proxy = new ERC1967Proxy(address(implementation), initData);
        token = AssetTokenV1(address(proxy));

        vm.startPrank(admin);
        token.grantRole(token.ISSUER_ROLE(), issuer);
        token.grantRole(token.PAUSER_ROLE(), pauser);
        token.grantRole(token.UPGRADER_ROLE(), upgrader);
        vm.stopPrank();
    }

    // -------------------------------------------------------------------------
    // Initialization
    // -------------------------------------------------------------------------

    function test_Initialize_SetsMetadataRolesAndCoreStorage() public view {
        assertEq(token.name(), "RWA Real Estate Token");
        assertEq(token.symbol(), "RWA-RET");
        assertEq(token.decimals(), 18);

        assertEq(token.assetId(), ASSET_ID);
        assertEq(token.oracle(), address(oracle));

        assertTrue(token.hasRole(token.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(token.hasRole(token.ISSUER_ROLE(), admin));
        assertTrue(token.hasRole(token.PAUSER_ROLE(), admin));
        assertTrue(token.hasRole(token.UPGRADER_ROLE(), admin));
    }

    function test_Initialize_RevertsWhenCalledTwiceThroughProxy() public {
        vm.expectRevert();

        token.initialize(
            "Second Name",
            "SECOND",
            address(oracle),
            ASSET_ID,
            MAX_SUPPLY,
            admin
        );
    }

    function test_Initialize_RevertsWhenOracleIsZeroAddress() public {
        AssetTokenV1 freshImplementation = new AssetTokenV1();

        bytes memory initData = abi.encodeCall(
            AssetTokenV1.initialize,
            (
                "Broken Token",
                "BROKEN",
                address(0),
                ASSET_ID,
                MAX_SUPPLY,
                admin
            )
        );

        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector));
        new ERC1967Proxy(address(freshImplementation), initData);
    }

    function test_Initialize_RevertsWhenAdminIsZeroAddress() public {
        AssetTokenV1 freshImplementation = new AssetTokenV1();

        bytes memory initData = abi.encodeCall(
            AssetTokenV1.initialize,
            (
                "Broken Token",
                "BROKEN",
                address(oracle),
                ASSET_ID,
                MAX_SUPPLY,
                address(0)
            )
        );

        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector));
        new ERC1967Proxy(address(freshImplementation), initData);
    }

    // -------------------------------------------------------------------------
    // Minting
    // -------------------------------------------------------------------------

    function test_Mint_IssuerMintsTokensWithinCap() public {
        vm.prank(issuer);
        token.mint(alice, MINT_AMOUNT);

        assertEq(token.balanceOf(alice), MINT_AMOUNT);
        assertEq(token.totalSupply(), MINT_AMOUNT);
    }

    function test_Mint_AdminAlsoRetainsIssuerPermission() public {
        vm.prank(admin);
        token.mint(alice, MINT_AMOUNT);

        assertEq(token.balanceOf(alice), MINT_AMOUNT);
        assertEq(token.totalSupply(), MINT_AMOUNT);
    }

    function test_Mint_RevertsWhenCallerLacksIssuerRole() public {
        vm.prank(attacker);
        vm.expectRevert();

        token.mint(alice, MINT_AMOUNT);
    }

    function test_Mint_RevertsWhenReceiverIsZeroAddress() public {
        vm.prank(issuer);
        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector));

        token.mint(address(0), MINT_AMOUNT);
    }

    function test_Mint_AllowsSupplyExactlyAtCap() public {
        vm.prank(issuer);
        token.mint(alice, MAX_SUPPLY);

        assertEq(token.balanceOf(alice), MAX_SUPPLY);
        assertEq(token.totalSupply(), MAX_SUPPLY);
    }

    function test_Mint_RevertsWhenSupplyWouldExceedCap() public {
        vm.prank(issuer);
        token.mint(alice, MAX_SUPPLY);

        vm.prank(issuer);
        vm.expectRevert(
            abi.encodeWithSelector(InvalidAsset.selector, ASSET_ID)
        );

        token.mint(bob, 1);
    }

    function test_Mint_UncappedTokenAllowsLargeSupply() public {
        AssetTokenV1 uncappedImplementation = new AssetTokenV1();

        bytes memory initData = abi.encodeCall(
            AssetTokenV1.initialize,
            (
                "Uncapped RWA Token",
                "URWA",
                address(oracle),
                ASSET_ID,
                0,
                admin
            )
        );

        ERC1967Proxy uncappedProxy =
            new ERC1967Proxy(address(uncappedImplementation), initData);

        AssetTokenV1 uncappedToken = AssetTokenV1(address(uncappedProxy));

        uint256 largeAmount = 5_000_000 ether;

        vm.prank(admin);
        uncappedToken.mint(alice, largeAmount);

        assertEq(uncappedToken.balanceOf(alice), largeAmount);
        assertEq(uncappedToken.totalSupply(), largeAmount);
    }

    // -------------------------------------------------------------------------
    // Burning
    // -------------------------------------------------------------------------

    function test_Burn_IssuerReducesBalanceAndTotalSupply() public {
        vm.prank(issuer);
        token.mint(alice, MINT_AMOUNT);

        vm.prank(issuer);
        token.burn(alice, 40_000 ether);

        assertEq(token.balanceOf(alice), 60_000 ether);
        assertEq(token.totalSupply(), 60_000 ether);
    }

    function test_Burn_RevertsWhenCallerLacksIssuerRole() public {
        vm.prank(issuer);
        token.mint(alice, MINT_AMOUNT);

        vm.prank(attacker);
        vm.expectRevert();

        token.burn(alice, 1 ether);
    }

    function test_Burn_RevertsWhenAmountExceedsBalance() public {
        vm.prank(issuer);
        token.mint(alice, 10 ether);

        vm.prank(issuer);
        vm.expectRevert();

        token.burn(alice, 11 ether);
    }

    // -------------------------------------------------------------------------
    // Pause / unpause / transfer restrictions
    // -------------------------------------------------------------------------

    function test_PauseAndUnpause_PauserControlsEmergencyState() public {
        assertFalse(token.paused());

        vm.prank(pauser);
        token.pause();

        assertTrue(token.paused());

        vm.prank(pauser);
        token.unpause();

        assertFalse(token.paused());
    }

    function test_Pause_RevertsWhenCallerLacksPauserRole() public {
        vm.prank(attacker);
        vm.expectRevert();

        token.pause();
    }

    function test_Unpause_RevertsWhenCallerLacksPauserRole() public {
        vm.prank(pauser);
        token.pause();

        vm.prank(attacker);
        vm.expectRevert();

        token.unpause();
    }

    function test_Mint_RevertsWhenTokenIsPaused() public {
        vm.prank(pauser);
        token.pause();

        vm.prank(issuer);
        vm.expectRevert();

        token.mint(alice, MINT_AMOUNT);
    }

    function test_Transfer_RevertsWhenTokenIsPaused() public {
        vm.prank(issuer);
        token.mint(alice, MINT_AMOUNT);

        vm.prank(pauser);
        token.pause();

        vm.prank(alice);
        vm.expectRevert();

        token.transfer(bob, 1 ether);
    }

    function test_Burn_RevertsWhenTokenIsPaused() public {
        vm.prank(issuer);
        token.mint(alice, MINT_AMOUNT);

        vm.prank(pauser);
        token.pause();

        vm.prank(issuer);
        vm.expectRevert();

        token.burn(alice, 1 ether);
    }

    function test_Transfer_SucceedsWhenTokenIsUnpaused() public {
        vm.prank(issuer);
        token.mint(alice, MINT_AMOUNT);

        vm.prank(alice);
        token.transfer(bob, 25_000 ether);

        assertEq(token.balanceOf(alice), 75_000 ether);
        assertEq(token.balanceOf(bob), 25_000 ether);
    }

    // -------------------------------------------------------------------------
    // Oracle integration
    // -------------------------------------------------------------------------

    function test_GetAssetPrice_ReturnsPriceFromConfiguredOracle() public view {
        (uint256 price18, uint256 updatedAt) = token.getAssetPrice();

        assertEq(price18, 2_000 ether);
        assertEq(updatedAt, block.timestamp);
    }

    function test_SetOracle_AdminUpdatesOracleAddress() public {
        vm.prank(admin);
        token.setOracle(address(secondOracle));

        assertEq(token.oracle(), address(secondOracle));
    }

    function test_SetOracle_UpdatedOracleAffectsAssetPriceLookup() public {
        vm.prank(admin);
        token.setOracle(address(secondOracle));

        (uint256 price18, uint256 updatedAt) = token.getAssetPrice();

        assertEq(price18, 2_500 ether);
        assertEq(updatedAt, block.timestamp);
    }

    function test_SetOracle_RevertsWhenCallerIsNotAdmin() public {
        vm.prank(attacker);
        vm.expectRevert();

        token.setOracle(address(secondOracle));
    }

    function test_SetOracle_RevertsWhenOracleIsZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector));

        token.setOracle(address(0));
    }

    // -------------------------------------------------------------------------
    // UUPS upgrade authorization
    // -------------------------------------------------------------------------

    function test_UpgradeToAndCall_RevertsWhenCallerLacksUpgraderRole() public {
        AssetTokenV2 v2Implementation = new AssetTokenV2();

        bytes memory upgradeCall = abi.encodeCall(
            AssetTokenV2.initializeV2,
            (makeAddr("feeRecipient"), 100, true)
        );

        vm.prank(attacker);
        vm.expectRevert();

        token.upgradeToAndCall(address(v2Implementation), upgradeCall);
    }
}
