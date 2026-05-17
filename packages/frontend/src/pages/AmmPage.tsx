import { useState, useMemo } from "react";
import { useAccount, usePublicClient } from "wagmi";
import { formatUnits, parseUnits } from "viem";
import { type Address } from "viem";
import { ADDRESSES } from "../config/addresses";
import {
  useAmmData,
  useApproveForAmm,
  useAmmSwap,
  useAddLiquidity,
  useRemoveLiquidity,
} from "../hooks/useAmmActions";
import { TxButton } from "../components/TxButton";
import { useQuery } from "@tanstack/react-query";
import { querySubgraph, AMM_SWAPS_QUERY, type SubgraphSwap } from "../config/subgraph";

type Tab = "swap" | "liquidity";

function fmt(raw: bigint | undefined, digits = 4) {
  if (raw === undefined) return "—";
  const n = parseFloat(formatUnits(raw, 18));
  if (n === 0) return "0";
  return n.toLocaleString("en-US", { maximumFractionDigits: digits });
}

function safeParse(val: string): bigint {
  try {
    return parseUnits(val, 18);
  } catch {
    return 0n;
  }
}

function calcAmountOut(amountIn: bigint, reserveIn: bigint, reserveOut: bigint): bigint {
  if (reserveIn === 0n || reserveOut === 0n || amountIn === 0n) return 0n;
  const amountInFee = amountIn * 997n;
  const numerator = amountInFee * reserveOut;
  const denominator = reserveIn * 1000n + amountInFee;
  return numerator / denominator;
}

