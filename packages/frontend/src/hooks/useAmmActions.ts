import { useWriteContract, useReadContracts } from "wagmi";
import { parseUnits, maxUint256 } from "viem";
import { type Address } from "viem";
import { ADDRESSES } from "../config/addresses";
import { ASSET_TOKEN_ABI, RWA_AMM_ABI, GOVERNANCE_TOKEN_ABI } from "../config/abis";
import { useTx, type TxStatus } from "./useTx";

export type { TxStatus };

export function useApproveForAmm(tokenAddress: Address) {
  const tx = useTx();
  const { writeContractAsync } = useWriteContract();

  const approve = () =>
    tx.send(() =>
      writeContractAsync({
        address: tokenAddress,
        abi: ASSET_TOKEN_ABI,
        functionName: "approve",
        args: [ADDRESSES.rwaAmm, maxUint256],
        maxFeePerGas: 100_000_000n,
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
        functionName: "swapExactTokensForTokens",
        args: [parseUnits(amountIn, 18), amountOutMin, tokenIn, recipient!],
        maxFeePerGas: 100_000_000n,
      }),
    );

  return { ...tx, swap };
}

export function useAddLiquidity(recipient?: Address) {
  const tx = useTx();
  const { writeContractAsync } = useWriteContract();

  const addLiquidity = (ethbondAmount: string, govAmount: string) =>
    tx.send(() =>
      writeContractAsync({
        address: ADDRESSES.rwaAmm,
        abi: RWA_AMM_ABI,
        functionName: "addLiquidity",
        // Contract: tokenA=GOV, tokenB=ETHBOND — pass GOV first, ETHBOND second
        args: [parseUnits(govAmount, 18), parseUnits(ethbondAmount, 18), 0n, 0n, recipient!],
        maxFeePerGas: 100_000_000n,
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
        maxFeePerGas: 100_000_000n,
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
      {
        address: ADDRESSES.governanceToken,
        abi: GOVERNANCE_TOKEN_ABI,
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
  const allowanceB = data?.[6]?.result as bigint | undefined;

  return {
    reserves,
    tokenA,
    tokenB,
    totalLp,
    userLp,
    allowanceA,
    allowanceB,
    refetch,
  };
}
