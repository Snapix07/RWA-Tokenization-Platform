// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

import {GovernanceToken} from "../src/GovernanceToken.sol";
import {AssetNFT} from "../src/AssetNFT.sol";
import {AssetTokenV1} from "../src/AssetTokenV1.sol";
import {AssetTokenV2} from "../src/AssetTokenV2.sol";
import {AssetFactory} from "../src/AssetFactory.sol";
import {ChainlinkOracleAdapter} from "../src/ChainlinkOracleAdapter.sol";
import {RWAVault} from "../src/RWAVault.sol";
import {RWAAMM} from "../src/RWAAMM.sol";
import {RWATimelockController} from "../src/RWATimelockController.sol";
import {RWAGovernor} from "../src/RWAGovernor.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";

/// @notice Idempotent deployment script for the RWA Tokenization Platform.
///         Run with: forge script script/Deploy.s.sol --rpc-url base_sepolia --broadcast --verify
///
/// Post-deployment verification is done by VerifyDeployment.s.sol in the same directory.
contract Deploy is Script {
    // -----------------------------------------------------------------------
    // Configuration — edit before deploying to a new network
    // -----------------------------------------------------------------------

    uint256 constant INITIAL_GOV_SUPPLY = 10_000_000 * 1e18; // 10 M RWAGOV
    uint256 constant VAULT_DEPOSIT_CAP = 0; // 0 = uncapped for testnet

    // Arbitrum Sepolia live Chainlink ETH/USD feed
    address constant ETH_USD_FEED = 0xd30e2101a97dcbAeBCBC04F14C3f624E67A35165;
    uint96 constant FEED_STALENESS = 3600; // 1 hour

    // Demo asset identifiers
    bytes32 constant ASSET_RE = keccak256("NYC_OFFICE_FUND_1");
    bytes32 constant ASSET_ETH_BACKED = keccak256("ETH_BACKED_BOND_1");

    // -----------------------------------------------------------------------

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        vm.startBroadcast(deployerKey);

        // 1. Governance token
        GovernanceToken govToken = new GovernanceToken(deployer, INITIAL_GOV_SUPPLY);
        console2.log("GovernanceToken   :", address(govToken));

        // 2. Oracle adapter + demo feeds
        ChainlinkOracleAdapter oracle = new ChainlinkOracleAdapter(deployer);
        oracle.addFeed(ASSET_ETH_BACKED, ETH_USD_FEED, FEED_STALENESS);
        console2.log("OracleAdapter     :", address(oracle));

        // 3. Asset NFT
        AssetNFT nft = new AssetNFT(deployer);
        console2.log("AssetNFT          :", address(nft));

        // 4. AssetToken implementations (logic contracts, not proxies)
        AssetTokenV1 implV1 = new AssetTokenV1();
        AssetTokenV2 implV2 = new AssetTokenV2();
        console2.log("AssetTokenV1 impl :", address(implV1));
        console2.log("AssetTokenV2 impl :", address(implV2));

        // 5. Factory — deploys asset token proxies via CREATE2
        AssetFactory factory = new AssetFactory(deployer, address(implV1));
        console2.log("AssetFactory      :", address(factory));

        // 6. Deploy a demo ETH-backed AssetToken via factory (CREATE2)
        address assetToken = factory.deployAssetToken(
            ASSET_ETH_BACKED,
            "ETH Backed Bond Token",
            "ETHBOND",
            address(oracle),
            0, // uncapped
            deployer
        );
        console2.log("AssetToken (proxy):", assetToken);

        // 7. RWAVault — UUPS proxy around vault implementation
        RWAVault vaultImpl = new RWAVault();
        bytes memory vaultInit = abi.encodeCall(
            RWAVault.initialize,
            (assetToken, "RWA Vault Share", "rvETHBOND", address(oracle), ASSET_ETH_BACKED, VAULT_DEPOSIT_CAP, deployer)
        );
        ERC1967Proxy vaultProxy = new ERC1967Proxy(address(vaultImpl), vaultInit);
        console2.log("RWAVault (proxy)  :", address(vaultProxy));

        // 8. AMM — GovernanceToken / AssetToken pair
        RWAAMM amm = new RWAAMM(address(govToken), assetToken, deployer);
        console2.log("RWAAMM            :", address(amm));

        // 9. Timelock — start with no proposers; Governor added below
        address[] memory proposers = new address[](0);
        address[] memory executors = new address[](1);
        executors[0] = address(0); // anyone can execute ready proposals
        RWATimelockController timelock = new RWATimelockController(proposers, executors, deployer);
        console2.log("Timelock          :", address(timelock));

        // 10. Governor
        RWAGovernor governor =
            new RWAGovernor(IVotes(address(govToken)), TimelockController(payable(address(timelock))));
        console2.log("Governor          :", address(governor));

        // 11. Wire up governance roles
        // Governor can propose and cancel in the Timelock
        timelock.grantRole(timelock.PROPOSER_ROLE(), address(governor));
        timelock.grantRole(timelock.CANCELLER_ROLE(), address(governor));

        // Timelock controls upgrades on the vault and the demo asset token
        RWAVault(address(vaultProxy)).grantRole(RWAVault(address(vaultProxy)).UPGRADER_ROLE(), address(timelock));
        AssetTokenV1(assetToken).grantRole(AssetTokenV1(assetToken).UPGRADER_ROLE(), address(timelock));

        // Timelock controls oracle feed management
        oracle.transferOwnership(address(timelock));

        // Deployer renounces Timelock admin so no backdoor remains
        timelock.renounceRole(timelock.DEFAULT_ADMIN_ROLE(), deployer);

        vm.stopBroadcast();

        console2.log("--- Deployment complete ---");
        console2.log("Verify with: forge script script/VerifyDeployment.s.sol --rpc-url base_sepolia");
    }
}
