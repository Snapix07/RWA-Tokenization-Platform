// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {RWAVault} from "../../src/RWAVault.sol";
import {ChainlinkOracleAdapter} from "../../src/ChainlinkOracleAdapter.sol";
import {MockAggregator} from "../../src/mocks/MockAggregator.sol";

import {
    DepositCapExceeded,
    ZeroAddress,
    ZeroAmount
} from "../../src/interfaces/IRWATypes.sol";

contract MockVaultAsset is ERC20 {
    constructor() ERC20("Mock RWA Asset", "mRWA") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract RWAVaultTest is Test {
    RWAVault internal implementation;
    RWAVault internal vault;
    ERC1967Proxy internal proxy;

    MockVaultAsset internal asset;

    ChainlinkOracleAdapter internal oracle;
    MockAggregator internal mockFeed;

    address internal admin = makeAddr("admin");
    address internal yieldManager = makeAddr("yieldManager");
    address internal pauser = makeAddr("pauser");
    address internal upgrader = makeAddr("upgrader");
    address internal oracleOwner = makeAddr("oracleOwner");

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal attacker = makeAddr("attacker");

    bytes32 internal constant ASSET_ID = keccak256("VAULT_RWA_ASSET_001");

    uint96 internal constant MAX_STALENESS = 1 days;
    uint256 internal constant DEPOSIT_CAP = 1_000_000 ether;
    uint256 internal constant ALICE_INITIAL_ASSETS = 100_000 ether;
    uint256 internal constant BOB_INITIAL_ASSETS = 100_000 ether;
    uint256 internal constant YIELD_AMOUNT = 10_000 ether;

    event YieldCollected(address indexed manager, uint256 amount);
    event DepositCapUpdated(uint256 newCap);

    function setUp() public {
        vm.warp(1_700_000_000);

        asset = new MockVaultAsset();

        oracle = new ChainlinkOracleAdapter(oracleOwner);
        mockFeed = new MockAggregator(int256(2_000e8), 8);

        vm.prank(oracleOwner);
        oracle.addFeed(ASSET_ID, address(mockFeed), MAX_STALENESS);

        implementation = new RWAVault();

        bytes memory initData = abi.encodeCall(
            RWAVault.initialize,
            (
                address(asset),
                "RWA Yield Vault Share",
                "rwYIELD",
                address(oracle),
                ASSET_ID,
                DEPOSIT_CAP,
                admin
            )
        );

        proxy = new ERC1967Proxy(address(implementation), initData);
        vault = RWAVault(address(proxy));

        vm.startPrank(admin);
        vault.grantRole(vault.YIELD_MANAGER_ROLE(), yieldManager);
        vault.grantRole(vault.PAUSER_ROLE(), pauser);
        vault.grantRole(vault.UPGRADER_ROLE(), upgrader);
        vm.stopPrank();

        asset.mint(alice, ALICE_INITIAL_ASSETS);
        asset.mint(bob, BOB_INITIAL_ASSETS);
        asset.mint(yieldManager, YIELD_AMOUNT);

        vm.prank(alice);
        asset.approve(address(vault), type(uint256).max);

        vm.prank(bob);
        asset.approve(address(vault), type(uint256).max);

        vm.prank(yieldManager);
        asset.approve(address(vault), type(uint256).max);
    }

    function _depositFromAlice(uint256 amount) internal returns (uint256 shares) {
        vm.prank(alice);
        shares = vault.deposit(amount, alice);
    }

    function test_Initialize_SetsMetadataAssetAndRoles() public view {
        assertEq(vault.name(), "RWA Yield Vault Share");
        assertEq(vault.symbol(), "rwYIELD");
        assertEq(vault.asset(), address(asset));

        assertTrue(vault.hasRole(vault.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(vault.hasRole(vault.YIELD_MANAGER_ROLE(), admin));
        assertTrue(vault.hasRole(vault.PAUSER_ROLE(), admin));
        assertTrue(vault.hasRole(vault.UPGRADER_ROLE(), admin));
    }

    function test_Initialize_RevertsWhenCalledTwiceThroughProxy() public {
        vm.expectRevert();

        vault.initialize(
            address(asset),
            "Second Vault",
            "SECOND",
            address(oracle),
            ASSET_ID,
            DEPOSIT_CAP,
            admin
        );
    }

    function test_Initialize_RevertsWhenAssetIsZeroAddress() public {
        RWAVault freshImplementation = new RWAVault();

        bytes memory initData = abi.encodeCall(
            RWAVault.initialize,
            (
                address(0),
                "Broken Vault",
                "BROKEN",
                address(oracle),
                ASSET_ID,
                DEPOSIT_CAP,
                admin
            )
        );

        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector));
        new ERC1967Proxy(address(freshImplementation), initData);
    }

    function test_Initialize_RevertsWhenAdminIsZeroAddress() public {
        RWAVault freshImplementation = new RWAVault();

        bytes memory initData = abi.encodeCall(
            RWAVault.initialize,
            (
                address(asset),
                "Broken Vault",
                "BROKEN",
                address(oracle),
                ASSET_ID,
                DEPOSIT_CAP,
                address(0)
            )
        );

        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector));
        new ERC1967Proxy(address(freshImplementation), initData);
    }

    function test_TotalAssets_IsZeroBeforeDeposits() public view {
        assertEq(vault.totalAssets(), 0);
    }

    function test_Deposit_MintsSharesAndTransfersAssets() public {
        uint256 amount = 1_000 ether;

        uint256 shares = _depositFromAlice(amount);

        assertEq(shares, amount);
        assertEq(vault.balanceOf(alice), amount);
        assertEq(vault.totalSupply(), amount);
        assertEq(asset.balanceOf(address(vault)), amount);
        assertEq(vault.totalAssets(), amount);
    }

    function test_Deposit_RevertsWhenAssetsAreZero() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(ZeroAmount.selector));

        vault.deposit(0, alice);
    }

    function test_Mint_MintsRequestedSharesAndPullsAssets() public {
        uint256 sharesRequested = 500 ether;

        vm.prank(alice);
        uint256 assetsSpent = vault.mint(sharesRequested, alice);

        assertEq(assetsSpent, sharesRequested);
        assertEq(vault.balanceOf(alice), sharesRequested);
        assertEq(vault.totalSupply(), sharesRequested);
        assertEq(asset.balanceOf(address(vault)), sharesRequested);
    }

    function test_Mint_RevertsWhenZeroSharesProduceZeroAssets() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(ZeroAmount.selector));

        vault.mint(0, alice);
    }

    function test_Deposit_MultipleUsersReceiveShares() public {
        vm.prank(alice);
        vault.deposit(1_000 ether, alice);

        vm.prank(bob);
        vault.deposit(500 ether, bob);

        assertEq(vault.balanceOf(alice), 1_000 ether);
        assertEq(vault.balanceOf(bob), 500 ether);
        assertEq(vault.totalSupply(), 1_500 ether);
        assertEq(vault.totalAssets(), 1_500 ether);
    }

    function test_Deposit_AllowsAmountExactlyAtDepositCap() public {
        asset.mint(alice, DEPOSIT_CAP);

        vm.prank(alice);
        vault.deposit(DEPOSIT_CAP, alice);

        assertEq(vault.totalAssets(), DEPOSIT_CAP);
    }

    function test_Deposit_RevertsWhenDepositCapWouldBeExceeded() public {
        // Top up balances so the revert comes from the vault cap,
        // not from insufficient ERC20 balance.
        asset.mint(alice, 800_000 ether);
        asset.mint(bob, 100_000 ether);

        vm.prank(alice);
        vault.deposit(900_000 ether, alice);

        vm.prank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(
                DepositCapExceeded.selector,
                200_000 ether,
                100_000 ether
            )
        );

        vault.deposit(200_000 ether, bob);
    }

    function test_SetDepositCap_AdminCanRaiseCap() public {
        uint256 newCap = 2_000_000 ether;

        vm.expectEmit(false, false, false, true, address(vault));
        emit DepositCapUpdated(newCap);

        vm.prank(admin);
        vault.setDepositCap(newCap);

        asset.mint(alice, 1_500_000 ether);

        vm.prank(alice);
        vault.deposit(1_500_000 ether, alice);

        assertTrue(vault.totalAssets() >= 1_500_000 ether);
    }

    function test_SetDepositCap_AdminCanDisableCapWithZero() public {
        vm.prank(admin);
        vault.setDepositCap(0);

        asset.mint(alice, 2_000_000 ether);

        vm.prank(alice);
        vault.deposit(2_000_000 ether, alice);

        assertTrue(vault.totalAssets() >= 2_000_000 ether);
    }

    function test_SetDepositCap_RevertsWhenCallerIsNotAdmin() public {
        vm.prank(attacker);
        vm.expectRevert();

        vault.setDepositCap(2_000_000 ether);
    }

    function test_Withdraw_BurnsSharesAndTransfersAssets() public {
        _depositFromAlice(1_000 ether);

        uint256 aliceAssetsBefore = asset.balanceOf(alice);

        vm.prank(alice);
        uint256 sharesBurned = vault.withdraw(400 ether, alice, alice);

        assertEq(sharesBurned, 400 ether);
        assertEq(vault.balanceOf(alice), 600 ether);
        assertEq(asset.balanceOf(alice), aliceAssetsBefore + 400 ether);
    }

    function test_Redeem_BurnsSharesAndReturnsAssets() public {
        _depositFromAlice(1_000 ether);

        uint256 aliceAssetsBefore = asset.balanceOf(alice);

        vm.prank(alice);
        uint256 assetsReturned = vault.redeem(250 ether, alice, alice);

        assertEq(assetsReturned, 250 ether);
        assertEq(vault.balanceOf(alice), 750 ether);
        assertEq(asset.balanceOf(alice), aliceAssetsBefore + 250 ether);
    }

    function test_Withdraw_RevertsWhenOwnerHasInsufficientShares() public {
        _depositFromAlice(100 ether);

        vm.prank(alice);
        vm.expectRevert();

        vault.withdraw(101 ether, alice, alice);
    }

    function test_Redeem_RevertsWhenOwnerHasInsufficientShares() public {
        _depositFromAlice(100 ether);

        vm.prank(alice);
        vm.expectRevert();

        vault.redeem(101 ether, alice, alice);
    }

    function test_PauseAndUnpause_PauserControlsVaultState() public {
        assertFalse(vault.paused());

        vm.prank(pauser);
        vault.pause();

        assertTrue(vault.paused());

        vm.prank(pauser);
        vault.unpause();

        assertFalse(vault.paused());
    }

    function test_Pause_RevertsWhenCallerLacksPauserRole() public {
        vm.prank(attacker);
        vm.expectRevert();

        vault.pause();
    }

    function test_Unpause_RevertsWhenCallerLacksPauserRole() public {
        vm.prank(pauser);
        vault.pause();

        vm.prank(attacker);
        vm.expectRevert();

        vault.unpause();
    }

    function test_Deposit_RevertsWhenVaultIsPaused() public {
        vm.prank(pauser);
        vault.pause();

        vm.prank(alice);
        vm.expectRevert();

        vault.deposit(1_000 ether, alice);
    }

    function test_Withdraw_RevertsWhenVaultIsPaused() public {
        _depositFromAlice(1_000 ether);

        vm.prank(pauser);
        vault.pause();

        vm.prank(alice);
        vm.expectRevert();

        vault.withdraw(100 ether, alice, alice);
    }

    function test_Redeem_RevertsWhenVaultIsPaused() public {
        _depositFromAlice(1_000 ether);

        vm.prank(pauser);
        vault.pause();

        vm.prank(alice);
        vm.expectRevert();

        vault.redeem(100 ether, alice, alice);
    }

    function test_CollectYield_YieldManagerCanInjectYield() public {
        _depositFromAlice(10_000 ether);

        uint256 assetsBefore = vault.totalAssets();

        vm.expectEmit(true, false, false, true, address(vault));
        emit YieldCollected(yieldManager, YIELD_AMOUNT);

        vm.prank(yieldManager);
        vault.collectYield(YIELD_AMOUNT);

        assertTrue(vault.totalAssets() > assetsBefore);
        assertEq(asset.balanceOf(address(vault)), 20_000 ether);
    }

    function test_CollectYield_RevertsWhenCallerLacksYieldManagerRole() public {
        vm.prank(attacker);
        vm.expectRevert();

        vault.collectYield(1_000 ether);
    }

    function test_CollectYield_RevertsWhenAmountIsZero() public {
        vm.prank(yieldManager);
        vm.expectRevert(abi.encodeWithSelector(ZeroAmount.selector));

        vault.collectYield(0);
    }

    function test_CollectYield_IncreasesShareValueRelativeToInitialDeposit() public {
        _depositFromAlice(10_000 ether);

        uint256 assetsPerOneShareBefore = vault.previewRedeem(1 ether);

        vm.prank(yieldManager);
        vault.collectYield(YIELD_AMOUNT);

        uint256 assetsPerOneShareAfter = vault.previewRedeem(1 ether);

        assertGt(assetsPerOneShareAfter, assetsPerOneShareBefore);
    }


    function test_NavPerShare_ReturnsOraclePriceWhenVaultHasNoShares() public view {
        uint256 nav = vault.navPerShare();

        assertEq(nav, 2_000 ether);
    }

    function test_NavPerShare_EqualsOraclePriceBeforeYield() public {
        _depositFromAlice(10_000 ether);

        uint256 nav = vault.navPerShare();

        assertEq(nav, 2_000 ether);
    }

    function test_NavPerShare_IncreasesAfterYieldCollection() public {
        _depositFromAlice(10_000 ether);

        uint256 navBefore = vault.navPerShare();

        vm.prank(yieldManager);
        vault.collectYield(YIELD_AMOUNT);

        uint256 navAfter = vault.navPerShare();

        assertGt(navAfter, navBefore);
    }

    function test_UpgradeToAndCall_RevertsWhenCallerLacksUpgraderRole() public {
        RWAVault newImplementation = new RWAVault();

        vm.prank(attacker);
        vm.expectRevert();

        vault.upgradeToAndCall(address(newImplementation), "");
    }

    function test_UpgradeToAndCall_UpgraderCanUpgradeVaultImplementation() public {
        RWAVault newImplementation = new RWAVault();

        vm.prank(upgrader);
        vault.upgradeToAndCall(address(newImplementation), "");

        assertEq(vault.asset(), address(asset));
        assertTrue(vault.hasRole(vault.UPGRADER_ROLE(), upgrader));
    }
}
