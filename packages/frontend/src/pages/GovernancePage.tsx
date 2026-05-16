import { useState } from "react";
import { useAccount, useReadContract } from "wagmi";
import { formatUnits } from "viem";
import { type Address } from "viem";
import { useQuery } from "@tanstack/react-query";
import { ADDRESSES } from "../config/addresses";
import { RWA_GOVERNOR_ABI } from "../config/abis";
import {
  useGovernanceData,
  useDelegate,
  useCastVote,
  PROPOSAL_STATES,
} from "../hooks/useGovernance";
import { TxButton } from "../components/TxButton";
import {
  querySubgraph,
  ASSETS_QUERY,
  GOVERNANCE_PROPOSALS_QUERY,
  type SubgraphAsset,
  type SubgraphProposal,
} from "../config/subgraph";

function fmt(raw: bigint | undefined, digits = 2) {
  if (raw === undefined) return "—";
  const n = parseFloat(formatUnits(raw, 18));
  if (n === 0) return "0";
  return n.toLocaleString("en-US", { maximumFractionDigits: digits });
}

function fmtBig(s: string, digits = 2) {
  const n = parseFloat(formatUnits(BigInt(s || "0"), 18));
  return n.toLocaleString("en-US", { maximumFractionDigits: digits });
}

function shortenAddr(addr: string) {
  return `${addr.slice(0, 6)}…${addr.slice(-4)}`;
}

function VotesBar({
  forV,
  againstV,
  abstainV,
}: {
  forV: string;
  againstV: string;
  abstainV: string;
}) {
  const f = parseFloat(formatUnits(BigInt(forV || "0"), 18));
  const a = parseFloat(formatUnits(BigInt(againstV || "0"), 18));
  const b = parseFloat(formatUnits(BigInt(abstainV || "0"), 18));
  const total = f + a + b || 1;

  return (
    <div style={{ marginTop: 10 }}>
      <div
        style={{
          display: "flex",
          height: 6,
          borderRadius: 3,
          overflow: "hidden",
          background: "var(--bg-surface-2)",
        }}
      >
        <div style={{ width: `${(f / total) * 100}%`, background: "var(--success)" }} />
        <div style={{ width: `${(a / total) * 100}%`, background: "var(--danger)" }} />
        <div style={{ width: `${(b / total) * 100}%`, background: "var(--text)" }} />
      </div>
      <div style={{ display: "flex", gap: 12, marginTop: 5, fontSize: 12, color: "var(--text)" }}>
        <span style={{ color: "var(--success)" }}>✓ For: {fmtBig(forV)}</span>
        <span style={{ color: "var(--danger)" }}>✗ Against: {fmtBig(againstV)}</span>
        <span>◦ Abstain: {fmtBig(abstainV)}</span>
      </div>
    </div>
  );
}

