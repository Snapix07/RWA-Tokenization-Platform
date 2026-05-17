# RWA Tokenization Platform

A production-grade decentralized protocol for tokenizing real-world assets (RWA) on **Arbitrum Sepolia**. Blockchain Technologies 2 final project — Option C.

| Package                                    | Description                        |
| ------------------------------------------ | ---------------------------------- |
| [`packages/contracts`](packages/contracts) | Solidity smart contracts (Foundry) |
| [`packages/subgraph`](packages/subgraph)   | The Graph subgraph                 |
| [`packages/frontend`](packages/frontend)   | React + Vite dApp                  |

---

## Architecture

```
  Issuer / User
      │
      ▼
 AssetFactory ──CREATE2──► AssetTokenV1 (UUPS proxy)
      │                         │
      │                    ChainlinkOracleAdapter
      │                         │ (staleness check, Yul benchmark)
      ▼                         ▼
  RWAVault (ERC-4626, UUPS) ◄── oracle price
      │
      ├── RWAAMM  (x·y=k, 0.3% fee, LP tokens)
      │
  GovernanceToken (ERC20Votes + ERC20Permit)
      │
  RWAGovernor ──► RWATimelockController (2-day delay)
                        │
                  controls upgrades, oracle feeds, parameters
```

---

## Deployed Contracts — Arbitrum Sepolia (chain 421614)

All contracts deployed and verified at commit `feature/contracts` · [broadcast log](packages/contracts/broadcast/Deploy.s.sol/421614/run-latest.json)

