import { useState } from "react";
import { useWriteContract, useWaitForTransactionReceipt } from "wagmi";
import { parseError } from "../lib/parseError";

export type TxStatus = "idle" | "pending" | "success" | "error";

export function useTx() {
  const { writeContractAsync } = useWriteContract();
  const [hash, setHash] = useState<`0x${string}` | undefined>();
  const [status, setStatus] = useState<TxStatus>("idle");
  const [errMsg, setErrMsg] = useState("");

  const { isLoading: isConfirming, isSuccess: isConfirmed } = useWaitForTransactionReceipt({
    hash,
  });

  const send = async (fn: () => Promise<`0x${string}`>): Promise<`0x${string}` | undefined> => {
    try {
      setStatus("pending");
      setErrMsg("");
      const txHash = await fn();
      setHash(txHash);
      setStatus("success");
      return txHash;
    } catch (e: unknown) {
      console.error("[useTx] transaction error:", e);
      setStatus("error");
      setErrMsg(parseError(e));
      return undefined;
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