// ── Карточка пропозала ────────────────────────────────────────────────────
function ProposalCard({
  proposal,
  userAddress,
}: {
  proposal: SubgraphProposal;
  userAddress?: Address;
}) {
  const [voteReason, setVoteReason] = useState("");
  const [showReason, setShowReason] = useState(false);

  const proposalIdBig = BigInt(proposal.proposalId);

  // Проверяем on-chain state (свежее чем subgraph)
  const { data: onChainState } = useReadContract({
    address: ADDRESSES.rwaGovernor,
    abi: RWA_GOVERNOR_ABI,
    functionName: "state",
    args: [proposalIdBig],
  });

  const { data: hasVoted } = useReadContract({
    address: ADDRESSES.rwaGovernor,
    abi: RWA_GOVERNOR_ABI,
    functionName: "hasVoted",
    args: [proposalIdBig, userAddress!],
    query: { enabled: !!userAddress },
  });

  const castVoteTx = useCastVote();

  const stateNum = onChainState !== undefined ? Number(onChainState) : proposal.state;
  const stateInfo = PROPOSAL_STATES[stateNum] ?? { label: "Unknown", badge: "badge-queued" };
  const isActive = stateNum === 1;

  const deadline = new Date(Number(proposal.voteEnd) * 1000).toLocaleString("en-US", {
    month: "short",
    day: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  });

  const shortDesc =
    proposal.description.length > 120
      ? proposal.description.slice(0, 120) + "…"
      : proposal.description;

  return (
    <div className="card" style={{ marginBottom: 14 }}>
      {/* Header */}
      <div
        style={{
          display: "flex",
          justifyContent: "space-between",
          alignItems: "flex-start",
          marginBottom: 10,
        }}
      >
        <div style={{ flex: 1, marginRight: 12 }}>
          <div style={{ fontSize: 14, fontWeight: 600, color: "var(--text-h)", marginBottom: 4 }}>
            {shortDesc || `Proposal #${proposal.proposalId.slice(-6)}`}
          </div>
          <div style={{ fontSize: 12, color: "var(--text)" }}>
            By {shortenAddr(proposal.proposer)} · Ends {deadline}
          </div>
        </div>
        <div style={{ display: "flex", flexDirection: "column", alignItems: "flex-end", gap: 4 }}>
          <span className={`badge ${stateInfo.badge}`}>{stateInfo.label}</span>
          {hasVoted && (
            <span className="badge badge-executed" style={{ fontSize: 11 }}>
              Voted ✓
            </span>
          )}
        </div>
      </div>

      {/* Votes bar */}
      <VotesBar
        forV={proposal.forVotes}
        againstV={proposal.againstVotes}
        abstainV={proposal.abstainVotes}
      />

      {/* Vote buttons — only when active and not voted */}
      {isActive && !hasVoted && userAddress && (
        <div style={{ marginTop: 14 }}>
          <hr className="divider" />

          {/* Reason toggle */}
          <div style={{ marginBottom: 10 }}>
            <button
              className="btn btn-secondary"
              style={{ fontSize: 12, padding: "4px 10px" }}
              onClick={() => setShowReason((v) => !v)}
            >
              {showReason ? "Hide reason" : "+ Add reason (optional)"}
            </button>
          </div>

          {showReason && (
            <textarea
              className="input-field"
              placeholder="Reason for your vote…"
              value={voteReason}
              onChange={(e) => setVoteReason(e.target.value)}
              style={{
                marginBottom: 10,
                minHeight: 60,
                resize: "vertical",
                fontFamily: "var(--sans)",
              }}
            />
          )}

          <div style={{ display: "flex", gap: 8 }}>
            {(
              [
                { support: 1 as const, label: "✓ For", cls: "btn-primary" },
                { support: 0 as const, label: "✗ Against", cls: "btn-danger" },
                { support: 2 as const, label: "◦ Abstain", cls: "btn-secondary" },
              ] as const
            ).map(({ support, label, cls }) => (
              <button
                key={support}
                className={`btn ${cls}`}
                style={{ flex: 1 }}
                disabled={castVoteTx.status === "pending" || castVoteTx.isConfirming}
                onClick={() => castVoteTx.castVote(proposalIdBig, support, voteReason || undefined)}
              >
                {label}
              </button>
            ))}
          </div>

          {castVoteTx.status !== "idle" && (
            <div
              style={{
                marginTop: 8,
                fontSize: 13,
                padding: "8px 12px",
                borderRadius: 6,
                background:
                  castVoteTx.status === "error"
                    ? "var(--danger-bg)"
                    : castVoteTx.isConfirmed
                      ? "var(--success-bg)"
                      : "var(--accent-bg)",
                color:
                  castVoteTx.status === "error"
                    ? "var(--danger)"
                    : castVoteTx.isConfirmed
                      ? "var(--success)"
                      : "var(--accent)",
              }}
            >
              {castVoteTx.isConfirmed
                ? "✅ Vote confirmed!"
                : castVoteTx.status === "error"
                  ? castVoteTx.errMsg
                  : castVoteTx.isConfirming
                    ? "⛓ Confirming on-chain…"
                    : "⏳ Waiting for wallet…"}
            </div>
          )}
        </div>
      )}

      {isActive && hasVoted && (
        <div
          style={{
            marginTop: 10,
            fontSize: 13,
            color: "var(--success)",
            background: "var(--success-bg)",
            padding: "6px 12px",
            borderRadius: 6,
          }}
        >
          ✅ You have already voted on this proposal.
        </div>
      )}

      {/* Proposal ID */}
      <div style={{ marginTop: 10, fontSize: 11, color: "var(--text)", opacity: 0.5 }}>
        ID: {proposal.proposalId}
      </div>
    </div>
  );
}

