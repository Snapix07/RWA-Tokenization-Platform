import { type TxStatus } from "../hooks/useVaultActions";

interface Props {
  status: TxStatus;
  isConfirming: boolean;
  isConfirmed: boolean;
  errMsg: string;
  label: string;
  loadingLabel?: string;
  onClick: () => void;
  disabled?: boolean;
}

const STATUS_LABELS: Record<string, string> = {
  pending: "⏳ Waiting for wallet…",
  success: "✅ Submitted!",
  error: "❌ Failed",
};

export function TxButton({
  status,
  isConfirming,
  isConfirmed,
  errMsg,
  label,
  loadingLabel,
  onClick,
  disabled,
}: Props) {
  const busy = status === "pending" || isConfirming;

  return (
    <div style={{ display: "flex", flexDirection: "column", gap: 8 }}>
      <button
        className="btn btn-primary"
        style={{ width: "100%" }}
        disabled={disabled || busy}
        onClick={onClick}
      >
        {isConfirming
          ? "⛓ Confirming on-chain…"
          : status === "pending"
            ? (loadingLabel ?? "⏳ Waiting…")
            : label}
      </button>

      {status !== "idle" && (
        <div
          style={{
            fontSize: 13,
            padding: "8px 12px",
            borderRadius: 6,
            background:
              status === "error"
                ? "var(--danger-bg)"
                : isConfirmed
                  ? "var(--success-bg)"
                  : "var(--accent-bg)",
            color:
              status === "error"
                ? "var(--danger)"
                : isConfirmed
                  ? "var(--success)"
                  : "var(--accent)",
          }}
        >
          {isConfirmed
            ? "✅ Transaction confirmed!"
            : status === "error"
              ? errMsg || "Transaction failed."
              : STATUS_LABELS[status]}
        </div>
      )}
    </div>
  );
}
