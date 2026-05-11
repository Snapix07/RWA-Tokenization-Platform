# RWA Tokenization Platform

Monorepo for the Real-World Asset tokenization platform.

| Package | Description |
|---|---|
| [`packages/contracts`](packages/contracts) | Solidity smart contracts (Foundry) |
| [`packages/frontend`](packages/frontend) | React + Vite frontend |

---

## Deployed Contracts

### Base Sepolia (testnet — chain 84532)

| Contract | Address | Explorer |
|---|---|---|
| Counter | _pending_ | — |

### Base Mainnet (chain 8453)

| Contract | Address | Explorer |
|---|---|---|
| Counter | _pending_ | — |

> Update this table after each deployment by pasting the address logged by `Deploy.s.sol` and linking to `https://basescan.org/address/<address>`.

---

## Development Setup

```bash
# Install toolchain dependencies
npm ci

# Compile contracts
cd packages/contracts && forge build

# Run contract tests
forge test -vvv

# Start frontend dev server
npm run dev
```

### Pre-commit hooks

Husky + lint-staged run automatically on `git commit`:

- `forge fmt` + `solhint` on changed `.sol` files
- `prettier --write` on changed frontend files

---

## Deploying Contracts

Copy `.env.example` to `.env` and fill in the values, then:

```bash
# Deploy to Base Sepolia
forge script packages/contracts/script/Deploy.s.sol:Deploy \
  --rpc-url base_sepolia \
  --broadcast \
  --verify \
  -vvvv

# Deploy to Base Mainnet
forge script packages/contracts/script/Deploy.s.sol:Deploy \
  --rpc-url base \
  --broadcast \
  --verify \
  -vvvv
```

The `--verify` flag submits source code to Basescan automatically using the
`[etherscan]` config in `foundry.toml`. Re-running the same script re-deploys
to the same CREATE2 address (salt is pinned to `SALT_VERSION` in `Deploy.s.sol`).

---

## CI

GitHub Actions runs on every push and every pull request:

1. **Lint** — `prettier --check`, `forge fmt --check`, `solhint`
2. **Build & Test** — `forge build`, `forge test`, `forge coverage`
3. **Slither** — static analysis; fails the build on high-severity findings

PRs cannot be merged while CI is red.
