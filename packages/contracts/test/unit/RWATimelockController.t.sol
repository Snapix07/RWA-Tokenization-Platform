// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {RWATimelockController} from "../../src/RWATimelockController.sol";

contract TimelockTarget {
    uint256 public value;
    uint256 public secondaryValue;
    address public lastCaller;

    event ValueUpdated(uint256 newValue, address caller);
    event SecondaryValueUpdated(uint256 newValue, address caller);

    function setValue(uint256 newValue) external {
        value = newValue;
        lastCaller = msg.sender;
        emit ValueUpdated(newValue, msg.sender);
    }

    function setSecondaryValue(uint256 newValue) external {
        secondaryValue = newValue;
        lastCaller = msg.sender;
        emit SecondaryValueUpdated(newValue, msg.sender);
    }
}

contract RWATimelockControllerTest is Test {
    RWATimelockController internal timelock;
    TimelockTarget internal target;

    address internal admin = makeAddr("admin");
    address internal proposer = makeAddr("proposer");
    address internal attacker = makeAddr("attacker");

    uint256 internal constant TWO_DAY_DELAY = 2 days;
    uint256 internal constant THREE_DAY_DELAY = 3 days;

    bytes32 internal constant EMPTY_PREDECESSOR = bytes32(0);
    bytes32 internal constant SALT_ONE = keccak256("SALT_ONE");
    bytes32 internal constant SALT_TWO = keccak256("SALT_TWO");
    bytes32 internal constant SALT_BATCH = keccak256("SALT_BATCH");
    bytes32 internal constant SALT_UPDATE_DELAY = keccak256("SALT_UPDATE_DELAY");

    function setUp() public {
        vm.warp(1_700_000_000);

        address[] memory proposers = new address[](1);
        proposers[0] = proposer;

        address[] memory executors = new address[](1);
        executors[0] = address(0); // open executor: anyone can execute ready operations

        timelock = new RWATimelockController(proposers, executors, admin);
        target = new TimelockTarget();
    }

    function _setValueData(uint256 newValue) internal pure returns (bytes memory) {
        return abi.encodeCall(TimelockTarget.setValue, (newValue));
    }

    function _scheduleSetValue(
        uint256 newValue,
        bytes32 salt
    ) internal returns (bytes32 operationId) {
        bytes memory data = _setValueData(newValue);

        operationId = timelock.hashOperation(
            address(target),
            0,
            data,
            EMPTY_PREDECESSOR,
            salt
        );

        vm.prank(proposer);
        timelock.schedule(
            address(target),
            0,
            data,
            EMPTY_PREDECESSOR,
            salt,
            TWO_DAY_DELAY
        );
    }

    function test_Constructor_UsesHardcodedTwoDayMinimumDelay() public view {
        assertEq(timelock.MIN_DELAY(), TWO_DAY_DELAY);
        assertEq(timelock.getMinDelay(), TWO_DAY_DELAY);
    }

    function test_Constructor_AssignsAdminRoleToConfiguredAdminAndSelf() public view {
        assertTrue(timelock.hasRole(timelock.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(timelock.hasRole(timelock.DEFAULT_ADMIN_ROLE(), address(timelock)));
    }

    function test_Constructor_AssignsProposerAndCancellerRoles() public view {
        assertTrue(timelock.hasRole(timelock.PROPOSER_ROLE(), proposer));
        assertTrue(timelock.hasRole(timelock.CANCELLER_ROLE(), proposer));
    }

    function test_Constructor_AssignsOpenExecutorRoleToZeroAddress() public view {
        assertTrue(timelock.hasRole(timelock.EXECUTOR_ROLE(), address(0)));
    }

    // -------------------------------------------------------------------------
    // Scheduling single operations
    // -------------------------------------------------------------------------

    function test_Schedule_RegistersPendingOperationWithExpectedTimestamp() public {
        bytes32 operationId = _scheduleSetValue(42, SALT_ONE);

        assertTrue(timelock.isOperation(operationId));
        assertTrue(timelock.isOperationPending(operationId));
        assertFalse(timelock.isOperationReady(operationId));
        assertFalse(timelock.isOperationDone(operationId));

        assertEq(
            timelock.getTimestamp(operationId),
            block.timestamp + TWO_DAY_DELAY
        );
    }

    function test_Schedule_RevertsWhenCallerLacksProposerRole() public {
        bytes memory data = _setValueData(42);

        vm.prank(attacker);
        vm.expectRevert();

        timelock.schedule(
            address(target),
            0,
            data,
            EMPTY_PREDECESSOR,
            SALT_ONE,
            TWO_DAY_DELAY
        );
    }

    function test_Schedule_RevertsWhenDelayIsBelowMinimumDelay() public {
        bytes memory data = _setValueData(42);

        vm.prank(proposer);
        vm.expectRevert();

        timelock.schedule(
            address(target),
            0,
            data,
            EMPTY_PREDECESSOR,
            SALT_ONE,
            TWO_DAY_DELAY - 1
        );
    }

    function test_Schedule_RevertsWhenSameOperationIsScheduledTwice() public {
        bytes memory data = _setValueData(42);

        vm.startPrank(proposer);

        timelock.schedule(
            address(target),
            0,
            data,
            EMPTY_PREDECESSOR,
            SALT_ONE,
            TWO_DAY_DELAY
        );

        vm.expectRevert();

        timelock.schedule(
            address(target),
            0,
            data,
            EMPTY_PREDECESSOR,
            SALT_ONE,
            TWO_DAY_DELAY
        );

        vm.stopPrank();
    }

    function test_Execute_RevertsBeforeOperationBecomesReady() public {
        _scheduleSetValue(42, SALT_ONE);

        bytes memory data = _setValueData(42);

        vm.prank(attacker);
        vm.expectRevert();

        timelock.execute(
            address(target),
            0,
            data,
            EMPTY_PREDECESSOR,
            SALT_ONE
        );
    }

    function test_Execute_AfterDelayRunsOperationAndMarksItDone() public {
        bytes32 operationId = _scheduleSetValue(42, SALT_ONE);

        vm.warp(block.timestamp + TWO_DAY_DELAY);

        bytes memory data = _setValueData(42);

        vm.prank(attacker);
        timelock.execute(
            address(target),
            0,
            data,
            EMPTY_PREDECESSOR,
            SALT_ONE
        );

        assertEq(target.value(), 42);
        assertEq(target.lastCaller(), address(timelock));

        assertTrue(timelock.isOperationDone(operationId));
        assertFalse(timelock.isOperationReady(operationId));
    }

    function test_Execute_RevertsWhenOperationIsExecutedTwice() public {
        _scheduleSetValue(42, SALT_ONE);

        vm.warp(block.timestamp + TWO_DAY_DELAY);

        bytes memory data = _setValueData(42);

        vm.startPrank(attacker);

        timelock.execute(
            address(target),
            0,
            data,
            EMPTY_PREDECESSOR,
            SALT_ONE
        );

        vm.expectRevert();

        timelock.execute(
            address(target),
            0,
            data,
            EMPTY_PREDECESSOR,
            SALT_ONE
        );

        vm.stopPrank();
    }

    function test_Cancel_CancellerRoleCanCancelPendingOperation() public {
        bytes32 operationId = _scheduleSetValue(42, SALT_ONE);

        vm.prank(proposer);
        timelock.cancel(operationId);

        assertFalse(timelock.isOperation(operationId));
        assertFalse(timelock.isOperationPending(operationId));
        assertEq(timelock.getTimestamp(operationId), 0);
    }

    function test_Cancel_RevertsWhenCallerLacksCancellerRole() public {
        bytes32 operationId = _scheduleSetValue(42, SALT_ONE);

        vm.prank(attacker);
        vm.expectRevert();

        timelock.cancel(operationId);
    }

    function test_Cancel_PreventsLaterExecution() public {
        bytes32 operationId = _scheduleSetValue(42, SALT_ONE);

        vm.prank(proposer);
        timelock.cancel(operationId);

        vm.warp(block.timestamp + TWO_DAY_DELAY);

        bytes memory data = _setValueData(42);

        vm.prank(attacker);
        vm.expectRevert();

        timelock.execute(
            address(target),
            0,
            data,
            EMPTY_PREDECESSOR,
            SALT_ONE
        );
    }

    function test_ScheduleBatchAndExecuteBatch_RunMultipleCallsAfterDelay() public {
        address[] memory targets = new address[](2);
        targets[0] = address(target);
        targets[1] = address(target);

        uint256[] memory values = new uint256[](2);
        values[0] = 0;
        values[1] = 0;

        bytes[] memory payloads = new bytes[](2);
        payloads[0] = abi.encodeCall(TimelockTarget.setValue, (111));
        payloads[1] = abi.encodeCall(TimelockTarget.setSecondaryValue, (222));

        bytes32 operationId = timelock.hashOperationBatch(
            targets,
            values,
            payloads,
            EMPTY_PREDECESSOR,
            SALT_BATCH
        );

        vm.prank(proposer);
        timelock.scheduleBatch(
            targets,
            values,
            payloads,
            EMPTY_PREDECESSOR,
            SALT_BATCH,
            TWO_DAY_DELAY
        );

        assertTrue(timelock.isOperationPending(operationId));

        vm.warp(block.timestamp + TWO_DAY_DELAY);

        vm.prank(attacker);
        timelock.executeBatch(
            targets,
            values,
            payloads,
            EMPTY_PREDECESSOR,
            SALT_BATCH
        );

        assertEq(target.value(), 111);
        assertEq(target.secondaryValue(), 222);
        assertTrue(timelock.isOperationDone(operationId));
    }

    function test_Execute_WithPredecessorRequiresEarlierOperationToFinishFirst() public {
        bytes memory firstData = _setValueData(10);
        bytes memory secondData = _setValueData(20);

        bytes32 firstOperationId = timelock.hashOperation(
            address(target),
            0,
            firstData,
            EMPTY_PREDECESSOR,
            SALT_ONE
        );

        bytes32 secondOperationId = timelock.hashOperation(
            address(target),
            0,
            secondData,
            firstOperationId,
            SALT_TWO
        );

        vm.startPrank(proposer);

        timelock.schedule(
            address(target),
            0,
            firstData,
            EMPTY_PREDECESSOR,
            SALT_ONE,
            TWO_DAY_DELAY
        );

        timelock.schedule(
            address(target),
            0,
            secondData,
            firstOperationId,
            SALT_TWO,
            TWO_DAY_DELAY
        );

        vm.stopPrank();

        vm.warp(block.timestamp + TWO_DAY_DELAY);

        vm.prank(attacker);
        vm.expectRevert();

        timelock.execute(
            address(target),
            0,
            secondData,
            firstOperationId,
            SALT_TWO
        );

        vm.prank(attacker);
        timelock.execute(
            address(target),
            0,
            firstData,
            EMPTY_PREDECESSOR,
            SALT_ONE
        );

        vm.prank(attacker);
        timelock.execute(
            address(target),
            0,
            secondData,
            firstOperationId,
            SALT_TWO
        );

        assertTrue(timelock.isOperationDone(firstOperationId));
        assertTrue(timelock.isOperationDone(secondOperationId));
        assertEq(target.value(), 20);
    }

    function test_UpdateDelay_RevertsWhenCalledDirectlyByAdmin() public {
        vm.prank(admin);
        vm.expectRevert();

        timelock.updateDelay(THREE_DAY_DELAY);
    }

    function test_UpdateDelay_SucceedsOnlyThroughScheduledSelfCall() public {
        bytes memory updateDelayCall =
            abi.encodeWithSignature("updateDelay(uint256)", THREE_DAY_DELAY);

        bytes32 operationId = timelock.hashOperation(
            address(timelock),
            0,
            updateDelayCall,
            EMPTY_PREDECESSOR,
            SALT_UPDATE_DELAY
        );

        vm.prank(proposer);
        timelock.schedule(
            address(timelock),
            0,
            updateDelayCall,
            EMPTY_PREDECESSOR,
            SALT_UPDATE_DELAY,
            TWO_DAY_DELAY
        );

        vm.warp(block.timestamp + TWO_DAY_DELAY);

        vm.prank(attacker);
        timelock.execute(
            address(timelock),
            0,
            updateDelayCall,
            EMPTY_PREDECESSOR,
            SALT_UPDATE_DELAY
        );

        assertTrue(timelock.isOperationDone(operationId));
        assertEq(timelock.getMinDelay(), THREE_DAY_DELAY);
    }
}
