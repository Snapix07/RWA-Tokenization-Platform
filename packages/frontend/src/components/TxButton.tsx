import { useEffect, useRef } from "react";
import { useToast } from "./Toast";
import { type TxStatus } from "../hooks/useVaultActions";

interface Props {
  status: TxStatus;
  isConfirming: boolean;
  isConfirmed: boolean;
  errMsg: string;
  label: string;
  loadingLabel?: string;
  successMessage?: string;
  onClick: () => void;
  disabled?: boolean;
}

export function TxButton({
  status,
  isConfirming,
  isConfirmed,
  errMsg,
  label,
  loadingLabel,
  successMessage,
  onClick,
  disabled,
}: Props) {
  const toast = useToast();
  const prevConfirmed = useRef(false);
  const prevStatus = useRef<TxStatus>("idle");

  useEffect(() => {
    if (isConfirmed && !prevConfirmed.current) {
      toast.success("Transaction confirmed!", successMessage ?? `${label} completed successfully.`);
    }
    prevConfirmed.current = isConfirmed;
  }, [isConfirmed, label, successMessage, toast]);

  useEffect(() => {
    if (status === "error" && prevStatus.current !== "error" && errMsg) {
      toast.error("Transaction failed", errMsg);
    }
    prevStatus.current = status;
  }, [status, errMsg, toast]);

  const busy = status === "pending" || isConfirming;

  const getBtnLabel = () => {
    if (isConfirming) return "⛓ Confirming…";
    if (status === "pending") return loadingLabel ?? "⏳ Waiting for wallet…";
    return label;
  };

  return (
    <div style={{ display: "flex", flexDirection: "column", gap: 8 }}>
      <button
        className="btn btn-primary"
        style={{ width: "100%" }}
        disabled={disabled || busy}
        onClick={onClick}
      >
        {getBtnLabel()}
      </button>

      {status !== "idle" && (
        <div
          style={{
            fontSize: 12,
            padding: "7px 11px",
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
            lineHeight: 1.4,
          }}
        >
          {isConfirmed
            ? "✅ Confirmed on-chain"
            : status === "error"
              ? errMsg || "Transaction failed."
              : isConfirming
                ? "⛓ Waiting for block confirmation…"
                : "⏳ Check your wallet…"}
        </div>
      )}
    </div>
  );
}
