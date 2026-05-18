// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";

import {RWAGovernor} from "../../src/RWAGovernor.sol";
import {RWATimelockController} from "../../src/RWATimelockController.sol";
import {GovernanceToken} from "../../src/GovernanceToken.sol";

contract GovernanceTarget {
    uint256 public value;
    address public lastCaller;

    event ValueUpdated(uint256 newValue, address caller);

    function setValue(uint256 newValue) external {
        value = newValue;
        lastCaller = msg.sender;
        emit ValueUpdated(newValue, msg.sender);
    }
}

contract RWAGovernorTest is Test {
    GovernanceToken internal token;
    RWATimelockController internal timelock;
    RWAGovernor internal governor;
    GovernanceTarget internal target;

    address internal admin = makeAddr("admin");
    address internal proposer = makeAddr("proposer");
    address internal voter = makeAddr("voter");
    address internal attacker = makeAddr("attacker");

    uint256 internal constant INITIAL_SUPPLY = 1_000_000 ether;
    uint256 internal constant PROPOSER_BALANCE = 20_000 ether;
    uint256 internal constant VOTER_BALANCE = 100_000 ether;

    uint256 internal constant VOTING_DELAY = 60;
    uint256 internal constant VOTING_PERIOD = 900;
    uint256 internal constant TIMELOCK_DELAY = 1 minutes;

    string internal constant DESCRIPTION = "Proposal: set governance target value to 42";

    function setUp() public {
        vm.warp(1_700_000_000);
        vm.roll(100);

        token = new GovernanceToken(admin, INITIAL_SUPPLY);

        address[] memory proposers = new address[](0);
        address[] memory executors = new address[](1);
        executors[0] = address(0);

        timelock = new RWATimelockController(proposers, executors, admin);
        governor = new RWAGovernor(token, timelock);
        target = new GovernanceTarget();

        bytes32 proposerRole = timelock.PROPOSER_ROLE();
        bytes32 cancellerRole = timelock.CANCELLER_ROLE();

        vm.startPrank(admin);
        timelock.grantRole(proposerRole, address(governor));
        timelock.grantRole(cancellerRole, address(governor));

        token.transfer(proposer, PROPOSER_BALANCE);
        token.transfer(voter, VOTER_BALANCE);
        vm.stopPrank();

        vm.prank(admin);
        token.delegate(admin);

        vm.prank(proposer);
        token.delegate(proposer);

        vm.prank(voter);
        token.delegate(voter);

        // Make all delegation checkpoints historical.
        vm.warp(block.timestamp + 1);
    }

    function _proposalPayload()
        internal
        view
        returns (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas,
            bytes32 descriptionHash
        )
    {
        targets = new address[](1);
        targets[0] = address(target);

        values = new uint256[](1);
        values[0] = 0;

        calldatas = new bytes[](1);
        calldatas[0] = abi.encodeCall(GovernanceTarget.setValue, (42));

        descriptionHash = keccak256(bytes(DESCRIPTION));
    }

    function _createProposal() internal returns (uint256 proposalId) {
        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas,

        ) = _proposalPayload();

        vm.prank(proposer);
        proposalId = governor.propose(
            targets,
            values,
            calldatas,
            DESCRIPTION
        );
    }

    function _moveToActive(uint256 proposalId) internal {
        uint256 snapshot = governor.proposalSnapshot(proposalId);
        vm.warp(snapshot + 1);
    }

    function _movePastDeadline(uint256 proposalId) internal {
        uint256 deadline = governor.proposalDeadline(proposalId);
        vm.warp(deadline + 1);
    }

    function _passProposal(uint256 proposalId) internal {
        _moveToActive(proposalId);

        vm.prank(voter);
        governor.castVote(proposalId, 1);

        _movePastDeadline(proposalId);
    }

    function test_Constructor_SetsGovernorNameTimelockAndCoreParameters() public view {
        assertEq(governor.name(), "RWA DAO");
        assertEq(governor.version(), "1");

        assertEq(governor.timelock(), address(timelock));
        assertEq(governor.votingDelay(), VOTING_DELAY);
        assertEq(governor.votingPeriod(), VOTING_PERIOD);
    }

    function test_ProposalNeedsQueuing_IsAlwaysTrueForTimelockGovernor() public {
        uint256 proposalId = _createProposal();

        assertTrue(governor.proposalNeedsQueuing(proposalId));
    }

    function test_ProposalThreshold_EqualsOnePercentOfCurrentTokenSupply() public view {
        assertEq(governor.proposalThreshold(), INITIAL_SUPPLY / 100);
    }

    function test_ProposalThreshold_UpdatesWhenTokenSupplyChanges() public {
        vm.prank(admin);
        token.mint(admin, 500_000 ether);

        assertEq(governor.proposalThreshold(), 15_000 ether);
    }

    function test_Quorum_EqualsFourPercentOfPastTotalSupply() public {
        uint256 snapshotTimepoint = block.timestamp - 1;

        assertEq(governor.quorum(snapshotTimepoint), 40_000 ether);
    }

    function test_Propose_CreatesPendingProposalWithExpectedSnapshotAndDeadline() public {
        uint256 currentTimepoint = block.timestamp;
        uint256 proposalId = _createProposal();

        assertEq(
            uint8(governor.state(proposalId)),
            uint8(IGovernor.ProposalState.Pending)
        );

        assertEq(
            governor.proposalSnapshot(proposalId),
            currentTimepoint + VOTING_DELAY
        );

        assertEq(
            governor.proposalDeadline(proposalId),
            currentTimepoint + VOTING_DELAY + VOTING_PERIOD
        );

        assertEq(governor.proposalProposer(proposalId), proposer);
    }

    function test_Propose_RevertsWhenProposerVotesAreBelowThreshold() public {
        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas,

        ) = _proposalPayload();

        vm.prank(attacker);
        vm.expectRevert();

        governor.propose(
            targets,
            values,
            calldatas,
            DESCRIPTION
        );
    }

    function test_Propose_RevertsWhenTargetArraysAreEmpty() public {
        address[] memory targets = new address[](0);
        uint256[] memory values = new uint256[](0);
        bytes[] memory calldatas = new bytes[](0);

        vm.prank(proposer);
        vm.expectRevert();

        governor.propose(
            targets,
            values,
            calldatas,
            DESCRIPTION
        );
    }

    function test_State_BecomesActiveAfterVotingDelay() public {
        uint256 proposalId = _createProposal();

        _moveToActive(proposalId);

        assertEq(
            uint8(governor.state(proposalId)),
            uint8(IGovernor.ProposalState.Active)
        );
    }

    function test_CastVote_RecordsVotingWeightDuringActivePeriod() public {
        uint256 proposalId = _createProposal();

        _moveToActive(proposalId);

        vm.prank(voter);
        uint256 weight = governor.castVote(proposalId, 1);

        assertEq(weight, VOTER_BALANCE);
        assertTrue(governor.hasVoted(proposalId, voter));
    }

    function test_CastVote_RevertsBeforeProposalBecomesActive() public {
        uint256 proposalId = _createProposal();

        vm.prank(voter);
        vm.expectRevert();

        governor.castVote(proposalId, 1);
    }

    function test_CastVote_RevertsWhenSameVoterVotesTwice() public {
        uint256 proposalId = _createProposal();

        _moveToActive(proposalId);

        vm.startPrank(voter);
        governor.castVote(proposalId, 1);

        vm.expectRevert();
        governor.castVote(proposalId, 1);
        vm.stopPrank();
    }

    function test_State_BecomesSucceededWhenQuorumReachedAndForVotesWin() public {
        uint256 proposalId = _createProposal();

        _passProposal(proposalId);

        assertEq(
            uint8(governor.state(proposalId)),
            uint8(IGovernor.ProposalState.Succeeded)
        );
    }

    function test_State_BecomesDefeatedWhenNoVotesAreCast() public {
        uint256 proposalId = _createProposal();

        _movePastDeadline(proposalId);

        assertEq(
            uint8(governor.state(proposalId)),
            uint8(IGovernor.ProposalState.Defeated)
        );
    }

    function test_CastVote_RevertsAfterVotingPeriodEnds() public {
        uint256 proposalId = _createProposal();

        _movePastDeadline(proposalId);

        vm.prank(voter);
        vm.expectRevert();

        governor.castVote(proposalId, 1);
    }

    function test_Queue_MovesSucceededProposalToQueuedState() public {
        uint256 proposalId = _createProposal();
        _passProposal(proposalId);

        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas,
            bytes32 descriptionHash
        ) = _proposalPayload();

        governor.queue(
            targets,
            values,
            calldatas,
            descriptionHash
        );

        assertEq(
            uint8(governor.state(proposalId)),
            uint8(IGovernor.ProposalState.Queued)
        );

        assertEq(governor.proposalEta(proposalId), block.timestamp + TIMELOCK_DELAY);
    }

    function test_Queue_RevertsBeforeProposalSucceeds() public {
        uint256 proposalId = _createProposal();
        proposalId;

        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas,
            bytes32 descriptionHash
        ) = _proposalPayload();

        vm.expectRevert();

        governor.queue(
            targets,
            values,
            calldatas,
            descriptionHash
        );
    }

    function test_Execute_RevertsBeforeTimelockDelayExpires() public {
        uint256 proposalId = _createProposal();
        _passProposal(proposalId);

        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas,
            bytes32 descriptionHash
        ) = _proposalPayload();

        governor.queue(
            targets,
            values,
            calldatas,
            descriptionHash
        );

        vm.expectRevert();

        governor.execute(
            targets,
            values,
            calldatas,
            descriptionHash
        );
    }

    function test_Execute_AfterTimelockDelayRunsProposalAndMarksExecuted() public {
        uint256 proposalId = _createProposal();
        _passProposal(proposalId);

        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas,
            bytes32 descriptionHash
        ) = _proposalPayload();

        governor.queue(
            targets,
            values,
            calldatas,
            descriptionHash
        );

        vm.warp(governor.proposalEta(proposalId));

        governor.execute(
            targets,
            values,
            calldatas,
            descriptionHash
        );

        assertEq(target.value(), 42);
        assertEq(target.lastCaller(), address(timelock));

        assertEq(
            uint8(governor.state(proposalId)),
            uint8(IGovernor.ProposalState.Executed)
        );
    }

    function test_Cancel_ProposerCanCancelPendingProposal() public {
        uint256 proposalId = _createProposal();

        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas,
            bytes32 descriptionHash
        ) = _proposalPayload();

        vm.prank(proposer);
        governor.cancel(
            targets,
            values,
            calldatas,
            descriptionHash
        );

        assertEq(
            uint8(governor.state(proposalId)),
            uint8(IGovernor.ProposalState.Canceled)
        );
    }

    function test_Cancel_RevertsWhenCallerIsNotProposalProposer() public {
        uint256 proposalId = _createProposal();
        proposalId;

        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas,
            bytes32 descriptionHash
        ) = _proposalPayload();

        vm.prank(attacker);
        vm.expectRevert();

        governor.cancel(
            targets,
            values,
            calldatas,
            descriptionHash
        );
    }

    function test_Cancel_RevertsAfterProposalBecomesActive() public {
        uint256 proposalId = _createProposal();

        _moveToActive(proposalId);

        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas,
            bytes32 descriptionHash
        ) = _proposalPayload();

        vm.prank(proposer);
        vm.expectRevert();

        governor.cancel(
            targets,
            values,
            calldatas,
            descriptionHash
        );
    }

    function test_ReceiveEther_RevertsBecauseTimelockIsExternalExecutor() public {
        vm.deal(attacker, 1 ether);

        vm.prank(attacker);
        (bool success,) = address(governor).call{value: 1 ether}("");

        assertFalse(success);
    }
}
