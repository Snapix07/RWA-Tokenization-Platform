# RWA Tokenization Platform

A production-grade decentralized protocol for tokenizing real-world assets (RWA) on Base Sepolia. Blockchain Technologies 2 final project — Option C.

| Package | Description |
|---|---|
| [`packages/contracts`](packages/contracts) | Solidity smart contracts (Foundry) |
| [`packages/subgraph`](packages/subgraph) | The Graph subgraph |
| [`packages/frontend`](packages/frontend) | React + Vite dApp |

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

## Deployed Contracts — Base Sepolia (chain 84532)

> Run `forge script script/Deploy.s.sol --rpc-url base_sepolia --broadcast --verify` then update this table.

| Contract | Address | Basescan |
|---|---|---|
| GovernanceToken | `pending` | — |
| ChainlinkOracleAdapter | `pending` | — |
| AssetNFT | `pending` | — |
| AssetTokenV1 impl | `pending` | — |
| AssetTokenV2 impl | `pending` | — |
| AssetFactory | `pending` | — |
| AssetToken ETHBOND (proxy) | `pending` | — |
| RWAVault (proxy) | `pending` | — |
| RWAAMM | `pending` | — |
| RWATimelockController | `pending` | — |
| RWAGovernor | `pending` | — |

---

## Smart Contracts

| Contract | Purpose | Patterns |
|---|---|---|
| `GovernanceToken` | ERC20Votes + ERC20Permit DAO token | AccessControl |
| `AssetNFT` | ERC-721 legal certificate per onboarded asset | AccessControl, Pausable |
| `AssetTokenV1` | RWA-backed ERC-20, UUPS V1 | UUPS, CEI, ReentrancyGuard |
| `AssetTokenV2` | UUPS V2 — adds KYC whitelist + mint fee | UUPS upgrade |
| `AssetFactory` | Deploys token proxies via CREATE and CREATE2 | Factory, AccessControl |
| `ChainlinkOracleAdapter` | Chainlink wrapper with staleness check + Yul gas benchmark | OracleAdapter, Pausable |
| `RWAVault` | ERC-4626 yield vault, UUPS | UUPS, CEI, ReentrancyGuard |
| `RWAAMM` | x·y=k AMM, 0.3% fee, LP tokens, built from scratch | CEI, ReentrancyGuard |
| `RWATimelockController` | 2-day governance timelock | Timelock |
| `RWAGovernor` | DAO: 4% quorum, 1% threshold, 1-day delay/1-week period | Timelock |

---

## Subgraph

Subgraph Studio slug: `rwa-tokenization-platform` — network: `base-sepolia`

**4 entities:** `AssetToken`, `VaultPosition`, `AmmSwap`, `GovernanceProposal` / `ProposalVote`

### 5 Documented GraphQL Queries

**Q1 — All deployed asset tokens**
```graphql
{ assetTokens(orderBy: deployedAt, orderDirection: desc) { id assetId deterministic deployedAt } }
```

**Q2 — Vault positions for a user**
```graphql
query UserPositions($user: String!) {
  vaultPositions(where: { user: $user }) { vault totalDeposited totalWithdrawn sharesBalance }
}
```

**Q3 — Recent AMM swaps**
```graphql
{ ammSwaps(first: 20, orderBy: timestamp, orderDirection: desc) { sender tokenIn amountIn amountOut timestamp } }
```

**Q4 — Active governance proposals**
```graphql
{ governanceProposals(where: { state: 1 }) { proposalId proposer description forVotes againstVotes abstainVotes voteEnd } }
```

**Q5 — All votes on a proposal**
```graphql
query Votes($id: String!) { governanceProposal(id: $id) { forVotes againstVotes votes { voter support weight } } }
```

---

## Governance Parameters

| Parameter | Value |
|---|---|
| Voting delay | 43 200 blocks (~1 day, Base Sepolia 2 s/block) |
| Voting period | 302 400 blocks (~1 week) |
| Quorum | 4% of total supply at snapshot block |
| Proposal threshold | 1% of current total supply (dynamic) |
| Timelock min delay | 2 days |

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
cp .env.example .env   # fill PRIVATE_KEY, BASE_SEPOLIA_RPC_URL, BASESCAN_API_KEY, DEPLOYER_ADDRESS

cd packages/contracts
forge script script/Deploy.s.sol --rpc-url base_sepolia --broadcast --verify -vvvv

# Verify post-deployment wiring (fill env vars with deployed addresses first)
forge script script/VerifyDeployment.s.sol --rpc-url base_sepolia
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

## Security

**Design patterns used:** Factory, Proxy/UUPS, CEI, AccessControl, Pausable, OracleAdapter, Timelock, ReentrancyGuard

**Vulnerability case studies:**
- **S-01 Reentrancy** (`test/security/ReentrancyAttack.t.sol`) — attacker drains 5× deposit from vault missing CEI. Fixed: `ReentrancyGuard` + effects-before-interactions.
- **S-02 Access Control** (`test/security/AccessControlAttack.t.sol`) — any address deploys tokens on unguarded factory. Fixed: `FACTORY_ROLE` on `AssetFactory.deployAssetToken`.

---

## CI/CD

GitHub Actions on every push and PR:

| Job | Steps |
|---|---|
| **Lint** | `prettier --check`, `forge fmt --check`, `solhint` |
| **Build & Test** | `forge build`, `forge test -vvv`, `forge coverage` |
| **Slither** | Static analysis — fails on High findings |
| **Validate** | Umbrella — required status check for branch protection |

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