// ── Главная страница ──────────────────────────────────────────────────────
export function GovernancePage() {
  const { address, isConnected } = useAccount();
  const [delegateInput, setDelegateInput] = useState("");

  const govData = useGovernanceData(address);
  const delegateTx = useDelegate(address);

  // Subgraph: assetTokens (react-query + graphql-request, с Authorization header)
  const {
    data: assetsData,
    isLoading: subgraphFetching,
    error: subgraphError,
  } = useQuery({
    queryKey: ["subgraph-assets"],
    queryFn: () => querySubgraph<{ assetTokens: SubgraphAsset[] }>(ASSETS_QUERY),
    staleTime: 30_000,
  });

  // Subgraph: governanceProposals (появятся как только будут созданы on-chain)
  const { data: proposalsData } = useQuery({
    queryKey: ["subgraph-proposals"],
    queryFn: () =>
      querySubgraph<{ governanceProposals: SubgraphProposal[] }>(GOVERNANCE_PROPOSALS_QUERY),
    staleTime: 30_000,
  });

  const assets: SubgraphAsset[] = assetsData?.assetTokens ?? [];
  const proposals: SubgraphProposal[] = proposalsData?.governanceProposals ?? [];

  const isSelfDelegated = govData.delegateTo?.toLowerCase() === address?.toLowerCase();

  const handleSelfDelegate = async () => {
    if (!address) return;
    await delegateTx.delegate(address);
    govData.refetch();
  };

  const handleCustomDelegate = async () => {
    if (!delegateInput || !delegateInput.startsWith("0x")) return;
    await delegateTx.delegate(delegateInput as Address);
    setDelegateInput("");
    govData.refetch();
  };

  if (!isConnected) {
    return (
      <div>
        <div className="page-header">
          <h1>Governance</h1>
        </div>
        <div className="card" style={{ textAlign: "center", padding: "40px 24px" }}>
          <div style={{ fontSize: 32, marginBottom: 12 }}>🔌</div>
          <div style={{ fontSize: 16, fontWeight: 600, color: "var(--text-h)" }}>
            Connect your wallet to participate in governance.
          </div>
        </div>
      </div>
    );
  }

  return (
    <div>
      <div className="page-header">
        <h1>Governance</h1>
        <p>
          DAO governance — 4% quorum, 1% proposal threshold, 1-day delay, 1-week voting period,
          2-day timelock.
        </p>
      </div>

      {/* GOV stats */}
      <div className="grid-4" style={{ marginBottom: 24 }}>
        <div className="card">
          <div className="card__title">GOV Balance</div>
          <div className="card__value">{fmt(govData.govBalance)}</div>
          <div className="card__sub">Governance token</div>
        </div>
        <div className="card" style={{ borderColor: "var(--accent-border)" }}>
          <div className="card__title">Voting Power</div>
          <div className="card__value">{fmt(govData.votingPower)}</div>
          <div className="card__sub">
            {isSelfDelegated
              ? "Self-delegated ✓"
              : govData.delegateTo &&
                  govData.delegateTo !== "0x0000000000000000000000000000000000000000"
                ? `→ ${shortenAddr(govData.delegateTo)}`
                : "Not delegated"}
          </div>
        </div>
        <div className="card">
          <div className="card__title">Total Supply</div>
          <div className="card__value">{fmt(govData.totalSupply)}</div>
          <div className="card__sub">GOV tokens</div>
        </div>
        <div className="card">
          <div className="card__title">Proposals</div>
          <div className="card__value">{proposals.length}</div>
          <div className="card__sub">On-chain</div>
        </div>
      </div>

      {/* Delegation */}
      <div className="card" style={{ marginBottom: 24 }}>
        <div className="section-title">🗳️ Delegation</div>

        {!isSelfDelegated && govData.govBalance !== undefined && govData.govBalance > 0n && (
          <div
            style={{
              background: "var(--warning-bg)",
              border: "1px solid var(--warning)",
              borderRadius: 6,
              padding: "10px 14px",
              fontSize: 13,
              color: "var(--warning)",
              marginBottom: 14,
            }}
          >
            ⚠️ You have GOV tokens but no voting power. Delegate to activate it.
          </div>
        )}

        <div style={{ display: "flex", gap: 12, flexWrap: "wrap" }}>
          {/* Self-delegate */}
          <div style={{ flex: 1, minWidth: 200 }}>
            <TxButton
              label="Delegate to Myself"
              loadingLabel="⏳ Delegating…"
              status={delegateTx.status}
              isConfirming={delegateTx.isConfirming}
              isConfirmed={delegateTx.isConfirmed}
              errMsg={delegateTx.errMsg}
              disabled={isSelfDelegated}
              onClick={handleSelfDelegate}
            />
            {isSelfDelegated && (
              <div style={{ fontSize: 12, color: "var(--success)", marginTop: 6 }}>
                ✓ Already self-delegated
              </div>
            )}
          </div>

          {/* Custom delegate */}
          <div style={{ flex: 2, minWidth: 280, display: "flex", flexDirection: "column", gap: 8 }}>
            <input
              className="input-field"
              placeholder="0x… delegate address"
              value={delegateInput}
              onChange={(e) => setDelegateInput(e.target.value)}
            />
            <button
              className="btn btn-secondary"
              disabled={
                !delegateInput || !delegateInput.startsWith("0x") || delegateTx.status === "pending"
              }
              onClick={handleCustomDelegate}
            >
              Delegate to Address
            </button>
          </div>
        </div>
      </div>

      {/* ── Registered Assets — from The Graph ───────────────────────── */}
      <div
        style={{
          marginBottom: 16,
          display: "flex",
          justifyContent: "space-between",
          alignItems: "center",
        }}
      >
        <h2 style={{ fontSize: 15, fontWeight: 700, color: "var(--text-h)" }}>Registered Assets</h2>
        <span style={{ fontSize: 12, color: "var(--text)" }}>📡 Indexed via The Graph</span>
      </div>

      {subgraphFetching && (
        <div className="card" style={{ textAlign: "center", padding: 24, color: "var(--text)" }}>
          Loading assets from subgraph…
        </div>
      )}

      {subgraphError && (
        <div
          className="card"
          style={{
            background: "var(--danger-bg)",
            borderColor: "var(--danger)",
            color: "var(--danger)",
            fontSize: 13,
            padding: "12px 16px",
            marginBottom: 24,
          }}
        >
          ⚠️ Could not load assets from subgraph.{" "}
          <span style={{ opacity: 0.7 }}>{subgraphError.message}</span>
        </div>
      )}

      {!subgraphFetching && !subgraphError && assets.length === 0 && (
        <div className="card" style={{ textAlign: "center", padding: "24px", marginBottom: 24 }}>
          <div style={{ fontSize: 13, color: "var(--text)" }}>
            No assets indexed yet. Assets created via AssetFactory will appear here.
          </div>
        </div>
      )}

      {!subgraphFetching && assets.length > 0 && (
        <div className="card" style={{ marginBottom: 24 }}>
          <table style={{ width: "100%", borderCollapse: "collapse", fontSize: 13 }}>
            <thead>
              <tr style={{ color: "var(--text)", textAlign: "left" }}>
                <th style={{ padding: "6px 8px", fontWeight: 600 }}>Asset ID</th>
                <th style={{ padding: "6px 8px", fontWeight: 600 }}>Address</th>
                <th style={{ padding: "6px 8px", fontWeight: 600 }}>Deterministic</th>
                <th style={{ padding: "6px 8px", fontWeight: 600 }}>Deployed</th>
              </tr>
            </thead>
            <tbody>
              {assets.map((a) => (
                <tr
                  key={a.id}
                  style={{ borderTop: "1px solid var(--border)", color: "var(--text-h)" }}
                >
                  <td style={{ padding: "8px 8px", fontFamily: "monospace", fontSize: 12 }}>
                    {a.assetId.slice(0, 10)}…
                  </td>
                  <td style={{ padding: "8px 8px", fontFamily: "monospace", fontSize: 12 }}>
                    {a.id.slice(0, 8)}…{a.id.slice(-4)}
                  </td>
                  <td style={{ padding: "8px 8px" }}>{a.deterministic ? "✓ CREATE2" : "CREATE"}</td>
                  <td style={{ padding: "8px 8px" }}>
                    {new Date(Number(a.deployedAt) * 1000).toLocaleDateString()}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {/* ── Proposals list ────────────────────────────────────────────── */}
      <div
        style={{
          marginBottom: 16,
          display: "flex",
          justifyContent: "space-between",
          alignItems: "center",
        }}
      >
        <h2 style={{ fontSize: 15, fontWeight: 700, color: "var(--text-h)" }}>Proposals</h2>
        <span style={{ fontSize: 12, color: "var(--text)" }}>⛓ On-chain state</span>
      </div>

      {proposals.length === 0 && (
        <div className="card" style={{ textAlign: "center", padding: "32px 24px" }}>
          <div style={{ fontSize: 28, marginBottom: 10 }}>🏛️</div>
          <div style={{ fontSize: 15, fontWeight: 600, color: "var(--text-h)", marginBottom: 6 }}>
            No proposals yet
          </div>
          <div style={{ fontSize: 13, color: "var(--text)" }}>
            Proposals created through the Governor will appear here once indexed.
          </div>
        </div>
      )}

      {proposals.map((p) => (
        <ProposalCard key={p.id} proposal={p} userAddress={address} />
      ))}

      {/* Links */}
      <div style={{ marginTop: 16, fontSize: 13, color: "var(--text)", display: "flex", gap: 20 }}>
        <a
          href={`https://sepolia.arbiscan.io/address/${ADDRESSES.rwaGovernor}`}
          target="_blank"
          rel="noreferrer"
          style={{ color: "var(--accent)" }}
        >
          Governor ↗
        </a>

        <a
          href={`https://sepolia.arbiscan.io/address/${ADDRESSES.timelockController}`}
          target="_blank"
          rel="noreferrer"
          style={{ color: "var(--accent)" }}
        >
          Timelock ↗
        </a>

        <a
          href={`https://sepolia.arbiscan.io/address/${ADDRESSES.governanceToken}`}
          target="_blank"
          rel="noreferrer"
          style={{ color: "var(--accent)" }}
        >
          GOV Token ↗
        </a>
      </div>
    </div>
  );
}
