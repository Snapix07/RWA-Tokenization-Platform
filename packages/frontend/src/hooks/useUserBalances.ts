import { useReadContracts } from "wagmi";
import { formatUnits } from "viem";
import { type Address } from "viem";
import { ADDRESSES } from "../config/addresses";
import { ASSET_TOKEN_ABI, RWA_VAULT_ABI, RWA_AMM_ABI, GOVERNANCE_TOKEN_ABI } from "../config/abis";

export function useUserBalances(userAddress?: Address) {
  const enabled = !!userAddress;

  const { data, isLoading } = useReadContracts({
    contracts: [
      {
        address: ADDRESSES.assetToken,
        abi: ASSET_TOKEN_ABI,
        functionName: "balanceOf",
        args: [userAddress!],
      },
      {
        address: ADDRESSES.rwaVault,
        abi: RWA_VAULT_ABI,
        functionName: "balanceOf",
        args: [userAddress!],
      },
      {
        address: ADDRESSES.rwaVault,
        abi: RWA_VAULT_ABI,
        functionName: "convertToAssets",
        args: [0n],
      },
      {
        address: ADDRESSES.rwaAmm,
        abi: RWA_AMM_ABI,
        functionName: "balanceOf",
        args: [userAddress!],
      },
      {
        address: ADDRESSES.governanceToken,
        abi: GOVERNANCE_TOKEN_ABI,
        functionName: "balanceOf",
        args: [userAddress!],
      },
      {
        address: ADDRESSES.governanceToken,
        abi: GOVERNANCE_TOKEN_ABI,
        functionName: "getVotes",
        args: [userAddress!],
      },
      {
        address: ADDRESSES.governanceToken,
        abi: GOVERNANCE_TOKEN_ABI,
        functionName: "delegates",
        args: [userAddress!],
      },
    ],
    query: { enabled },
  });

  const assetTokenBal = data?.[0]?.result as bigint | undefined;
  const vaultSharesBal = data?.[1]?.result as bigint | undefined;
  const govBalance = data?.[4]?.result as bigint | undefined;
  const votingPower = data?.[5]?.result as bigint | undefined;
  const delegateTo = data?.[6]?.result as Address | undefined;
  const ammLpBal = data?.[3]?.result as bigint | undefined;

  return {
    isLoading,
    assetToken: assetTokenBal !== undefined ? formatUnits(assetTokenBal, 18) : null,
    vaultShares: vaultSharesBal !== undefined ? formatUnits(vaultSharesBal, 18) : null,
    ammLp: ammLpBal !== undefined ? formatUnits(ammLpBal, 18) : null,
    govBalance: govBalance !== undefined ? formatUnits(govBalance, 18) : null,
    votingPower: votingPower !== undefined ? formatUnits(votingPower, 18) : null,
    delegateTo: delegateTo,
    isSelfDelegated: delegateTo?.toLowerCase() === userAddress?.toLowerCase(),
  };
}
