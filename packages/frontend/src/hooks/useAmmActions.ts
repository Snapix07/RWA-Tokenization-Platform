import { useState } from "react";
import { useWriteContract, useWaitForTransactionReceipt, useReadContracts } from "wagmi";
import { parseUnits, maxUint256 } from "viem";
import { type Address } from "viem";
import { ADDRESSES } from "../config/addresses";
import { ASSET_TOKEN_ABI, RWA_AMM_ABI } from "../config/abis";

export type TxStatus = "idle" | "pending" | "success" | "error";

function useTx() {
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
      if (e instanceof Error) {
        if (e.message.includes("User rejected")) setErrMsg("Transaction rejected.");
        else if (e.message.includes("insufficient")) setErrMsg("Insufficient balance.");
        else if (e.message.includes("INSUFFICIENT_OUTPUT"))
          setErrMsg("Slippage too high. Try a smaller amount.");
        else setErrMsg(e.message.slice(0, 120));
      }
    }
  };

  return { send, hash, status, errMsg, isConfirming, isConfirmed, writeContractAsync };
}

export function useApproveForAmm(tokenAddress: Address, owner?: Address) {
  const tx = useTx();
  const { writeContractAsync } = useWriteContract();

  const approve = () =>
    tx.send(() =>
      writeContractAsync({
        address: tokenAddress,
        abi: ASSET_TOKEN_ABI,
        functionName: "approve",
        args: [ADDRESSES.rwaAmm, maxUint256],
      }),
    );

  return { ...tx, approve };
}

export function useAmmSwap(recipient?: Address) {
  const tx = useTx();
  const { writeContractAsync } = useWriteContract();

  const swap = (tokenIn: Address, amountIn: string, amountOutMin: bigint) =>
    tx.send(() =>
      writeContractAsync({
        address: ADDRESSES.rwaAmm,
        abi: RWA_AMM_ABI,
        functionName: "swap",
        args: [tokenIn, parseUnits(amountIn, 18), amountOutMin, recipient!],
      }),
    );

  return { ...tx, swap };
}

export function useAddLiquidity(recipient?: Address) {
  const tx = useTx();
  const { writeContractAsync } = useWriteContract();

  const addLiquidity = (amountA: string, amountB: string) =>
    tx.send(() =>
      writeContractAsync({
        address: ADDRESSES.rwaAmm,
        abi: RWA_AMM_ABI,
        functionName: "addLiquidity",
        args: [parseUnits(amountA, 18), parseUnits(amountB, 18), 0n, 0n, recipient!],
      }),
    );

  return { ...tx, addLiquidity };
}

export function useRemoveLiquidity(recipient?: Address) {
  const tx = useTx();
  const { writeContractAsync } = useWriteContract();

  const removeLiquidity = (liquidity: string) =>
    tx.send(() =>
      writeContractAsync({
        address: ADDRESSES.rwaAmm,
        abi: RWA_AMM_ABI,
        functionName: "removeLiquidity",
        args: [parseUnits(liquidity, 18), 0n, 0n, recipient!],
      }),
    );

  return { ...tx, removeLiquidity };
}

export function useAmmData(address?: Address) {
  const { data, refetch } = useReadContracts({
    contracts: [
      {
        address: ADDRESSES.rwaAmm,
        abi: RWA_AMM_ABI,
        functionName: "getReserves",
      },
      {
        address: ADDRESSES.rwaAmm,
        abi: RWA_AMM_ABI,
        functionName: "tokenA",
      },
      {
        address: ADDRESSES.rwaAmm,
        abi: RWA_AMM_ABI,
        functionName: "tokenB",
      },
      {
        address: ADDRESSES.rwaAmm,
        abi: RWA_AMM_ABI,
        functionName: "totalSupply",
      },
      {
        address: ADDRESSES.rwaAmm,
        abi: RWA_AMM_ABI,
        functionName: "balanceOf",
        args: [address!],
      },
      {
        address: ADDRESSES.assetToken,
        abi: ASSET_TOKEN_ABI,
        functionName: "allowance",
        args: [address!, ADDRESSES.rwaAmm],
      },
    ],
    query: { enabled: !!address },
  });

  const reserves = data?.[0]?.result as [bigint, bigint] | undefined;
  const tokenA = data?.[1]?.result as Address | undefined;
  const tokenB = data?.[2]?.result as Address | undefined;
  const totalLp = data?.[3]?.result as bigint | undefined;
  const userLp = data?.[4]?.result as bigint | undefined;
  const allowanceA = data?.[5]?.result as bigint | undefined;

  return {
    reserves,
    tokenA,
    tokenB,
    totalLp,
    userLp,
    allowanceA,
    refetch,
  };
}
