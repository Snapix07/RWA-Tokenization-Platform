import { useState } from "react";
import { useAccount } from "wagmi";
import { useReadContracts } from "wagmi";
import { formatUnits, parseUnits } from "viem";
import { ADDRESSES } from "../config/addresses";
import { ASSET_TOKEN_ABI, RWA_VAULT_ABI } from "../config/abis";
import { useApproveAssetToken, useVaultDeposit, useVaultRedeem } from "../hooks/useVaultActions";
import { TxButton } from "../components/TxButton";

function fmt(raw: bigint | undefined, dec = 18, digits = 4) {
  if (raw === undefined) return "—";
  const n = parseFloat(formatUnits(raw, dec));
  if (n === 0) return "0";
  return n.toLocaleString("en-US", { maximumFractionDigits: digits });
}

export function VaultPage() {
  const { address, isConnected } = useAccount();

  const [depositAmt, setDepositAmt] = useState("");
  const [redeemAmt, setRedeemAmt] = useState("");

  // ── Read data ──────────────────────────────────────────────────────────
  const { data, refetch } = useReadContracts({
    contracts: [
      // [0] user assetToken balance
      {
        address: ADDRESSES.assetToken,
        abi: ASSET_TOKEN_ABI,
        functionName: "balanceOf",
        args: [address!],
      },
      // [1] user vault shares
      {
        address: ADDRESSES.rwaVault,
        abi: RWA_VAULT_ABI,
        functionName: "balanceOf",
        args: [address!],
      },
      // [2] vault totalAssets
      {
        address: ADDRESSES.rwaVault,
        abi: RWA_VAULT_ABI,
        functionName: "totalAssets",
      },
      // [3] vault totalSupply (shares)
      {
        address: ADDRESSES.rwaVault,
        abi: RWA_VAULT_ABI,
        functionName: "totalSupply",
      },
      // [4] navPerShare
      {
        address: ADDRESSES.rwaVault,
        abi: RWA_VAULT_ABI,
        functionName: "navPerShare",
      },
      // [5] allowance assetToken → vault
      {
        address: ADDRESSES.assetToken,
        abi: ASSET_TOKEN_ABI,
        functionName: "allowance",
        args: [address!, ADDRESSES.rwaVault],
      },
      // [6] previewDeposit
      {
        address: ADDRESSES.rwaVault,
        abi: RWA_VAULT_ABI,
        functionName: "previewDeposit",
        args: [
          depositAmt
            ? (() => {
                try {
                  return parseUnits(depositAmt, 18);
                } catch {
                  return 0n;
                }
              })()
            : 0n,
        ],
      },
      // [7] previewRedeem
      {
        address: ADDRESSES.rwaVault,
        abi: RWA_VAULT_ABI,
        functionName: "previewRedeem",
        args: [
          redeemAmt
            ? (() => {
                try {
                  return parseUnits(redeemAmt, 18);
                } catch {
                  return 0n;
                }
              })()
            : 0n,
        ],
      },
      // [8] assetToken symbol
      {
        address: ADDRESSES.assetToken,
        abi: ASSET_TOKEN_ABI,
        functionName: "symbol",
      },
      // [9] paused
      {
        address: ADDRESSES.rwaVault,
        abi: RWA_VAULT_ABI,
        functionName: "paused",
      },
    ],
    query: { enabled: !!address },
  });

  const assetBal = data?.[0]?.result as bigint | undefined;
  const sharesBal = data?.[1]?.result as bigint | undefined;
  const totalAssets = data?.[2]?.result as bigint | undefined;
  const totalShares = data?.[3]?.result as bigint | undefined;
  const navPerShare = data?.[4]?.result as bigint | undefined;
  const allowance = data?.[5]?.result as bigint | undefined;
  const previewDep = data?.[6]?.result as bigint | undefined;
  const previewRed = data?.[7]?.result as bigint | undefined;
  const symbol = data?.[8]?.result as string | undefined;
  const paused = data?.[9]?.result as boolean | undefined;

  const needsApprove =
    depositAmt &&
    allowance !== undefined &&
    (() => {
      try {
        return allowance < parseUnits(depositAmt, 18);
      } catch {
        return false;
      }
    })();

  // ── Actions ────────────────────────────────────────────────────────────
  const approveTx = useApproveAssetToken(address);
  const depositTx = useVaultDeposit(address);
  const redeemTx = useVaultRedeem(address);

  const handleDeposit = async () => {
    if (!depositAmt) return;
    if (needsApprove) {
      await approveTx.approve(depositAmt);
      await refetch();
    }
    await depositTx.deposit(depositAmt);
    setDepositAmt("");
    refetch();
  };

  const handleRedeem = async () => {
    if (!redeemAmt) return;
    await redeemTx.redeem(redeemAmt);
    setRedeemAmt("");
    refetch();
  };

  if (!isConnected) {
    return (
      <div>
        <div className="page-header">
          <h1>Token & Vault</h1>
        </div>
        <div className="card" style={{ textAlign: "center", padding: "40px 24px" }}>
          <div style={{ fontSize: 32, marginBottom: 12 }}>🔌</div>
          <div style={{ fontSize: 16, fontWeight: 600, color: "var(--text-h)" }}>
            Connect your wallet to interact with the vault.
          </div>
        </div>
      </div>
    );
  }

  return (
    <div>
      <div className="page-header">
        <h1>Token & Vault</h1>
        <p>
          Deposit {symbol ?? "ETHBOND"} into the ERC-4626 vault to earn yield. Redeem shares at any
          time.
        </p>
      </div>

      {paused && (
        <div className="network-banner" style={{ marginBottom: 20 }}>
          <span className="network-banner__text">⏸ Vault is currently paused by governance.</span>
        </div>
      )}

      {/* Stats row */}
      <div className="grid-4" style={{ marginBottom: 24 }}>
        <div className="card">
          <div className="card__title">Your {symbol ?? "ETHBOND"}</div>
          <div className="card__value">{fmt(assetBal)}</div>
          <div className="card__sub">Available to deposit</div>
        </div>
        <div className="card">
          <div className="card__title">Your Vault Shares</div>
          <div className="card__value">{fmt(sharesBal)}</div>
          <div className="card__sub">rv{symbol ?? "ETHBOND"}</div>
        </div>
        <div className="card">
          <div className="card__title">Vault Total Assets</div>
          <div className="card__value">{fmt(totalAssets)}</div>
          <div className="card__sub">Total {symbol ?? "ETHBOND"} deposited</div>
        </div>
        <div className="card" style={{ borderColor: "var(--accent-border)" }}>
          <div className="card__title">NAV per Share</div>
          <div className="card__value">{fmt(navPerShare)}</div>
          <div className="card__sub">Total shares: {fmt(totalShares)}</div>
        </div>
      </div>

      {/* Actions */}
      <div className="grid-2">
        {/* Deposit */}
        <div className="card">
          <div className="section-title">⬇️ Deposit</div>

          <div style={{ display: "flex", flexDirection: "column", gap: 14 }}>
            <div className="input-group">
              <label className="input-label">Amount ({symbol ?? "ETHBOND"})</label>
              <div style={{ position: "relative" }}>
                <input
                  className="input-field"
                  type="number"
                  min="0"
                  placeholder="0.0"
                  value={depositAmt}
                  onChange={(e) => setDepositAmt(e.target.value)}
                  style={{ paddingRight: 70 }}
                />
                <button
                  onClick={() => assetBal && setDepositAmt(formatUnits(assetBal, 18))}
                  style={{
                    position: "absolute",
                    right: 10,
                    top: "50%",
                    transform: "translateY(-50%)",
                    background: "var(--accent-bg)",
                    color: "var(--accent)",
                    border: "none",
                    borderRadius: 4,
                    padding: "2px 8px",
                    fontSize: 12,
                    fontWeight: 600,
                    cursor: "pointer",
                  }}
                >
                  MAX
                </button>
              </div>
            </div>

            {depositAmt && previewDep !== undefined && (
              <div
                style={{
                  background: "var(--bg-surface-2)",
                  borderRadius: 6,
                  padding: "10px 14px",
                  fontSize: 13,
                  color: "var(--text)",
                }}
              >
                You will receive ≈{" "}
                <strong style={{ color: "var(--text-h)" }}>
                  {fmt(previewDep)} rv{symbol ?? "ETHBOND"}
                </strong>
              </div>
            )}

            {needsApprove && (
              <div
                style={{
                  background: "var(--warning-bg)",
                  borderRadius: 6,
                  padding: "8px 12px",
                  fontSize: 13,
                  color: "var(--warning)",
                }}
              >
                ⚠️ Approval required before depositing.
              </div>
            )}

            <TxButton
              label={needsApprove ? "1. Approve + Deposit" : "Deposit"}
              loadingLabel={needsApprove ? "⏳ Approving…" : "⏳ Depositing…"}
              status={depositTx.status}
              isConfirming={depositTx.isConfirming}
              isConfirmed={depositTx.isConfirmed}
              errMsg={depositTx.errMsg || approveTx.errMsg}
              disabled={!depositAmt || paused}
              onClick={handleDeposit}
            />
          </div>
        </div>

        {/* Redeem */}
        <div className="card">
          <div className="section-title">⬆️ Redeem</div>

          <div style={{ display: "flex", flexDirection: "column", gap: 14 }}>
            <div className="input-group">
              <label className="input-label">Shares to redeem (rv{symbol ?? "ETHBOND"})</label>
              <div style={{ position: "relative" }}>
                <input
                  className="input-field"
                  type="number"
                  min="0"
                  placeholder="0.0"
                  value={redeemAmt}
                  onChange={(e) => setRedeemAmt(e.target.value)}
                  style={{ paddingRight: 70 }}
                />
                <button
                  onClick={() => sharesBal && setRedeemAmt(formatUnits(sharesBal, 18))}
                  style={{
                    position: "absolute",
                    right: 10,
                    top: "50%",
                    transform: "translateY(-50%)",
                    background: "var(--accent-bg)",
                    color: "var(--accent)",
                    border: "none",
                    borderRadius: 4,
                    padding: "2px 8px",
                    fontSize: 12,
                    fontWeight: 600,
                    cursor: "pointer",
                  }}
                >
                  MAX
                </button>
              </div>
            </div>

            {redeemAmt && previewRed !== undefined && (
              <div
                style={{
                  background: "var(--bg-surface-2)",
                  borderRadius: 6,
                  padding: "10px 14px",
                  fontSize: 13,
                  color: "var(--text)",
                }}
              >
                You will receive ≈{" "}
                <strong style={{ color: "var(--text-h)" }}>
                  {fmt(previewRed)} {symbol ?? "ETHBOND"}
                </strong>
              </div>
            )}

            <TxButton
              label="Redeem"
              loadingLabel="⏳ Redeeming…"
              status={redeemTx.status}
              isConfirming={redeemTx.isConfirming}
              isConfirmed={redeemTx.isConfirmed}
              errMsg={redeemTx.errMsg}
              disabled={!redeemAmt || paused}
              onClick={handleRedeem}
            />
          </div>
        </div>
      </div>

      {/* Vault contract link */}
      <div style={{ marginTop: 16, fontSize: 13, color: "var(--text)" }}>
        Vault contract:{" "}
        <a
          href={`https://sepolia.arbiscan.io/address/${ADDRESSES.rwaVault}`}
          target="_blank"
          rel="noreferrer"
          style={{ color: "var(--accent)" }}
        >
          {ADDRESSES.rwaVault} ↗
        </a>
      </div>
    </div>
  );
}