| Contract                   | Address                                      | Explorer                                                                                   |
| -------------------------- | -------------------------------------------- | ------------------------------------------------------------------------------------------ |
| GovernanceToken            | `0x57B0e45C40CCE6248a102Cdf8612Cdc683Cf3Fd9` | [arbiscan](https://sepolia.arbiscan.io/address/0x57B0e45C40CCE6248a102Cdf8612Cdc683Cf3Fd9) |
| ChainlinkOracleAdapter     | `0x213B4519E7a59Bd2BEEDde148B8b6fFFCE5dEB53` | [arbiscan](https://sepolia.arbiscan.io/address/0x213B4519E7a59Bd2BEEDde148B8b6fFFCE5dEB53) |
| AssetNFT                   | `0x88AbE0eB4Beb185c3e63BCD58892758C9f0ac3D6` | [arbiscan](https://sepolia.arbiscan.io/address/0x88AbE0eB4Beb185c3e63BCD58892758C9f0ac3D6) |
| AssetTokenV1 (impl)        | `0x337D60f8be5E65dce632E4f2794b58EA7416AC0e` | [arbiscan](https://sepolia.arbiscan.io/address/0x337D60f8be5E65dce632E4f2794b58EA7416AC0e) |
| AssetTokenV2 (impl)        | `0xc91C9F525E6A7B7f19Ac9ade118a97929f3A57aB` | [arbiscan](https://sepolia.arbiscan.io/address/0xc91C9F525E6A7B7f19Ac9ade118a97929f3A57aB) |
| AssetFactory               | `0x0d41539C9B43cd675dEBBC3dB8754e26ec274eDF` | [arbiscan](https://sepolia.arbiscan.io/address/0x0d41539C9B43cd675dEBBC3dB8754e26ec274eDF) |
| AssetToken ETHBOND (proxy) | `0xBE60c53E15328b18E82E7204fbECA45e11628caa` | [arbiscan](https://sepolia.arbiscan.io/address/0xBE60c53E15328b18E82E7204fbECA45e11628caa) |
| RWAVault (impl)            | `0x3AF9B9bf4DF2f4dDFE3F07e5f971528D6EdcCbF3` | [arbiscan](https://sepolia.arbiscan.io/address/0x3AF9B9bf4DF2f4dDFE3F07e5f971528D6EdcCbF3) |
| RWAVault (proxy)           | `0xFbECEB9447925e0c2e433f5eD674F7110AF67018` | [arbiscan](https://sepolia.arbiscan.io/address/0xFbECEB9447925e0c2e433f5eD674F7110AF67018) |
| RWAAMM                     | `0x658eD17F2686A652ACC89162c7aA99b957e7938E` | [arbiscan](https://sepolia.arbiscan.io/address/0x658eD17F2686A652ACC89162c7aA99b957e7938E) |
| RWATimelockController      | `0x1C9e29A66561B1533578cFc27AB0A4cB7F740c8e` | [arbiscan](https://sepolia.arbiscan.io/address/0x1C9e29A66561B1533578cFc27AB0A4cB7F740c8e) |
| RWAGovernor                | `0x091858adb6f82c323c4B4d1b0aA59Cec953B9E75` | [arbiscan](https://sepolia.arbiscan.io/address/0x091858adb6f82c323c4B4d1b0aA59Cec953B9E75) |

---

## Smart Contracts

| Contract                 | Purpose                                                    | Patterns                   |
| ------------------------ | ---------------------------------------------------------- | -------------------------- |
| `GovernanceToken`        | ERC20Votes + ERC20Permit DAO token                         | AccessControl              |
| `AssetNFT`               | ERC-721 legal certificate per onboarded asset              | AccessControl, Pausable    |
| `AssetTokenV1`           | RWA-backed ERC-20, UUPS V1                                 | UUPS, CEI, ReentrancyGuard |
| `AssetTokenV2`           | UUPS V2 — adds KYC whitelist + mint fee                    | UUPS upgrade               |
| `AssetFactory`           | Deploys token proxies via CREATE and CREATE2               | Factory, AccessControl     |
| `ChainlinkOracleAdapter` | Chainlink wrapper with staleness check + Yul gas benchmark | OracleAdapter, Pausable    |
| `RWAVault`               | ERC-4626 yield vault, UUPS                                 | UUPS, CEI, ReentrancyGuard |
| `RWAAMM`                 | x·y=k AMM, 0.3% fee, LP tokens, built from scratch         | CEI, ReentrancyGuard       |
| `RWATimelockController`  | 2-day governance timelock                                  | Timelock                   |
| `RWAGovernor`            | DAO: 4% quorum, 1% threshold, 1-day delay/1-week period    | Timelock                   |

---

## Subgraph

Subgraph Studio slug: `rwa-tokenization-platform` — network: `arbitrum-sepolia`

**4 entities:** `AssetToken`, `VaultPosition`, `AmmSwap`, `GovernanceProposal` / `ProposalVote`

### 5 Documented GraphQL Queries

**Q1 — All deployed asset tokens**

```graphql
{
  assetTokens(orderBy: deployedAt, orderDirection: desc) {
    id
    assetId
    deterministic
    deployedAt
  }
}
```

**Q2 — Vault positions for a user**

```graphql
query UserPositions($user: String!) {
  vaultPositions(where: { user: $user }) {
    vault
    totalDeposited
    totalWithdrawn
    sharesBalance
  }
}
```

**Q3 — Recent AMM swaps**

```graphql
{
  ammSwaps(first: 20, orderBy: timestamp, orderDirection: desc) {
    sender
    tokenIn
    amountIn
    amountOut
    timestamp
  }
}
```

**Q4 — Active governance proposals**

```graphql
{
  governanceProposals(where: { state: 1 }) {
    proposalId
    proposer
    description
    forVotes
    againstVotes
    abstainVotes
    voteEnd
  }
}
```

**Q5 — All votes on a proposal**

```graphql
query Votes($id: String!) {
  governanceProposal(id: $id) {
    forVotes
    againstVotes
    votes {
      voter
      support
      weight
    }
  }
}
```

---

## Governance Parameters

| Parameter          | Value                                         |
| ------------------ | --------------------------------------------- |
| Voting delay       | 43 200 blocks (~1 day at Arbitrum ~2 s/block) |
| Voting period      | 302 400 blocks (~1 week)                      |
| Quorum             | 4% of total supply at snapshot block          |
| Proposal threshold | 1% of current total supply (dynamic)          |
| Timelock min delay | 2 days                                        |

---

## Development Setup

```bash
git clone https://github.com/Snapix07/RWA-Tokenization-Platform.git
cd RWA-Tokenization-Platform
npm ci                                   # install JS tools
cd packages/contracts && forge install   # install Foundry deps
forge build                              # compile contracts
```

---

## Testing

```bash
cd packages/contracts

forge test -vvv                                        # all tests
forge test --match-path "test/security/*" -vv          # security case studies
forge coverage --report markdown > coverage-report.md  # coverage
```

---

## Deployment

```bash
cp .env.example .env   # fill PRIVATE_KEY, ARB_SEPOLIA_RPC_URL, ARBISCAN_API_KEY

cd packages/contracts
forge script script/Deploy.s.sol --rpc-url arb_sepolia --broadcast --verify -vvvv

# Re-verify if Etherscan V2 fails (keyless fallback)
forge script script/Deploy.s.sol --rpc-url arb_sepolia --verify --verifier sourcify --resume

# Post-deployment wiring check
export TIMELOCK_ADDRESS=0x1C9e29A66561B1533578cFc27AB0A4cB7F740c8e
export GOVERNOR_ADDRESS=0x091858adb6f82c323c4B4d1b0aA59Cec953B9E75
export VAULT_ADDRESS=0xFbECEB9447925e0c2e433f5eD674F7110AF67018
export ASSET_TOKEN_ADDRESS=0xBE60c53E15328b18E82E7204fbECA45e11628caa
export ORACLE_ADDRESS=0x213B4519E7a59Bd2BEEDde148B8b6fFFCE5dEB53
export DEPLOYER_ADDRESS=0x86A5A05aC0cAb580d3f0082A70E3f65281aABAf0
forge script script/VerifyDeployment.s.sol --rpc-url arb_sepolia
```

Expected verification output:

```
[PASS] Timelock min delay >= 2 days
[PASS] Deployer has renounced TIMELOCK_ADMIN_ROLE
[PASS] Governor holds PROPOSER_ROLE on Timelock
...
ALL CHECKS PASSED -- deployment is correctly wired.
```

---

## Documentation

- **[Architecture & Design Document](./docs/ARCHITECTURE_DOCUMENT.md)** — 6+ pages
  - System architecture diagrams (C4 Level 1, 2)
  - Contract relationships & data flows
  - Storage layout analysis (UUPS upgrade safety)
  - Design decisions & ADRs

- **[Security Audit Report](./docs/SECURITY_AUDIT_REPORT.md)** — 8+ pages
  - Findings summary: 0 High, 0 Medium, 2 Low
  - Vulnerability case studies (S-01: Reentrancy, S-02: Access Control)
  - Governance & oracle attack analysis
  - Centralization analysis

- **[Gas Optimization Report](./docs/GAS_OPTIMIZATION_REPORT.md)** — 3-4 pages
  - L1 vs L2 cost comparison (90% savings on Arbitrum)
  - 6 operation benchmarks with detailed analysis
  - Optimization techniques applied

- **[Test Coverage Report](./coverage.md)** — 92% line coverage
  - 82 tests (55 unit, 12 fuzz, 8 invariant, 7 fork)
  - Coverage breakdown by contract

## Testing & Verification

```bash
# Run full test suite
forge test -vvv

# Generate coverage report
forge coverage --report markdown > coverage.md

# Static analysis (Slither)
slither src --json > slither-report.json

# Gas report
forge test --gas-report

# Verify deployment
export TIMELOCK_ADDRESS=0x1C9e29A66561B1533578cFc27AB0A4cB7F740c8e
export GOVERNOR_ADDRESS=0x091858adb6f82c323c4B4d1b0aA59Cec953B9E75
forge script script/VerifyDeployment.s.sol --rpc-url arb_sepolia
```

## Security

**Design patterns used:** Factory, Proxy/UUPS, CEI, AccessControl, Pausable, OracleAdapter, Timelock, ReentrancyGuard

**Vulnerability case studies:**

- **S-01 Reentrancy** (`test/security/ReentrancyAttack.t.sol`) — attacker drains 5× deposit from vault missing CEI. Fixed: `ReentrancyGuard` + effects-before-interactions.
- **S-02 Access Control** (`test/security/AccessControlAttack.t.sol`) — any address deploys tokens on unguarded factory. Fixed: `FACTORY_ROLE` on `AssetFactory.deployAssetToken`.

---

## CI/CD

GitHub Actions on every push and PR:

| Job              | Steps                                                  |
| ---------------- | ------------------------------------------------------ |
| **Lint**         | `prettier --check`, `forge fmt --check`, `solhint`     |
| **Build & Test** | `forge build`, `forge test -vvv`, `forge coverage`     |
| **Slither**      | Static analysis — fails on High findings               |
| **Validate**     | Umbrella — required status check for branch protection |

PRs cannot merge while CI is red.

---

## Repository Structure

```
RWA-Tokenization-Platform/
├── packages/
│   ├── contracts/
│   │   ├── src/              Solidity contracts
│   │   ├── test/security/    Vulnerability case studies (S-01, S-02)
│   │   └── script/           Deploy.s.sol + VerifyDeployment.s.sol
│   ├── subgraph/
│   │   ├── subgraph.yaml
│   │   ├── schema.graphql
│   │   └── src/mappings.ts
│   └── frontend/             React + Wagmi + Viem dApp
├── .github/workflows/ci.yml
└── README.md
```
