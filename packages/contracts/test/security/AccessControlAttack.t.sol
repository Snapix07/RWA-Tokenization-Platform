// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {AssetFactory} from "../../src/AssetFactory.sol";
import {AssetTokenV1} from "../../src/AssetTokenV1.sol";
import {ChainlinkOracleAdapter} from "../../src/ChainlinkOracleAdapter.sol";
import {MockAggregator} from "../../src/mocks/MockAggregator.sol";

// ============================================================
// SECURITY CASE STUDY S-02: Missing Access Control on Factory
// ============================================================
//
// Finding   : S-02
// Severity  : High
// Pattern   : Unguarded privileged function
// Status    : Fixed — AssetFactory requires FACTORY_ROLE on deployAssetToken
//
// Root cause:
//   A factory without role checks on deployment functions allows any address
//   to create arbitrary token contracts under the platform's name, enabling
//   rugpull tokens, fake reserve reports, and oracle poisoning.
//
// Proof-of-concept (test_AccessControl_VulnerableFactory):
//   An arbitrary attacker address calls deployToken() on VulnerableFactory
//   and successfully creates a token without authorization.
//
// Fix (test_AccessControl_FixedFactory):
//   AssetFactory enforces FACTORY_ROLE. Unauthorized calls revert with
//   AccessControlUnauthorizedAccount.

// ─────────────────────────────────────────────────────────────────────────────
// Vulnerable implementation (before fix)
// ─────────────────────────────────────────────────────────────────────────────

contract SimpleToken {
    string public name;

    constructor(string memory _name) {
        name = _name;
    }
}

/// @dev Factory with NO access control — anyone can deploy tokens.
contract VulnerableFactory {
    address[] public deployedTokens;

    // VULNERABLE: no role check — any address can call this
    function deployToken(string calldata name) external returns (address token) {
        token = address(new SimpleToken(name));
        deployedTokens.push(token);
    }

    function getDeployedCount() external view returns (uint256) {
        return deployedTokens.length;
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tests
// ─────────────────────────────────────────────────────────────────────────────

contract AccessControlAttackTest is Test {
    address admin = makeAddr("admin");
    address attacker = makeAddr("attacker");
    address authorizedIssuer = makeAddr("authorizedIssuer");

    VulnerableFactory vulnerableFactory;
    AssetFactory fixedFactory;
    AssetTokenV1 implementation;
    ChainlinkOracleAdapter oracle;
    MockAggregator mockFeed;

    bytes32 constant ASSET_ID = keccak256("LEGIT_ASSET");

    function setUp() public {
        vulnerableFactory = new VulnerableFactory();

        vm.startPrank(admin);
        implementation = new AssetTokenV1();
        fixedFactory = new AssetFactory(admin, address(implementation));
        oracle = new ChainlinkOracleAdapter(admin);
        mockFeed = new MockAggregator(2000e8, 8); // $2000, 8 decimals
        oracle.addFeed(ASSET_ID, address(mockFeed), 3600);
        vm.stopPrank();
    }

    // ── Before fix ───────────────────────────────────────────────────────────

    /// @dev BEFORE FIX: attacker deploys a fraudulent token with no authorization.
    function test_AccessControl_VulnerableFactory() public {
        assertEq(vulnerableFactory.getDeployedCount(), 0);

        vm.prank(attacker);
        address fraudToken = vulnerableFactory.deployToken("FAKE RWA TOKEN");

        // Attack succeeded — fraudulent token now exists in the registry
        assertEq(vulnerableFactory.getDeployedCount(), 1, "attacker deployed token without authorization");
        assertEq(vulnerableFactory.deployedTokens(0), fraudToken, "fraudulent token registered");

        console2.log("VULNERABLE: attacker deployed fake token at", fraudToken);
    }

    // ── After fix ────────────────────────────────────────────────────────────

    /// @dev AFTER FIX: attacker cannot deploy via AssetFactory — reverts without FACTORY_ROLE.
    function test_AccessControl_FixedFactory_AttackerReverts() public {
        vm.prank(attacker);
        vm.expectRevert(); // AccessControlUnauthorizedAccount
        fixedFactory.deployAssetToken(ASSET_ID, "FAKE RWA TOKEN", "FAKE", address(oracle), 0, attacker);

        assertEq(fixedFactory.getDeployedTokens().length, 0, "no tokens deployed by attacker");
        console2.log("FIXED: attacker deployment correctly reverted");
    }

    /// @dev AFTER FIX: authorized issuer with FACTORY_ROLE deploys successfully.
    function test_AccessControl_FixedFactory_AuthorizedIssuerSucceeds() public {
        // Read role constant BEFORE pranking — calling a getter consumes vm.prank
        bytes32 factoryRole = fixedFactory.FACTORY_ROLE();
        vm.prank(admin);
        fixedFactory.grantRole(factoryRole, authorizedIssuer);

        vm.prank(authorizedIssuer);
        address token =
            fixedFactory.deployAssetToken(ASSET_ID, "NYC Office Fund Token", "NYCOFF", address(oracle), 0, admin);

        assertTrue(fixedFactory.isRegistered(token), "legitimate token registered");
        assertEq(fixedFactory.getToken(ASSET_ID), token, "token mapped to assetId");
        console2.log("FIXED: authorized issuer deployed token at", token);
    }

    /// @dev AFTER FIX: revoking FACTORY_ROLE immediately blocks further deployments.
    function test_AccessControl_FixedFactory_RevokeRole() public {
        bytes32 FACTORY_ROLE = fixedFactory.FACTORY_ROLE();
        bytes32 ASSET_ID_2 = keccak256("SECOND_ASSET");

        vm.startPrank(admin);
        fixedFactory.grantRole(FACTORY_ROLE, authorizedIssuer);
        vm.stopPrank();

        // First deployment: succeeds
        vm.prank(authorizedIssuer);
        fixedFactory.deployAssetToken(ASSET_ID, "Token One", "TOK1", address(oracle), 0, admin);

        // Admin revokes role mid-operation
        vm.prank(admin);
        fixedFactory.revokeRole(FACTORY_ROLE, authorizedIssuer);

        // Second deployment: reverts immediately
        vm.prank(authorizedIssuer);
        vm.expectRevert();
        fixedFactory.deployAssetToken(ASSET_ID_2, "Token Two", "TOK2", address(oracle), 0, admin);

        assertEq(fixedFactory.getDeployedTokens().length, 1, "only one token deployed");
    }
}
