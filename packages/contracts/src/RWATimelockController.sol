// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

/// @title RWATimelockController
/// @notice Thin wrapper around OZ TimelockController with a hardcoded 2-day minimum delay.
///         Keeping it as a named contract gives a clean Basescan artifact and a place to
///         add project-specific cancellation logic if needed.
///
/// Deployment sequence:
///   1. Deploy this contract with empty proposers (Governor not yet deployed).
///   2. Deploy RWAGovernor, passing this contract as the timelock.
///   3. Grant PROPOSER_ROLE and CANCELLER_ROLE to the Governor on this contract.
///   4. Renounce TIMELOCK_ADMIN_ROLE from the deployer.
///
/// Design patterns: Timelock.
contract RWATimelockController is TimelockController {
    uint256 public constant MIN_DELAY = 2 days;

    /// @param proposers  Initially empty; the Governor is added after deployment.
    /// @param executors  Pass [address(0)] to allow anyone to execute ready proposals.
    /// @param admin      Deployer address — must renounce TIMELOCK_ADMIN_ROLE after setup.
    constructor(address[] memory proposers, address[] memory executors, address admin)
        TimelockController(MIN_DELAY, proposers, executors, admin)
    {}
}
