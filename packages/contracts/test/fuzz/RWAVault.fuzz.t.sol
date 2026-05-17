// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {RWAVault} from "../../src/RWAVault.sol";
import {ChainlinkOracleAdapter} from "../../src/ChainlinkOracleAdapter.sol";
import {MockAggregator} from "../../src/mocks/MockAggregator.sol";

import {DepositCapExceeded} from "../../src/interfaces/IRWATypes.sol";

contract MockVaultFuzzAsset is ERC20 {
    constructor() ERC20("Mock Vault Fuzz Asset", "mVFA") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract RWAVaultFuzzTest is Test {
    RWAVault internal implementation;
    RWAVault internal vault;
    ERC1967Proxy internal proxy;

    MockVaultFuzzAsset internal asset;

    ChainlinkOracleAdapter internal oracle;
    MockAggregator internal mockFeed;

    address internal admin = makeAddr("admin");
    address internal oracleOwner = makeAddr("oracleOwner");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    bytes32 internal constant ASSET_ID = keccak256("FUZZ_VAULT_ASSET_001");

    uint96 internal constant MAX_STALENESS = 1 days;
    uint256 internal constant DEFAULT_DEPOSIT_CAP = 1_000_000 ether;
    uint256 internal constant USER_BALANCE = 10_000_000 ether;

    function setUp() public {
        vm.warp(1_700_000_000);

        asset = new MockVaultFuzzAsset();

        oracle = new ChainlinkOracleAdapter(oracleOwner);
        mockFeed = new MockAggregator(int256(2_000e8), 8);

        vm.prank(oracleOwner);
        oracle.addFeed(ASSET_ID, address(mockFeed), MAX_STALENESS);

        implementation = new RWAVault();

        bytes memory initData = abi.encodeCall(
            RWAVault.initialize,
            (
                address(asset),
                "Fuzz RWA Vault Share",
                "fRWA",
                address(oracle),
                ASSET_ID,
                DEFAULT_DEPOSIT_CAP,
                admin
            )
        );

        proxy = new ERC1967Proxy(address(implementation), initData);
        vault = RWAVault(address(proxy));

        asset.mint(alice, USER_BALANCE);
        asset.mint(bob, USER_BALANCE);

        vm.prank(alice);
        asset.approve(address(vault), type(uint256).max);

        vm.prank(bob);
        asset.approve(address(vault), type(uint256).max);
    }

    function testFuzz_Deposit_MintsOneToOneSharesBeforeYield(uint96 rawAssets) public {
        uint256 assets = bound(
            uint256(rawAssets),
            1,
            100_000 ether
        );

        vm.prank(alice);
        uint256 shares = vault.deposit(assets, alice);

        assertEq(shares, assets);
        assertEq(vault.balanceOf(alice), assets);
        assertEq(vault.totalSupply(), assets);
        assertEq(vault.totalAssets(), assets);
    }

    function testFuzz_MultipleDeposits_NoYieldKeepsAssetsEqualToShares(
        uint96 rawAliceAssets,
        uint96 rawBobAssets
    ) public {
        uint256 aliceAssets = bound(
            uint256(rawAliceAssets),
            1,
            100_000 ether
        );

        uint256 bobAssets = bound(
            uint256(rawBobAssets),
            1,
            100_000 ether
        );

        vm.prank(alice);
        vault.deposit(aliceAssets, alice);

        vm.prank(bob);
        vault.deposit(bobAssets, bob);

        uint256 totalDeposited = aliceAssets + bobAssets;

        assertEq(vault.balanceOf(alice), aliceAssets);
        assertEq(vault.balanceOf(bob), bobAssets);
        assertEq(vault.totalSupply(), totalDeposited);
        assertEq(vault.totalAssets(), totalDeposited);
    }

    function testFuzz_Withdraw_AfterDepositReturnsRequestedAssets(
        uint96 rawDeposit,
        uint96 rawWithdraw
    ) public {
        uint256 depositAmount = bound(
            uint256(rawDeposit),
            1 ether,
            100_000 ether
        );

        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        uint256 withdrawAmount = bound(
            uint256(rawWithdraw),
            1,
            depositAmount
        );

        uint256 aliceAssetsBefore = asset.balanceOf(alice);

        vm.prank(alice);
        uint256 sharesBurned = vault.withdraw(
            withdrawAmount,
            alice,
            alice
        );

        assertEq(sharesBurned, withdrawAmount);
        assertEq(
            asset.balanceOf(alice),
            aliceAssetsBefore + withdrawAmount
        );
        assertEq(
            vault.balanceOf(alice),
            depositAmount - withdrawAmount
        );
    }

    function testFuzz_Redeem_AfterDepositReturnsMatchingAssets(
        uint96 rawDeposit,
        uint96 rawShares
    ) public {
        uint256 depositAmount = bound(
            uint256(rawDeposit),
            1 ether,
            100_000 ether
        );

        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        uint256 sharesToRedeem = bound(
            uint256(rawShares),
            1,
            depositAmount
        );

        uint256 aliceAssetsBefore = asset.balanceOf(alice);

        vm.prank(alice);
        uint256 assetsReturned = vault.redeem(
            sharesToRedeem,
            alice,
            alice
        );

        assertEq(assetsReturned, sharesToRedeem);
        assertEq(
            asset.balanceOf(alice),
            aliceAssetsBefore + sharesToRedeem
        );
        assertEq(
            vault.balanceOf(alice),
            depositAmount - sharesToRedeem
        );
    }

    function testFuzz_DepositCap_RevertsAfterCapIsFilled(uint96 rawCap) public {
        uint256 cap = bound(
            uint256(rawCap),
            1 ether,
            100_000 ether
        );

        vm.prank(admin);
        vault.setDepositCap(cap);

        vm.prank(alice);
        vault.deposit(cap, alice);

        vm.prank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(
                DepositCapExceeded.selector,
                1,
                0
            )
        );

        vault.deposit(1, bob);
    }
}
