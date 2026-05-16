import { useAccount } from "wagmi";
import { useProtocolStats } from "../hooks/useProtocolStats";
import { useUserBalances } from "../hooks/useUserBalances";

function fmt(value: string | null, decimals = 4): string {
  if (value === null) return "—";
  const n = parseFloat(value);
  if (n === 0) return "0";
  if (n < 0.0001) return "< 0.0001";
  return n.toLocaleString("en-US", { maximumFractionDigits: decimals });
}

function Skeleton() {
  return (
    <span
      style={{
        display: "inline-block",
        width: 80,
        height: 18,
        borderRadius: 4,
        background: "var(--bg-surface-2)",
        animation: "pulse 1.4s ease-in-out infinite",
      }}
    />
  );
}

interface StatCardProps {
  title: string;
  value: string | null;
  sub?: string;
  loading?: boolean;
  accent?: boolean;
}

function StatCard({ title, value, sub, loading, accent }: StatCardProps) {
  return (
    <div className="card" style={accent ? { borderColor: "var(--accent-border)" } : {}}>
      <div className="card__title">{title}</div>
      <div className="card__value">{loading ? <Skeleton /> : fmt(value)}</div>
      {sub && <div className="card__sub">{sub}</div>}
    </div>
  );
}

export function DashboardPage() {
  const { address, isConnected } = useAccount();
  const stats = useProtocolStats();
  const user = useUserBalances(address);
  const updatedAgo = stats.token.updatedAt
    ? `${Math.round((Date.now() / 1000 - stats.token.updatedAt) / 60)}m ago`
    : "";

  return (
    <div>
      {/* Page header */}
      <div className="page-header">
        <h1>Dashboard</h1>
        <p>Live overview of the RWA Tokenization Protocol on Arbitrum Sepolia.</p>
      </div>

      {/* Protocol status badge */}
      <div style={{ marginBottom: 20, display: "flex", alignItems: "center", gap: 8 }}>
        <span className={`badge ${stats.token.paused ? "badge-defeated" : "badge-active"}`}>
          {stats.token.paused ? "⏸ Protocol Paused" : "● Protocol Active"}
        </span>
        {stats.token.symbol && (
          <span className="badge badge-queued">Token: {stats.token.symbol}</span>
        )}
      </div>

      {/* Global stats */}
      <h2
        style={{
          fontSize: 13,
          fontWeight: 600,
          marginBottom: 12,
          opacity: 0.5,
          letterSpacing: "0.07em",
          textTransform: "uppercase",
        }}
      >
        Protocol Stats
      </h2>
      <div className="grid-4" style={{ marginBottom: 28 }}>
        <StatCard
          title="Asset Price (Oracle)"
          value={stats.token.price}
          sub={
            updatedAgo
              ? `$${stats.token.price ? parseFloat(stats.token.price).toFixed(4) : "—"} · Updated ${updatedAgo}`
              : undefined
          }
          loading={stats.isLoading}
          accent
        />
        <StatCard
          title="Token Total Supply"
          value={stats.token.totalSupply}
          sub={stats.token.symbol}
          loading={stats.isLoading}
        />
        <StatCard
          title="Vault Total Assets"
          value={stats.vault.totalAssets}
          sub={`NAV/share: ${fmt(stats.vault.navPerShare)}`}
          loading={stats.isLoading}
        />
        <StatCard
          title="AMM Reserve A"
          value={stats.amm.reserveA}
          sub={`Reserve B: ${fmt(stats.amm.reserveB)}`}
          loading={stats.isLoading}
        />
      </div>

      {/* User balances */}
      {isConnected ? (
        <>
          <h2
            style={{
              fontSize: 13,
              fontWeight: 600,
              marginBottom: 12,
              opacity: 0.5,
              letterSpacing: "0.07em",
              textTransform: "uppercase",
            }}
          >
            Your Positions
          </h2>
          <div className="grid-4" style={{ marginBottom: 28 }}>
            <StatCard
              title="ETHBOND Balance"
              value={user.assetToken}
              sub="Asset Token"
              loading={user.isLoading}
              accent
            />
            <StatCard
              title="Vault Shares"
              value={user.vaultShares}
              sub="rvETHBOND"
              loading={user.isLoading}
            />
            <StatCard
              title="AMM LP Tokens"
              value={user.ammLp}
              sub="Pool share"
              loading={user.isLoading}
            />
            <StatCard
              title="Voting Power"
              value={user.votingPower}
              sub={
                user.isSelfDelegated
                  ? "Self-delegated ✓"
                  : user.delegateTo
                    ? `→ ${user.delegateTo.slice(0, 6)}…${user.delegateTo.slice(-4)}`
                    : "Not delegated"
              }
              loading={user.isLoading}
            />
          </div>

          {/* Delegation nudge */}
          {!user.isLoading &&
            user.govBalance &&
            parseFloat(user.govBalance) > 0 &&
            !user.isSelfDelegated && (
              <div
                className="network-banner"
                style={{
                  background: "var(--accent-bg)",
                  borderColor: "var(--accent-border)",
                }}
              >
                <span style={{ color: "var(--accent)", fontSize: 14, fontWeight: 500 }}>
                  💡 You have {fmt(user.govBalance)} GOV tokens but no voting power yet. Delegate to
                  yourself in the Governance tab to start voting.
                </span>
              </div>
            )}
        </>
      ) : (
        <div className="card" style={{ textAlign: "center", padding: "40px 24px" }}>
          <div style={{ fontSize: 32, marginBottom: 12 }}>🔌</div>
          <div style={{ fontSize: 16, fontWeight: 600, color: "var(--text-h)", marginBottom: 6 }}>
            Connect your wallet
          </div>
          <div style={{ fontSize: 14, color: "var(--text)" }}>
            Connect MetaMask to see your positions and interact with the protocol.
          </div>
        </div>
      )}

      {/* Contract addresses */}
      <h2
        style={{
          fontSize: 13,
          fontWeight: 600,
          marginBottom: 12,
          marginTop: 8,
          opacity: 0.5,
          letterSpacing: "0.07em",
          textTransform: "uppercase",
        }}
      >
        Deployed Contracts
      </h2>
      <div className="card">
        <table style={{ width: "100%", borderCollapse: "collapse", fontSize: 13 }}>
          <thead>
            <tr style={{ borderBottom: "1px solid var(--border)" }}>
              <th
                style={{
                  textAlign: "left",
                  padding: "6px 12px 10px 0",
                  color: "var(--text)",
                  fontWeight: 600,
                }}
              >
                Contract
              </th>
              <th
                style={{
                  textAlign: "left",
                  padding: "6px 0 10px",
                  color: "var(--text)",
                  fontWeight: 600,
                }}
              >
                Address
              </th>
            </tr>
          </thead>
          <tbody>
            {[
              { name: "AssetToken (ETHBOND)", addr: "0xBE60c53E15328b18E82E7204fbECA45e11628caa" },
              { name: "RWAVault", addr: "0xFbECEB9447925e0c2e433f5eD674F7110AF67018" },
              { name: "RWAAMM", addr: "0x658eD17F2686A652ACC89162c7aA99b957e7938E" },
              { name: "GovernanceToken", addr: "0x57B0e45C40CCE6248a102Cdf8612Cdc683Cf3Fd9" },
              { name: "RWAGovernor", addr: "0x091858adb6f82c323c4B4d1b0aA59Cec953B9E75" },
              { name: "TimelockController", addr: "0x1C9e29A66561B1533578cFc27AB0A4cB7F740c8e" },
            ].map(({ name, addr }) => (
              <tr key={addr} style={{ borderBottom: "1px solid var(--border)" }}>
                <td style={{ padding: "9px 12px 9px 0", color: "var(--text-h)", fontWeight: 500 }}>
                  {name}
                </td>
                <td style={{ padding: "9px 0" }}>
                  <a
                    href={`https://sepolia.arbiscan.io/address/${addr}`}
                    target="_blank"
                    rel="noreferrer"
                    style={{
                      fontFamily: "var(--mono)",
                      fontSize: 12,
                      color: "var(--accent)",
                      textDecoration: "none",
                    }}
                  >
                    {addr.slice(0, 10)}…{addr.slice(-8)} ↗
                  </a>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      {/* Pulse animation for skeleton */}
      <style>{`
        @keyframes pulse {
          0%, 100% { opacity: 1; }
          50%       { opacity: 0.4; }
        }
      `}</style>
    </div>
  );
}