export function AmmPage() {
  const { address, isConnected } = useAccount();
  const publicClient = usePublicClient();
  const [tab, setTab] = useState<Tab>("swap");

  const [swapDirection, setSwapDirection] = useState<"AtoB" | "BtoA">("AtoB");
  const [swapAmt, setSwapAmt] = useState("");
  const [slippage, setSlippage] = useState("0.5");

  const [amtA, setAmtA] = useState("");
  const [amtB, setAmtB] = useState("");
  const [removeLpAmt, setRemoveLpAmt] = useState("");

  const amm = useAmmData(address);

  const reserveIn = swapDirection === "AtoB" ? amm.reserves?.[1] : amm.reserves?.[0];
  const reserveOut = swapDirection === "AtoB" ? amm.reserves?.[0] : amm.reserves?.[1];
  const tokenIn = swapDirection === "AtoB" ? amm.tokenB : amm.tokenA;

  const amountOut = useMemo(() => {
    if (!swapAmt || !reserveIn || !reserveOut) return 0n;
    return calcAmountOut(safeParse(swapAmt), reserveIn, reserveOut);
  }, [swapAmt, reserveIn, reserveOut]);

  const amountOutMin = useMemo(() => {
    if (amountOut === 0n) return 0n;
    const slippageBps = BigInt(Math.round(parseFloat(slippage || "0") * 100));
    return (amountOut * (10000n - slippageBps)) / 10000n;
  }, [amountOut, slippage]);

  const poolPrice = useMemo(() => {
    const rA = amm.reserves?.[0];
    const rB = amm.reserves?.[1];
    if (!rA || !rB || rA === 0n) return null;
    return (Number(rB) / Number(rA)).toFixed(6);
  }, [amm.reserves]);

  const swapNeedsApproveA =
    swapAmt && swapDirection === "AtoB" && (!amm.allowanceA || safeParse(swapAmt) > amm.allowanceA);
  const swapNeedsApproveB =
    swapAmt && swapDirection === "BtoA" && (!amm.allowanceB || safeParse(swapAmt) > amm.allowanceB);
  const swapNeedsApprove = swapNeedsApproveA || swapNeedsApproveB;

  const approveA = useApproveForAmm(ADDRESSES.assetToken);
  const approveB = useApproveForAmm(ADDRESSES.governanceToken);
  const swapTx = useAmmSwap(address);
  const addLiqTx = useAddLiquidity(address);
  const removeLiqTx = useRemoveLiquidity(address);
  const { data: swapsData, isLoading: swapsLoading } = useQuery({
    queryKey: ["amm-swaps"],
    queryFn: () => querySubgraph<{ ammSwaps: SubgraphSwap[] }>(AMM_SWAPS_QUERY),
    staleTime: 20_000,
    refetchInterval: 30_000,
  });

  const recentSwaps = swapsData?.ammSwaps ?? [];

  const handleSwap = async () => {
    if (!swapAmt || !tokenIn || !publicClient) return;
    if (swapNeedsApproveA) {
      const hash = await approveA.approve();
      if (hash) await publicClient.waitForTransactionReceipt({ hash });
    }
    if (swapNeedsApproveB) {
      const hash = await approveB.approve();
      if (hash) await publicClient.waitForTransactionReceipt({ hash });
    }
    await swapTx.swap(tokenIn as Address, swapAmt, amountOutMin);
    setSwapAmt("");
    amm.refetch();
  };

  const handleAddLiquidity = async () => {
    if (!amtA || !amtB || !publicClient) return;
    if (!amm.allowanceA || safeParse(amtA) > amm.allowanceA) {
      const hash = await approveA.approve();
      if (hash) await publicClient.waitForTransactionReceipt({ hash });
    }
    if (!amm.allowanceB || safeParse(amtB) > amm.allowanceB) {
      const hash = await approveB.approve();
      if (hash) await publicClient.waitForTransactionReceipt({ hash });
    }
    await addLiqTx.addLiquidity(amtA, amtB);
    setAmtA("");
    setAmtB("");
    amm.refetch();
  };

  const handleRemoveLiquidity = async () => {
    if (!removeLpAmt) return;
    await removeLiqTx.removeLiquidity(removeLpAmt);
    setRemoveLpAmt("");
    amm.refetch();
  };

  if (!isConnected) {
    return (
      <div>
        <div className="page-header">
          <h1>AMM Swap</h1>
        </div>
        <div className="card" style={{ textAlign: "center", padding: "40px 24px" }}>
          <div style={{ fontSize: 32, marginBottom: 12 }}>🔌</div>
          <div style={{ fontSize: 16, fontWeight: 600, color: "var(--text-h)" }}>
            Connect your wallet to use the AMM.
          </div>
        </div>
      </div>
    );
  }

  return (
    <div>
      <div className="page-header">
        <h1>AMM Swap</h1>
        <p>Constant-product AMM (x·y=k) with 0.3% fee. Swap tokens or provide liquidity.</p>
      </div>

      <div className="grid-4" style={{ marginBottom: 24 }}>
        <div className="card">
          <div className="card__title">Reserve A (ETHBOND)</div>
          <div className="card__value">{fmt(amm.reserves?.[0])}</div>
        </div>
        <div className="card">
          <div className="card__title">Reserve B (GOV)</div>
          <div className="card__value">{fmt(amm.reserves?.[1])}</div>
        </div>
        <div className="card" style={{ borderColor: "var(--accent-border)" }}>
          <div className="card__title">Pool Price (B per A)</div>
          <div className="card__value">{poolPrice ?? "—"}</div>
          <div className="card__sub">0.3% fee on swaps</div>
        </div>
        <div className="card">
          <div className="card__title">Your LP Tokens</div>
          <div className="card__value">{fmt(amm.userLp)}</div>
          <div className="card__sub">Total: {fmt(amm.totalLp)}</div>
        </div>
      </div>

      <div style={{ display: "flex", gap: 8, marginBottom: 20 }}>
        {(["swap", "liquidity"] as Tab[]).map((t) => (
          <button
            key={t}
            className={`btn ${tab === t ? "btn-primary" : "btn-secondary"}`}
            onClick={() => setTab(t)}
          >
            {t === "swap" ? "🔄 Swap" : "💧 Liquidity"}
          </button>
        ))}
      </div>

      {tab === "swap" && (
        <div style={{ maxWidth: 480 }}>
          <div className="card">
            <div className="section-title">Swap Tokens</div>
            <div
              style={{
                display: "flex",
                alignItems: "center",
                justifyContent: "space-between",
                marginBottom: 16,
                padding: "8px 12px",
                background: "var(--bg-surface-2)",
                borderRadius: 6,
                fontSize: 13,
              }}
            >
              <span style={{ color: "var(--text-h)", fontWeight: 600 }}>
                {swapDirection === "AtoB" ? "ETHBOND → GOV" : "GOV → ETHBOND"}
              </span>
              <button
                className="btn btn-secondary"
                style={{ padding: "4px 12px", fontSize: 12 }}
                onClick={() => {
                  setSwapDirection((d) => (d === "AtoB" ? "BtoA" : "AtoB"));
                  setSwapAmt("");
                }}
              >
                ⇄ Flip
              </button>
            </div>

            <div style={{ display: "flex", flexDirection: "column", gap: 14 }}>
              <div className="input-group">
                <label className="input-label">
                  Amount In ({swapDirection === "AtoB" ? "ETHBOND" : "GOV"})
                </label>
                <input
                  className="input-field"
                  type="number"
                  min="0"
                  placeholder="0.0"
                  value={swapAmt}
                  onChange={(e) => setSwapAmt(e.target.value)}
                />
              </div>

              {swapAmt && (
                <div
                  style={{
                    background: "var(--bg-surface-2)",
                    borderRadius: 6,
                    padding: "10px 14px",
                    fontSize: 13,
                  }}
                >
                  <div style={{ color: "var(--text)", marginBottom: 4 }}>
                    You receive ≈{" "}
                    <strong style={{ color: "var(--text-h)" }}>
                      {fmt(amountOut)} {swapDirection === "AtoB" ? "GOV" : "ETHBOND"}
                    </strong>
                  </div>
                  <div style={{ color: "var(--text)", fontSize: 12 }}>
                    Min received (after slippage):{" "}
                    <span style={{ color: "var(--text-h)" }}>{fmt(amountOutMin)}</span>
                  </div>
                </div>
              )}
              <div className="input-group">
                <label className="input-label">Slippage tolerance (%)</label>
                <div style={{ display: "flex", gap: 6 }}>
                  {["0.1", "0.5", "1.0"].map((s) => (
                    <button
                      key={s}
                      className={`btn ${slippage === s ? "btn-primary" : "btn-secondary"}`}
                      style={{ padding: "5px 12px", fontSize: 13, flex: 1 }}
                      onClick={() => setSlippage(s)}
                    >
                      {s}%
                    </button>
                  ))}
                  <input
                    className="input-field"
                    type="number"
                    placeholder="Custom"
                    value={["0.1", "0.5", "1.0"].includes(slippage) ? "" : slippage}
                    onChange={(e) => setSlippage(e.target.value)}
                    style={{ flex: 1, padding: "5px 10px" }}
                  />
                </div>
              </div>

              {swapNeedsApprove && (
                <div
                  style={{
                    background: "var(--warning-bg)",
                    borderRadius: 6,
                    padding: "8px 12px",
                    fontSize: 13,
                    color: "var(--warning)",
                  }}
                >
                  ⚠️ Approval required before swapping.
                </div>
              )}

              <TxButton
                label={swapNeedsApprove ? "Approve + Swap" : "Swap"}
                loadingLabel="⏳ Swapping…"
                status={swapTx.status}
                isConfirming={swapTx.isConfirming}
                isConfirmed={swapTx.isConfirmed}
                errMsg={swapTx.errMsg || approveA.errMsg}
                disabled={!swapAmt || amountOut === 0n}
                onClick={handleSwap}
              />
            </div>
          </div>
        </div>
      )}

      {tab === "liquidity" && (
        <div className="grid-2">
          <div className="card">
            <div className="section-title">➕ Add Liquidity</div>
            <div style={{ display: "flex", flexDirection: "column", gap: 14 }}>
              <div className="input-group">
                <label className="input-label">Amount A (ETHBOND)</label>
                <input
                  className="input-field"
                  type="number"
                  min="0"
                  placeholder="0.0"
                  value={amtA}
                  onChange={(e) => setAmtA(e.target.value)}
                />
              </div>

              <div className="input-group">
                <label className="input-label">Amount B (GOV)</label>
                <input
                  className="input-field"
                  type="number"
                  min="0"
                  placeholder="0.0"
                  value={amtB}
                  onChange={(e) => setAmtB(e.target.value)}
                />
              </div>

              {amtA && amtB && (
                <div
                  style={{
                    background: "var(--bg-surface-2)",
                    borderRadius: 6,
                    padding: "10px 14px",
                    fontSize: 13,
                    color: "var(--text)",
                  }}
                >
                  Pool ratio:{" "}
                  <strong style={{ color: "var(--text-h)" }}>
                    {poolPrice
                      ? `1 ETHBOND = ${poolPrice} GOV`
                      : "No liquidity yet — you set the initial price"}
                  </strong>
                </div>
              )}

              <TxButton
                label="Add Liquidity"
                loadingLabel="⏳ Adding…"
                status={addLiqTx.status}
                isConfirming={addLiqTx.isConfirming}
                isConfirmed={addLiqTx.isConfirmed}
                errMsg={addLiqTx.errMsg}
                disabled={!amtA || !amtB}
                onClick={handleAddLiquidity}
              />
            </div>
          </div>

          <div className="card">
            <div className="section-title">➖ Remove Liquidity</div>
            <div style={{ display: "flex", flexDirection: "column", gap: 14 }}>
              <div
                style={{
                  background: "var(--bg-surface-2)",
                  borderRadius: 6,
                  padding: "10px 14px",
                  fontSize: 13,
                }}
              >
                Your LP balance:{" "}
                <strong style={{ color: "var(--text-h)" }}>{fmt(amm.userLp)}</strong>
              </div>

              <div className="input-group">
                <label className="input-label">LP tokens to remove</label>
                <div style={{ position: "relative" }}>
                  <input
                    className="input-field"
                    type="number"
                    min="0"
                    placeholder="0.0"
                    value={removeLpAmt}
                    onChange={(e) => setRemoveLpAmt(e.target.value)}
                    style={{ paddingRight: 70 }}
                  />
                  <button
                    onClick={() => amm.userLp && setRemoveLpAmt(formatUnits(amm.userLp, 18))}
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

              <TxButton
                label="Remove Liquidity"
                loadingLabel="⏳ Removing…"
                status={removeLiqTx.status}
                isConfirming={removeLiqTx.isConfirming}
                isConfirmed={removeLiqTx.isConfirmed}
                errMsg={removeLiqTx.errMsg}
                disabled={!removeLpAmt || !amm.userLp || amm.userLp === 0n}
                onClick={handleRemoveLiquidity}
              />
            </div>
          </div>
        </div>
      )}

      <div style={{ marginTop: 16, fontSize: 13, color: "var(--text)" }}>
        AMM contract:{" "}
        <a
          href={`https://sepolia.arbiscan.io/address/${ADDRESSES.rwaAmm}`}
          target="_blank"
          rel="noreferrer"
          style={{ color: "var(--accent)" }}
        >
          {ADDRESSES.rwaAmm} ↗
        </a>
      </div>

      <div style={{ marginTop: 32 }}>
        <div
          style={{
            display: "flex",
            justifyContent: "space-between",
            alignItems: "center",
            marginBottom: 12,
          }}
        >
          <h2 style={{ fontSize: 15, fontWeight: 700, color: "var(--text-h)" }}>Recent Swaps</h2>
          <span style={{ fontSize: 12, color: "var(--text)" }}>📡 Indexed via The Graph</span>
        </div>

        {swapsLoading && (
          <div className="card" style={{ textAlign: "center", padding: 24, color: "var(--text)" }}>
            Loading swap history…
          </div>
        )}

        {!swapsLoading && recentSwaps.length === 0 && (
          <div className="card" style={{ textAlign: "center", padding: 24 }}>
            <div style={{ fontSize: 13, color: "var(--text)" }}>
              No swaps yet. Be the first to swap!
            </div>
          </div>
        )}

        {recentSwaps.length > 0 && (
          <div className="card" style={{ padding: 0, overflow: "hidden" }}>
            <table style={{ width: "100%", borderCollapse: "collapse", fontSize: 13 }}>
              <thead>
                <tr
                  style={{
                    background: "var(--bg-surface-2)",
                    color: "var(--text)",
                    textAlign: "left",
                  }}
                >
                  <th style={{ padding: "10px 14px", fontWeight: 600 }}>Sender</th>
                  <th style={{ padding: "10px 14px", fontWeight: 600 }}>Amount In</th>
                  <th style={{ padding: "10px 14px", fontWeight: 600 }}>Amount Out</th>
                  <th style={{ padding: "10px 14px", fontWeight: 600 }}>Time</th>
                </tr>
              </thead>
              <tbody>
                {recentSwaps.map((swap) => (
                  <tr
                    key={swap.id}
                    style={{ borderTop: "1px solid var(--border)", color: "var(--text-h)" }}
                  >
                    <td style={{ padding: "10px 14px", fontFamily: "monospace", fontSize: 12 }}>
                      {swap.sender.slice(0, 6)}…{swap.sender.slice(-4)}
                    </td>
                    <td style={{ padding: "10px 14px" }}>
                      {parseFloat(formatUnits(BigInt(swap.amountIn), 18)).toFixed(4)}
                    </td>
                    <td style={{ padding: "10px 14px", color: "var(--success)" }}>
                      {parseFloat(formatUnits(BigInt(swap.amountOut), 18)).toFixed(4)}
                    </td>
                    <td style={{ padding: "10px 14px", color: "var(--text)", fontSize: 12 }}>
                      {new Date(Number(swap.timestamp) * 1000).toLocaleString("en-US", {
                        month: "short",
                        day: "numeric",
                        hour: "2-digit",
                        minute: "2-digit",
                      })}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </div>
  );
}
