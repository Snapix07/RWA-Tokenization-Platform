import { useReadContracts, useWriteContract } from "wagmi";
import { type Address } from "viem";
import { ADDRESSES } from "../config/addresses";
import { GOVERNANCE_TOKEN_ABI, RWA_GOVERNOR_ABI } from "../config/abis";
import { useTx, type TxStatus } from "./useTx";

export type { TxStatus };

export function useDelegate() {
  const tx = useTx();
  const { writeContractAsync } = useWriteContract();

  const delegate = (delegatee: Address) =>
    tx.send(() =>
      writeContractAsync({
        address: ADDRESSES.governanceToken,
        abi: GOVERNANCE_TOKEN_ABI,
        functionName: "delegate",
        args: [delegatee],
      }),
    );

  return { ...tx, delegate };
}

export function useCastVote() {
  const tx = useTx();
  const { writeContractAsync } = useWriteContract();

  const castVote = (proposalId: bigint, support: 0 | 1 | 2, reason?: string) =>
    tx.send(() =>
      reason
        ? writeContractAsync({
            address: ADDRESSES.rwaGovernor,
            abi: RWA_GOVERNOR_ABI,
            functionName: "castVoteWithReason",
            args: [proposalId, support, reason],
          })
        : writeContractAsync({
            address: ADDRESSES.rwaGovernor,
            abi: RWA_GOVERNOR_ABI,
            functionName: "castVote",
            args: [proposalId, support],
          }),
    );

  return { ...tx, castVote };
}

export function useGovernanceData(account?: Address) {
  const { data, refetch } = useReadContracts({
    contracts: [
      {
        address: ADDRESSES.governanceToken,
        abi: GOVERNANCE_TOKEN_ABI,
        functionName: "balanceOf",
        args: [account!],
      },
      {
        address: ADDRESSES.governanceToken,
        abi: GOVERNANCE_TOKEN_ABI,
        functionName: "getVotes",
        args: [account!],
      },
      {
        address: ADDRESSES.governanceToken,
        abi: GOVERNANCE_TOKEN_ABI,
        functionName: "delegates",
        args: [account!],
      },
      {
        address: ADDRESSES.governanceToken,
        abi: GOVERNANCE_TOKEN_ABI,
        functionName: "totalSupply",
      },
    ],
    query: { enabled: !!account },
  });

  return {
    govBalance: data?.[0]?.result as bigint | undefined,
    votingPower: data?.[1]?.result as bigint | undefined,
    delegateTo: data?.[2]?.result as Address | undefined,
    totalSupply: data?.[3]?.result as bigint | undefined,
    refetch,
  };
}

export const PROPOSAL_STATES: Record<number, { label: string; badge: string }> = {
  0: { label: "Pending", badge: "badge-pending" },
  1: { label: "Active", badge: "badge-active" },
  2: { label: "Canceled", badge: "badge-defeated" },
  3: { label: "Defeated", badge: "badge-defeated" },
  4: { label: "Succeeded", badge: "badge-executed" },
  5: { label: "Queued", badge: "badge-queued" },
  6: { label: "Expired", badge: "badge-defeated" },
  7: { label: "Executed", badge: "badge-executed" },
};
