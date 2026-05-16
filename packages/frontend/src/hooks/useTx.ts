import { useState } from "react";
import { useWriteContract, useWaitForTransactionReceipt } from "wagmi";
import { parseError } from "../lib/parseError";

export type TxStatus = "idle" | "pending" | "success" | "error";

/**
 * Shared transaction hook — используется во всех action-хуках.
 * Централизует error parsing через parseError().
 */
export function useTx() {
  const { writeContractAsync } = useWriteContract();
  const [hash, setHash] = useState<`0x${string}` | undefined>();
  const [status, setStatus] = useState<TxStatus>("idle");
  const [errMsg, setErrMsg] = useState("");

  const { isLoading: isConfirming, isSuccess: isConfirmed } = useWaitForTransactionReceipt({
    hash,
  });

  const send = async (fn: () => Promise<`0x${string}`>) => {
    try {
      setStatus("pending");
      setErrMsg("");
      const txHash = await fn();
      setHash(txHash);
      setStatus("success");
    } catch (e: unknown) {
      setStatus("error");
      setErrMsg(parseError(e));
    }
  };

  const reset = () => {
    setStatus("idle");
    setErrMsg("");
    setHash(undefined);
  };

  return {
    send,
    reset,
    hash,
    status,
    errMsg,
    isConfirming,
    isConfirmed,
    writeContractAsync,
  };
}
