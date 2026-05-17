// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {RWAVault} from "../../src/RWAVault.sol";
import {ChainlinkOracleAdapter} from "../../src/ChainlinkOracleAdapter.sol";
import {MockAggregator} from "../../src/mocks/MockAggregator.sol";

contract MockInvariantVaultAsset is ERC20 {
    constructor() ERC20("Invariant Vault Asset", "iVA") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract RWAVaultHandler is Test {
    RWAVault internal vault;
    MockInvariantVaultAsset internal asset;

    address[] internal actors;
    address internal yieldManager;

    uint256 public ghostAssetsIn;
    uint256 public ghostAssetsOut;
    uint256 public ghostCollectedYield;

    uint256 internal constant MIN_ACTION_AMOUNT = 1 ether;
    uint256 internal constant MAX_ACTION_AMOUNT = 100_000 ether;

    constructor(
        RWAVault vault_,
        MockInvariantVaultAsset asset_,
        address[] memory actors_,
        address yieldManager_
    ) {
        vault = vault_;
        asset = asset_;
        actors = actors_;
        yieldManager = yieldManager_;
    }

    function deposit(
        uint256 actorSeed,
        uint96 rawAssets
    ) external {
        address actor = actors[actorSeed % actors.length];
        uint256 actorBalance = asset.balanceOf(actor);

        if (actorBalance < MIN_ACTION_AMOUNT) {
            return;
        }

        uint256 assets = bound(
            uint256(rawAssets),
            MIN_ACTION_AMOUNT,
            _min(actorBalance, MAX_ACTION_AMOUNT)
        );

        vm.prank(actor);
        try vault.deposit(assets, actor) {
            ghostAssetsIn += assets;
        } catch {
            // Ignore invalid randomized states.
        }
    }

    function mintShares(
        uint256 actorSeed,
        uint96 rawShares
    ) external {
        address actor = actors[actorSeed % actors.length];
        uint256 actorBalance = asset.balanceOf(actor);

        if (actorBalance < MIN_ACTION_AMOUNT) {
            return;
        }

        uint256 shares = bound(
            uint256(rawShares),
            MIN_ACTION_AMOUNT,
            MAX_ACTION_AMOUNT
        );

        vm.prank(actor);
        try vault.mint(shares, actor) returns (uint256 assetsSpent) {
            ghostAssetsIn += assetsSpent;
        } catch {
            // Can revert if randomized mint requires more assets than actor owns.
        }
    }

    function withdraw(
        uint256 actorSeed,
        uint96 rawAssets
    ) external {
        address actor = actors[actorSeed % actors.length];
        uint256 maxWithdrawable = vault.maxWithdraw(actor);

        if (maxWithdrawable == 0) {
            return;
        }

        uint256 assets = bound(
            uint256(rawAssets),
            1,
            _min(maxWithdrawable, MAX_ACTION_AMOUNT)
        );

        vm.prank(actor);
        try vault.withdraw(assets, actor, actor) {
            ghostAssetsOut += assets;
        } catch {
            // Current vault accounting can make some randomized withdrawals invalid.
        }
    }

    function redeem(
        uint256 actorSeed,
        uint96 rawShares
    ) external {
        address actor = actors[actorSeed % actors.length];
        uint256 actorShares = vault.balanceOf(actor);

        if (actorShares == 0) {
            return;
        }

        uint256 shares = bound(
            uint256(rawShares),
            1,
            _min(actorShares, MAX_ACTION_AMOUNT)
        );

        vm.prank(actor);
        try vault.redeem(shares, actor, actor) returns (uint256 assetsReturned) {
            ghostAssetsOut += assetsReturned;
        } catch {
            // Some randomized redemptions may be impossible under current share price.
        }
    }

    function collectYield(
        uint96 rawAmount
    ) external {
        uint256 managerBalance = asset.balanceOf(yieldManager);

        if (managerBalance < MIN_ACTION_AMOUNT) {
            return;
        }

        uint256 amount = bound(
            uint256(rawAmount),
            MIN_ACTION_AMOUNT,
            _min(managerBalance, MAX_ACTION_AMOUNT)
        );

        vm.prank(yieldManager);
        try vault.collectYield(amount) {
            ghostAssetsIn += amount;
            ghostCollectedYield += amount;
        } catch {
            // Ignore randomized invalid states.
        }
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}

contract RWAVaultInvariantTest is StdInvariant, Test {
    RWAVault internal implementation;
    RWAVault internal vault;
    ERC1967Proxy internal proxy;

    MockInvariantVaultAsset internal asset;

    ChainlinkOracleAdapter internal oracle;
    MockAggregator internal mockFeed;

    RWAVaultHandler internal handler;

    address internal admin = makeAddr("admin");
    address internal yieldManager = makeAddr("yieldManager");
    address internal oracleOwner = makeAddr("oracleOwner");

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol");

    bytes32 internal constant ASSET_ID =
        keccak256("INVARIANT_VAULT_ASSET_001");

    uint96 internal constant MAX_STALENESS = 1 days;
    uint256 internal constant STARTING_BALANCE = 1_000_000_000_000 ether;

    function setUp() public {
        vm.warp(1_700_000_000);

        asset = new MockInvariantVaultAsset();

        oracle = new ChainlinkOracleAdapter(oracleOwner);
        mockFeed = new MockAggregator(int256(2_000e8), 8);

        vm.prank(oracleOwner);
        oracle.addFeed(ASSET_ID, address(mockFeed), MAX_STALENESS);

        implementation = new RWAVault();

        bytes memory initData = abi.encodeCall(
            RWAVault.initialize,
            (
                address(asset),
                "Invariant Vault Share",
                "iVSHARE",
                address(oracle),
                ASSET_ID,
                0, // uncapped for invariant state exploration
                admin
            )
        );

        proxy = new ERC1967Proxy(address(implementation), initData);
        vault = RWAVault(address(proxy));

        vm.startPrank(admin);
        vault.grantRole(vault.YIELD_MANAGER_ROLE(), yieldManager);
        vm.stopPrank();

        address[] memory actors = new address[](3);
        actors[0] = alice;
        actors[1] = bob;
        actors[2] = carol;

        for (uint256 i = 0; i < actors.length; i++) {
            asset.mint(actors[i], STARTING_BALANCE);

            vm.prank(actors[i]);
            asset.approve(address(vault), type(uint256).max);
        }

        asset.mint(yieldManager, STARTING_BALANCE);

        vm.prank(yieldManager);
        asset.approve(address(vault), type(uint256).max);

        handler = new RWAVaultHandler(
            vault,
            asset,
            actors,
            yieldManager
        );

        targetContract(address(handler));
    }

    function invariant_PhysicalTreasuryBalanceMatchesTrackedInflowsMinusOutflows() public view {
        uint256 totalIn = handler.ghostAssetsIn();
        uint256 totalOut = handler.ghostAssetsOut();

        assertGe(totalIn, totalOut);

        uint256 expectedPhysicalBalance = totalIn - totalOut;

        assertEq(
            asset.balanceOf(address(vault)),
            expectedPhysicalBalance
        );
    }

    function invariant_TotalShareSupplyEqualsAllActorShareBalances() public view {
        uint256 actorShareTotal =
            vault.balanceOf(alice) +
            vault.balanceOf(bob) +
            vault.balanceOf(carol);

        assertEq(
            vault.totalSupply(),
            actorShareTotal
        );
    }

    function invariant_ReportedTotalAssetsMatchesCurrentVaultAccountingModel() public view {
        uint256 expectedReportedAssets =
            asset.balanceOf(address(vault)) +
            handler.ghostCollectedYield();

        assertEq(
            vault.totalAssets(),
            expectedReportedAssets
        );
    }

    function invariant_TotalAssetsNeverBelowPhysicalUnderlyingTreasury() public view {
        assertGe(
            vault.totalAssets(),
            asset.balanceOf(address(vault))
        );
    }
}
