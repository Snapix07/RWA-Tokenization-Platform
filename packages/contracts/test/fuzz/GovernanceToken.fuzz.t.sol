// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {GovernanceToken} from "../../src/GovernanceToken.sol";

contract GovernanceTokenFuzzTest is Test {
    GovernanceToken internal token;

    address internal admin = makeAddr("admin");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol");

    uint256 internal constant INITIAL_SUPPLY = 1_000_000 ether;

    function setUp() public {
        vm.roll(100);

        token = new GovernanceToken(admin, INITIAL_SUPPLY);

        vm.startPrank(admin);
        token.transfer(alice, 300_000 ether);
        token.transfer(bob, 300_000 ether);
        token.transfer(carol, 100_000 ether);
        vm.stopPrank();
    }

    function testFuzz_Delegate_AssignsExactVotingPowerToSelf(uint96 rawAmount) public {
        uint256 amount = bound(
            uint256(rawAmount),
            1 ether,
            100_000 ether
        );

        vm.prank(admin);
        token.transfer(alice, amount);

        uint256 aliceBalance = token.balanceOf(alice);

        vm.prank(alice);
        token.delegate(alice);

        assertEq(token.getVotes(alice), aliceBalance);
    }

    function testFuzz_Transfer_MovesVotingPowerBetweenDelegatedAccounts(uint96 rawAmount) public {
        uint256 amount = bound(
            uint256(rawAmount),
            1 ether,
            100_000 ether
        );

        vm.prank(alice);
        token.delegate(alice);

        vm.prank(bob);
        token.delegate(bob);

        uint256 aliceVotesBefore = token.getVotes(alice);
        uint256 bobVotesBefore = token.getVotes(bob);

        vm.prank(alice);
        token.transfer(bob, amount);

        assertEq(token.getVotes(alice), aliceVotesBefore - amount);
        assertEq(token.getVotes(bob), bobVotesBefore + amount);
    }

    function testFuzz_Mint_IncreasesVotesForAlreadyDelegatedReceiver(uint96 rawAmount) public {
        uint256 amount = bound(
            uint256(rawAmount),
            1 ether,
            100_000 ether
        );

        vm.prank(alice);
        token.delegate(alice);

        uint256 votesBefore = token.getVotes(alice);

        vm.prank(admin);
        token.mint(alice, amount);

        assertEq(token.getVotes(alice), votesBefore + amount);
    }

    function testFuzz_Transfer_PreservesCombinedVotesAcrossTwoDelegatedAccounts(uint96 rawAmount) public {
        uint256 amount = bound(
            uint256(rawAmount),
            1 ether,
            100_000 ether
        );

        vm.prank(alice);
        token.delegate(alice);

        vm.prank(bob);
        token.delegate(bob);

        uint256 combinedVotesBefore =
            token.getVotes(alice) + token.getVotes(bob);

        vm.prank(alice);
        token.transfer(bob, amount);

        uint256 combinedVotesAfter =
            token.getVotes(alice) + token.getVotes(bob);

        assertEq(combinedVotesAfter, combinedVotesBefore);
    }

    function testFuzz_GetPastVotes_PreservesHistoricalVotingPower(uint96 rawTransferAmount) public {
        uint256 transferAmount = bound(
            uint256(rawTransferAmount),
            1 ether,
            100_000 ether
        );

        vm.prank(alice);
        token.delegate(alice);

        vm.roll(200);

        uint256 snapshotBlock = 199;
        uint256 historicalVotes = token.getPastVotes(alice, snapshotBlock);

        vm.prank(alice);
        token.transfer(bob, transferAmount);

        vm.roll(201);

        assertEq(historicalVotes, 300_000 ether);
        assertEq(token.getPastVotes(alice, snapshotBlock), 300_000 ether);
        assertEq(token.getVotes(alice), 300_000 ether - transferAmount);
    }
}
