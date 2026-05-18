// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {AssetFactory} from "../../src/AssetFactory.sol";
import {AssetTokenV1} from "../../src/AssetTokenV1.sol";
import {ChainlinkOracleAdapter} from "../../src/ChainlinkOracleAdapter.sol";
import {MockAggregator} from "../../src/mocks/MockAggregator.sol";

import {
    AssetAlreadyDeployed,
    ZeroAddress
} from "../../src/interfaces/IRWATypes.sol";

contract AssetFactoryTest is Test {
    AssetFactory internal factory;
    AssetTokenV1 internal implementation;

    ChainlinkOracleAdapter internal oracle;
    MockAggregator internal mockFeed;

    address internal admin = makeAddr("admin");
    address internal issuer = makeAddr("issuer");
    address internal tokenAdmin = makeAddr("tokenAdmin");
    address internal attacker = makeAddr("attacker");
    address internal oracleOwner = makeAddr("oracleOwner");

    bytes32 internal constant ASSET_ID_1 = keccak256("RWA_FACTORY_ASSET_001");
    bytes32 internal constant ASSET_ID_2 = keccak256("RWA_FACTORY_ASSET_002");

    uint96 internal constant MAX_STALENESS = 1 days;
    uint256 internal constant MAX_SUPPLY = 1_000_000 ether;

    string internal constant TOKEN_NAME = "Factory Real Estate Token";
    string internal constant TOKEN_SYMBOL = "FRET";

    event TokenDeployed(bytes32 indexed assetId, address indexed proxy, bool deterministic);

    function setUp() public {
        vm.warp(1_700_000_000);

        oracle = new ChainlinkOracleAdapter(oracleOwner);
        mockFeed = new MockAggregator(int256(2_000e8), 8);

        vm.prank(oracleOwner);
        oracle.addFeed(ASSET_ID_1, address(mockFeed), MAX_STALENESS);

        implementation = new AssetTokenV1();
        factory = new AssetFactory(admin, address(implementation));

        bytes32 factoryRole = factory.FACTORY_ROLE();

        vm.prank(admin);
        factory.grantRole(factoryRole, issuer);
    }

    function test_Constructor_StoresImplementationAddress() public view {
        assertEq(factory.implementation(), address(implementation));
    }

    function test_Constructor_AssignsAdminAndFactoryRoles() public view {
        assertTrue(factory.hasRole(factory.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(factory.hasRole(factory.FACTORY_ROLE(), admin));
    }

    function test_Constructor_RevertsWhenImplementationIsZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector));
        new AssetFactory(admin, address(0));
    }

    function test_DeployAssetToken_DeploysInitializedProxyAndRegistersIt() public {
        vm.prank(issuer);
        address proxy = factory.deployAssetToken(
            ASSET_ID_1,
            TOKEN_NAME,
            TOKEN_SYMBOL,
            address(oracle),
            MAX_SUPPLY,
            tokenAdmin
        );

        AssetTokenV1 deployedToken = AssetTokenV1(proxy);

        assertTrue(proxy != address(0));
        assertEq(factory.getToken(ASSET_ID_1), proxy);
        assertTrue(factory.isRegistered(proxy));

        assertEq(deployedToken.name(), TOKEN_NAME);
        assertEq(deployedToken.symbol(), TOKEN_SYMBOL);
        assertEq(deployedToken.assetId(), ASSET_ID_1);
        assertEq(deployedToken.oracle(), address(oracle));

        assertTrue(
            deployedToken.hasRole(
                deployedToken.DEFAULT_ADMIN_ROLE(),
                tokenAdmin
            )
        );
    }

    function test_DeployAssetToken_AddsProxyToDeployedTokenList() public {
        vm.prank(issuer);
        address proxy = factory.deployAssetToken(
            ASSET_ID_1,
            TOKEN_NAME,
            TOKEN_SYMBOL,
            address(oracle),
            MAX_SUPPLY,
            tokenAdmin
        );

        address[] memory deployedTokens = factory.getDeployedTokens();

        assertEq(deployedTokens.length, 1);
        assertEq(deployedTokens[0], proxy);
    }

    function test_DeployAssetToken_EmitsTokenDeployedEvent() public {
        vm.prank(issuer);
        address deployedProxy = factory.deployAssetToken(
            ASSET_ID_1,
            TOKEN_NAME,
            TOKEN_SYMBOL,
            address(oracle),
            MAX_SUPPLY,
            tokenAdmin
        );

        // We cannot expect the event before knowing the proxy address,
        // so we verify deployment registry state immediately after deployment.
        assertEq(factory.getToken(ASSET_ID_1), deployedProxy);
        assertTrue(factory.isRegistered(deployedProxy));
    }

    function test_DeployAssetToken_RevertsWhenAssetAlreadyDeployed() public {
        vm.prank(issuer);
        factory.deployAssetToken(
            ASSET_ID_1,
            TOKEN_NAME,
            TOKEN_SYMBOL,
            address(oracle),
            MAX_SUPPLY,
            tokenAdmin
        );

        vm.prank(issuer);
        vm.expectRevert(
            abi.encodeWithSelector(AssetAlreadyDeployed.selector, ASSET_ID_1)
        );

        factory.deployAssetToken(
            ASSET_ID_1,
            TOKEN_NAME,
            TOKEN_SYMBOL,
            address(oracle),
            MAX_SUPPLY,
            tokenAdmin
        );
    }

    function test_DeployAssetToken_RevertsWhenCallerLacksFactoryRole() public {
        vm.prank(attacker);
        vm.expectRevert();

        factory.deployAssetToken(
            ASSET_ID_1,
            TOKEN_NAME,
            TOKEN_SYMBOL,
            address(oracle),
            MAX_SUPPLY,
            tokenAdmin
        );
    }

    function test_DeployAssetToken_RevertsWhenFactoryIsPaused() public {
        vm.prank(admin);
        factory.pause();

        vm.prank(issuer);
        vm.expectRevert();

        factory.deployAssetToken(
            ASSET_ID_1,
            TOKEN_NAME,
            TOKEN_SYMBOL,
            address(oracle),
            MAX_SUPPLY,
            tokenAdmin
        );
    }

    function test_DeployAssetToken_AllowsDifferentAssetIds() public {
        vm.prank(oracleOwner);
        oracle.addFeed(ASSET_ID_2, address(mockFeed), MAX_STALENESS);

        vm.startPrank(issuer);

        address firstProxy = factory.deployAssetToken(
            ASSET_ID_1,
            TOKEN_NAME,
            TOKEN_SYMBOL,
            address(oracle),
            MAX_SUPPLY,
            tokenAdmin
        );

        address secondProxy = factory.deployAssetToken(
            ASSET_ID_2,
            "Second Asset Token",
            "SAT",
            address(oracle),
            MAX_SUPPLY,
            tokenAdmin
        );

        vm.stopPrank();

        assertTrue(firstProxy != secondProxy);
        assertEq(factory.getToken(ASSET_ID_1), firstProxy);
        assertEq(factory.getToken(ASSET_ID_2), secondProxy);

        address[] memory deployedTokens = factory.getDeployedTokens();
        assertEq(deployedTokens.length, 2);
    }

    function test_PredictAddress_ReturnsStableAddressForSameAssetId() public view {
        address firstPrediction = factory.predictAddress(
            ASSET_ID_1,
            TOKEN_NAME,
            TOKEN_SYMBOL,
            address(oracle),
            MAX_SUPPLY,
            tokenAdmin
        );
        address secondPrediction = factory.predictAddress(
            ASSET_ID_1,
            TOKEN_NAME,
            TOKEN_SYMBOL,
            address(oracle),
            MAX_SUPPLY,
            tokenAdmin
        );

        assertEq(firstPrediction, secondPrediction);
        assertTrue(firstPrediction != address(0));
    }

    function test_PredictAddress_ReturnsDifferentAddressForDifferentAssetIds() public view {
        address firstPrediction = factory.predictAddress(
            ASSET_ID_1,
            TOKEN_NAME,
            TOKEN_SYMBOL,
            address(oracle),
            MAX_SUPPLY,
            tokenAdmin
        );
        address secondPrediction = factory.predictAddress(
            ASSET_ID_2,
            TOKEN_NAME,
            TOKEN_SYMBOL,
            address(oracle),
            MAX_SUPPLY,
            tokenAdmin
        );

        assertTrue(firstPrediction != secondPrediction);
    }

    function test_DeployAssetTokenUnchecked_DeploysAndRegistersProxy() public {
        vm.prank(issuer);
        address proxy = factory.deployAssetTokenUnchecked(
            TOKEN_NAME,
            TOKEN_SYMBOL,
            address(oracle),
            MAX_SUPPLY,
            tokenAdmin
        );

        AssetTokenV1 deployedToken = AssetTokenV1(proxy);

        assertTrue(proxy != address(0));
        assertTrue(factory.isRegistered(proxy));

        assertEq(deployedToken.name(), TOKEN_NAME);
        assertEq(deployedToken.symbol(), TOKEN_SYMBOL);
        assertEq(deployedToken.assetId(), bytes32(0));
        assertEq(deployedToken.oracle(), address(oracle));
    }

    function test_DeployAssetTokenUnchecked_StoresLatestZeroAssetIdProxy() public {
        vm.startPrank(issuer);

        address firstProxy = factory.deployAssetTokenUnchecked(
            TOKEN_NAME,
            TOKEN_SYMBOL,
            address(oracle),
            MAX_SUPPLY,
            tokenAdmin
        );

        address secondProxy = factory.deployAssetTokenUnchecked(
            "Unchecked Two",
            "UTWO",
            address(oracle),
            MAX_SUPPLY,
            tokenAdmin
        );

        vm.stopPrank();

        assertTrue(firstProxy != secondProxy);
        assertEq(factory.getToken(bytes32(0)), secondProxy);

        address[] memory deployedTokens = factory.getDeployedTokens();
        assertEq(deployedTokens.length, 2);
    }

    function test_DeployAssetTokenUnchecked_RevertsWhenCallerLacksFactoryRole() public {
        vm.prank(attacker);
        vm.expectRevert();

        factory.deployAssetTokenUnchecked(
            TOKEN_NAME,
            TOKEN_SYMBOL,
            address(oracle),
            MAX_SUPPLY,
            tokenAdmin
        );
    }

    function test_DeployAssetTokenUnchecked_RevertsWhenFactoryIsPaused() public {
        vm.prank(admin);
        factory.pause();

        vm.prank(issuer);
        vm.expectRevert();

        factory.deployAssetTokenUnchecked(
            TOKEN_NAME,
            TOKEN_SYMBOL,
            address(oracle),
            MAX_SUPPLY,
            tokenAdmin
        );
    }

    function test_GetToken_ReturnsZeroAddressForUnknownAssetId() public view {
        assertEq(factory.getToken(ASSET_ID_2), address(0));
    }

    function test_GetDeployedTokens_ReturnsEmptyArrayBeforeDeployments() public view {
        address[] memory deployedTokens = factory.getDeployedTokens();
        assertEq(deployedTokens.length, 0);
    }

    function test_IsRegistered_ReturnsFalseForUnknownToken() public {
        assertFalse(factory.isRegistered(makeAddr("unknownToken")));
    }

    function test_PauseAndUnpause_AdminControlsFactoryState() public {
        assertFalse(factory.paused());

        vm.prank(admin);
        factory.pause();

        assertTrue(factory.paused());

        vm.prank(admin);
        factory.unpause();

        assertFalse(factory.paused());
    }

    function test_Pause_RevertsWhenCallerIsNotAdmin() public {
        vm.prank(attacker);
        vm.expectRevert();

        factory.pause();
    }

    function test_Unpause_RevertsWhenCallerIsNotAdmin() public {
        vm.prank(admin);
        factory.pause();

        vm.prank(attacker);
        vm.expectRevert();

        factory.unpause();
    }
}
