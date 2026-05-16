import { useState } from "react";
import { useWriteContract, useWaitForTransactionReceipt, useReadContract } from "wagmi";
import { parseUnits, maxUint256 } from "viem";
import { type Address } from "viem";
import { ADDRESSES } from "../config/addresses";
import { ASSET_TOKEN_ABI, RWA_VAULT_ABI } from "../config/abis";

export type TxStatus = "idle" | "pending" | "success" | "error";

function useTx() {
  const { writeContractAsync } = useWriteContract();
  const [hash, setHash] = useState<`0x${string}` | undefined>();
  const [status, setStatus] = useState<TxStatus>("idle");
  const [errMsg, setErrMsg] = useState<string>("");

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
      if (e instanceof Error) {
        if (e.message.includes("User rejected")) {
          setErrMsg("Transaction rejected by user.");
        } else if (e.message.includes("insufficient")) {
          setErrMsg("Insufficient balance.");
        } else {
          setErrMsg(e.message.slice(0, 120));
        }
      }
    }
  };

  return { send, hash, status, errMsg, isConfirming, isConfirmed };
}

export function useApproveAssetToken(owner?: Address) {
  const tx = useTx();
  const { writeContractAsync } = useWriteContract();

  const { data: allowance, refetch: refetchAllowance } = useReadContract({
    address: ADDRESSES.assetToken,
    abi: ASSET_TOKEN_ABI,
    functionName: "allowance",
    args: [owner!, ADDRESSES.rwaVault],
    query: { enabled: !!owner },
  });

  const approve = (amount: string) =>
    tx.send(() =>
      writeContractAsync({
        address: ADDRESSES.assetToken,
        abi: ASSET_TOKEN_ABI,
        functionName: "approve",
        args: [ADDRESSES.rwaVault, maxUint256],
      }),
    );

  return { ...tx, approve, allowance, refetchAllowance };
}

export function useVaultDeposit(receiver?: Address) {
  const tx = useTx();
  const { writeContractAsync } = useWriteContract();

  const deposit = (assets: string) =>
    tx.send(() =>
      writeContractAsync({
        address: ADDRESSES.rwaVault,
        abi: RWA_VAULT_ABI,
        functionName: "deposit",
        args: [parseUnits(assets, 18), receiver!],
      }),
    );

  return { ...tx, deposit };
}

export function useVaultRedeem(owner?: Address) {
  const tx = useTx();
  const { writeContractAsync } = useWriteContract();

  const redeem = (shares: string) =>
    tx.send(() =>
      writeContractAsync({
        address: ADDRESSES.rwaVault,
        abi: RWA_VAULT_ABI,
        functionName: "redeem",
        args: [parseUnits(shares, 18), owner!, owner!],
      }),
    );

  return { ...tx, redeem };
}
