// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {RWATimelockController} from "../src/RWATimelockController.sol";
import {RWAGovernor} from "../src/RWAGovernor.sol";
import {RWAVault} from "../src/RWAVault.sol";
import {AssetTokenV1} from "../src/AssetTokenV1.sol";
import {ChainlinkOracleAdapter} from "../src/ChainlinkOracleAdapter.sol";

/// @notice Post-deployment verification script.
///         Run after Deploy.s.sol to confirm all governance wiring is correct.
///
///         Required env vars:
///           TIMELOCK_ADDRESS, GOVERNOR_ADDRESS, VAULT_ADDRESS,
///           ASSET_TOKEN_ADDRESS, ORACLE_ADDRESS, DEPLOYER_ADDRESS
///
///         Usage:
///           forge script script/VerifyDeployment.s.sol --rpc-url base_sepolia
contract VerifyDeployment is Script {
    uint256 private _passed;
    uint256 private _failed;

    function run() external {
        address timelockAddr = vm.envAddress("TIMELOCK_ADDRESS");
        address governorAddr = vm.envAddress("GOVERNOR_ADDRESS");
        address vaultAddr = vm.envAddress("VAULT_ADDRESS");
        address assetTokenAddr = vm.envAddress("ASSET_TOKEN_ADDRESS");
        address oracleAddr = vm.envAddress("ORACLE_ADDRESS");
        address deployer = vm.envAddress("DEPLOYER_ADDRESS");

        RWATimelockController timelock = RWATimelockController(payable(timelockAddr));
        RWAGovernor governor = RWAGovernor(payable(governorAddr));
        RWAVault vault = RWAVault(vaultAddr);
        AssetTokenV1 assetToken = AssetTokenV1(assetTokenAddr);
        ChainlinkOracleAdapter oracle = ChainlinkOracleAdapter(oracleAddr);

        console2.log("=== RWA Platform Post-Deployment Verification ===\n");

        // ── Timelock ──────────────────────────────────────────────────────────
        _check("Timelock min delay >= 2 days", timelock.getMinDelay() >= 2 days);
        _check("Deployer has renounced TIMELOCK_ADMIN_ROLE", !timelock.hasRole(timelock.DEFAULT_ADMIN_ROLE(), deployer));
        _check("Governor holds PROPOSER_ROLE on Timelock", timelock.hasRole(timelock.PROPOSER_ROLE(), governorAddr));
        _check("Governor holds CANCELLER_ROLE on Timelock", timelock.hasRole(timelock.CANCELLER_ROLE(), governorAddr));
        _check("Anyone can execute (EXECUTOR_ROLE open)", timelock.hasRole(timelock.EXECUTOR_ROLE(), address(0)));

        // ── Governor ─────────────────────────────────────────────────────────
        _check("Governor votingDelay = 43 200 blocks (~1 day)", governor.votingDelay() == 43_200);
        _check("Governor votingPeriod = 302 400 blocks (~1 week)", governor.votingPeriod() == 302_400);
        _check("Governor quorum fraction = 4%", governor.quorumNumerator() == 4);

        // ── Access control on managed contracts ───────────────────────────────
        _check("Vault UPGRADER_ROLE held by Timelock", vault.hasRole(vault.UPGRADER_ROLE(), timelockAddr));
        _check(
            "AssetToken UPGRADER_ROLE held by Timelock", assetToken.hasRole(assetToken.UPGRADER_ROLE(), timelockAddr)
        );
        _check(
            "Deployer does NOT hold AssetToken UPGRADER_ROLE", !assetToken.hasRole(assetToken.UPGRADER_ROLE(), deployer)
        );

        // ── Oracle ownership ──────────────────────────────────────────────────
        _check("Oracle owner is Timelock (not deployer)", oracle.owner() == timelockAddr);

        // ── Summary ───────────────────────────────────────────────────────────
        console2.log("\n--- Summary ---");
        console2.log("Passed :", _passed);
        console2.log("Failed :", _failed);
        if (_failed == 0) {
            console2.log("\nALL CHECKS PASSED -- deployment is correctly wired.");
        } else {
            console2.log("\nSOME CHECKS FAILED -- review wiring before using the protocol.");
        }
    }

    function _check(string memory label, bool condition) internal {
        if (condition) {
            console2.log("[PASS]", label);
            _passed++;
        } else {
            console2.log("[FAIL]", label);
            _failed++;
        }
    }
}
