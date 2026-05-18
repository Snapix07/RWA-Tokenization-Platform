// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {GovernanceToken} from "../../src/GovernanceToken.sol";

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

contract GovernanceTokenTest is Test {
    GovernanceToken internal governanceToken;

    address internal admin = makeAddr("admin");
    address internal minter = makeAddr("minter");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal attacker = makeAddr("attacker");

    uint256 internal constant INITIAL_SUPPLY = 1_000_000 ether;
    uint256 internal constant MINT_AMOUNT = 500 ether;

    uint256 internal permitOwnerPrivateKey = 0xA11CE;
    address internal permitOwner;
    address internal permitSpender = makeAddr("permitSpender");

    bytes32 internal constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    function setUp() public {
        permitOwner = vm.addr(permitOwnerPrivateKey);

        governanceToken = new GovernanceToken(admin, INITIAL_SUPPLY);

        vm.startPrank(admin);
        governanceToken.grantRole(governanceToken.MINTER_ROLE(), minter);
        vm.stopPrank();
    }

    // -------------------------------------------------------------------------
    // Constructor and token configuration
    // -------------------------------------------------------------------------

    function test_Constructor_SetsTokenMetadata() public view {
        assertEq(governanceToken.name(), "RWA Governance Token");
        assertEq(governanceToken.symbol(), "RWAGOV");
        assertEq(governanceToken.decimals(), 18);
    }

    function test_Constructor_AssignsInitialSupplyToAdmin() public view {
        assertEq(governanceToken.totalSupply(), INITIAL_SUPPLY);
        assertEq(governanceToken.balanceOf(admin), INITIAL_SUPPLY);
    }

    function test_Constructor_AssignsAdminAndMinterRoles() public view {
        assertTrue(governanceToken.hasRole(governanceToken.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(governanceToken.hasRole(governanceToken.MINTER_ROLE(), admin));
    }

    function test_Constructor_WithZeroInitialSupplyKeepsSupplyAtZero() public {
        GovernanceToken zeroSupplyToken = new GovernanceToken(admin, 0);

        assertEq(zeroSupplyToken.totalSupply(), 0);
        assertEq(zeroSupplyToken.balanceOf(admin), 0);
    }

    // -------------------------------------------------------------------------
    // Minting and role-gated access
    // -------------------------------------------------------------------------

    function test_Mint_AdminCanMintTokens() public {
        vm.prank(admin);
        governanceToken.mint(alice, MINT_AMOUNT);

        assertEq(governanceToken.balanceOf(alice), MINT_AMOUNT);
        assertEq(governanceToken.totalSupply(), INITIAL_SUPPLY + MINT_AMOUNT);
    }

    function test_Mint_GrantedMinterCanMintTokens() public {
        vm.prank(minter);
        governanceToken.mint(bob, MINT_AMOUNT);

        assertEq(governanceToken.balanceOf(bob), MINT_AMOUNT);
        assertEq(governanceToken.totalSupply(), INITIAL_SUPPLY + MINT_AMOUNT);
    }

    function test_Mint_RevertsWhenCallerLacksMinterRole() public {
        vm.prank(attacker);
        vm.expectRevert();

        governanceToken.mint(alice, MINT_AMOUNT);
    }

    function test_Mint_RevertsWhenReceiverIsZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert();

        governanceToken.mint(address(0), MINT_AMOUNT);
    }

    function test_RevokeMinterRole_PreventsFutureMinting() public {
        bytes32 minterRole = governanceToken.MINTER_ROLE();

        vm.prank(admin);
        governanceToken.revokeRole(minterRole, minter);

        vm.prank(minter);
        vm.expectRevert();

        governanceToken.mint(alice, MINT_AMOUNT);
    }

    // -------------------------------------------------------------------------
    // ERC-20 transfers
    // -------------------------------------------------------------------------

    function test_Transfer_MovesBalancesCorrectly() public {
        uint256 amount = 250 ether;

        vm.prank(admin);
        governanceToken.transfer(alice, amount);

        assertEq(governanceToken.balanceOf(admin), INITIAL_SUPPLY - amount);
        assertEq(governanceToken.balanceOf(alice), amount);
    }

    function test_Transfer_RevertsWhenSenderBalanceIsInsufficient() public {
        vm.prank(alice);
        vm.expectRevert();

        governanceToken.transfer(bob, 1 ether);
    }

    // -------------------------------------------------------------------------
    // ERC20Votes delegation and checkpoints
    // -------------------------------------------------------------------------

    function test_Delegate_AssignsVotingPowerToDelegatee() public {
        uint256 amount = 100 ether;

        vm.prank(admin);
        governanceToken.transfer(alice, amount);

        vm.prank(alice);
        governanceToken.delegate(bob);

        assertEq(governanceToken.delegates(alice), bob);
        assertEq(governanceToken.getVotes(bob), amount);
    }

    function test_Mint_IncreasesVotesWhenReceiverAlreadyDelegated() public {
        vm.prank(alice);
        governanceToken.delegate(alice);

        vm.prank(admin);
        governanceToken.mint(alice, MINT_AMOUNT);

        assertEq(governanceToken.getVotes(alice), MINT_AMOUNT);
    }

    function test_Transfer_MovesDelegatedVotingPower() public {
        uint256 amount = 300 ether;

        vm.prank(admin);
        governanceToken.delegate(admin);

        vm.prank(alice);
        governanceToken.delegate(alice);

        vm.prank(admin);
        governanceToken.transfer(alice, amount);

        assertEq(governanceToken.getVotes(admin), INITIAL_SUPPLY - amount);
        assertEq(governanceToken.getVotes(alice), amount);
    }

    function test_GetPastVotes_ReturnsHistoricalDelegationSnapshot() public {
        uint256 amount = 200 ether;

        // Delegate at a dedicated timestamp.
        vm.warp(block.timestamp + 10);

        vm.prank(admin);
        governanceToken.delegate(admin);

        // Make delegation checkpoint historical.
        vm.warp(block.timestamp + 10);

        uint256 snapshotBeforeTransfer = governanceToken.clock() - 1;

        assertEq(
            governanceToken.getPastVotes(admin, snapshotBeforeTransfer),
            INITIAL_SUPPLY
        );

        // Transfer at a strictly later timestamp.
        vm.warp(block.timestamp + 10);

        vm.prank(admin);
        governanceToken.transfer(alice, amount);

        // Make transfer checkpoint historical.
        vm.warp(block.timestamp + 10);

        uint256 snapshotAfterTransfer = governanceToken.clock() - 1;

        assertEq(
            governanceToken.getPastVotes(admin, snapshotBeforeTransfer),
            INITIAL_SUPPLY
        );

        assertEq(
            governanceToken.getPastVotes(admin, snapshotAfterTransfer),
            INITIAL_SUPPLY - amount
        );
    }

    function test_GetPastTotalSupply_PreservesSnapshotBeforeLaterMint() public {
        // Move forward so the constructor checkpoint is safely historical.
        vm.warp(block.timestamp + 10);

        uint256 snapshotBeforeMint = governanceToken.clock() - 1;

        assertEq(
            governanceToken.getPastTotalSupply(snapshotBeforeMint),
            INITIAL_SUPPLY
        );

        // Mint at a strictly later timestamp.
        vm.warp(block.timestamp + 10);

        vm.prank(admin);
        governanceToken.mint(alice, MINT_AMOUNT);

        // Make the mint checkpoint historical.
        vm.warp(block.timestamp + 10);

        uint256 snapshotAfterMint = governanceToken.clock() - 1;

        assertEq(
            governanceToken.getPastTotalSupply(snapshotBeforeMint),
            INITIAL_SUPPLY
        );

        assertEq(
            governanceToken.getPastTotalSupply(snapshotAfterMint),
            INITIAL_SUPPLY + MINT_AMOUNT
        );
    }

    // -------------------------------------------------------------------------
    // ERC20Permit gasless approval
    // -------------------------------------------------------------------------

    function test_Permit_SetsAllowanceAndIncrementsNonce() public {
        uint256 value = 777 ether;
        uint256 deadline = block.timestamp + 1 days;

        bytes32 structHash = keccak256(
            abi.encode(
                PERMIT_TYPEHASH,
                permitOwner,
                permitSpender,
                value,
                governanceToken.nonces(permitOwner),
                deadline
            )
        );

        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                governanceToken.DOMAIN_SEPARATOR(),
                structHash
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(permitOwnerPrivateKey, digest);

        governanceToken.permit(
            permitOwner,
            permitSpender,
            value,
            deadline,
            v,
            r,
            s
        );

        assertEq(governanceToken.allowance(permitOwner, permitSpender), value);
        assertEq(governanceToken.nonces(permitOwner), 1);
    }

    function test_Permit_RevertsWhenDeadlineExpired() public {
        uint256 value = 100 ether;
        uint256 deadline = block.timestamp - 1;

        bytes32 structHash = keccak256(
            abi.encode(
                PERMIT_TYPEHASH,
                permitOwner,
                permitSpender,
                value,
                governanceToken.nonces(permitOwner),
                deadline
            )
        );

        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                governanceToken.DOMAIN_SEPARATOR(),
                structHash
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(permitOwnerPrivateKey, digest);

        vm.expectRevert();

        governanceToken.permit(
            permitOwner,
            permitSpender,
            value,
            deadline,
            v,
            r,
            s
        );
    }

    function test_Permit_RevertsWhenSignatureIsInvalid() public {
        uint256 value = 100 ether;
        uint256 deadline = block.timestamp + 1 days;

        bytes32 structHash = keccak256(
            abi.encode(
                PERMIT_TYPEHASH,
                permitOwner,
                permitSpender,
                value,
                governanceToken.nonces(permitOwner),
                deadline
            )
        );

        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                governanceToken.DOMAIN_SEPARATOR(),
                structHash
            )
        );

        uint256 wrongPrivateKey = 0xB0B;
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(wrongPrivateKey, digest);

        vm.expectRevert();

        governanceToken.permit(
            permitOwner,
            permitSpender,
            value,
            deadline,
            v,
            r,
            s
        );
    }

    // -------------------------------------------------------------------------
    // Interface support and nonces
    // -------------------------------------------------------------------------

    function test_SupportsAccessControlInterface() public view {
        assertTrue(governanceToken.supportsInterface(type(IAccessControl).interfaceId));
    }

    function test_Nonces_InitiallyZeroForUnusedOwner() public view {
        assertEq(governanceToken.nonces(permitOwner), 0);
    }
}
