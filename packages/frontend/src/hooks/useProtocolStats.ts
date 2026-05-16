import { useReadContracts } from "wagmi";
import { formatUnits } from "viem";
import { ADDRESSES } from "../config/addresses";
import { ASSET_TOKEN_ABI, RWA_VAULT_ABI, RWA_AMM_ABI } from "../config/abis";

export function useProtocolStats() {
  const { data, isLoading } = useReadContracts({
    contracts: [
      {
        address: ADDRESSES.assetToken,
        abi: ASSET_TOKEN_ABI,
        functionName: "totalSupply",
      },
      {
        address: ADDRESSES.assetToken,
        abi: ASSET_TOKEN_ABI,
        functionName: "getAssetPrice",
      },
      {
        address: ADDRESSES.assetToken,
        abi: ASSET_TOKEN_ABI,
        functionName: "symbol",
      },
      {
        address: ADDRESSES.assetToken,
        abi: ASSET_TOKEN_ABI,
        functionName: "paused",
      },
      // Vault
      {
        address: ADDRESSES.rwaVault,
        abi: RWA_VAULT_ABI,
        functionName: "totalAssets",
      },
      {
        address: ADDRESSES.rwaVault,
        abi: RWA_VAULT_ABI,
        functionName: "totalSupply",
      },
      {
        address: ADDRESSES.rwaVault,
        abi: RWA_VAULT_ABI,
        functionName: "navPerShare",
      },
      // AMM
      {
        address: ADDRESSES.rwaAmm,
        abi: RWA_AMM_ABI,
        functionName: "getReserves",
      },
      {
        address: ADDRESSES.rwaAmm,
        abi: RWA_AMM_ABI,
        functionName: "totalSupply",
      },
    ],
  });

  const totalSupply = data?.[0]?.result as bigint | undefined;
  const assetPrice = data?.[1]?.result as [bigint, bigint] | undefined;
  const symbol = data?.[2]?.result as string | undefined;
  const paused = data?.[3]?.result as boolean | undefined;
  const vaultAssets = data?.[4]?.result as bigint | undefined;
  const vaultShares = data?.[5]?.result as bigint | undefined;
  const navPerShare = data?.[6]?.result as bigint | undefined;
  const reserves = data?.[7]?.result as [bigint, bigint] | undefined;
  const ammTotalLp = data?.[8]?.result as bigint | undefined;

  return {
    isLoading,
    token: {
      symbol: symbol ?? "ETHBOND",
      totalSupply: totalSupply !== undefined ? formatUnits(totalSupply, 18) : null,
      price: assetPrice !== undefined ? formatUnits(assetPrice[0], 18) : null,
      updatedAt: assetPrice !== undefined ? Number(assetPrice[1]) : null,
      paused: paused ?? false,
    },
    vault: {
      totalAssets: vaultAssets !== undefined ? formatUnits(vaultAssets, 18) : null,
      totalShares: vaultShares !== undefined ? formatUnits(vaultShares, 18) : null,
      navPerShare: navPerShare !== undefined ? formatUnits(navPerShare, 18) : null,
    },
    amm: {
      reserveA: reserves !== undefined ? formatUnits(reserves[0], 18) : null,
      reserveB: reserves !== undefined ? formatUnits(reserves[1], 18) : null,
      totalLp: ammTotalLp !== undefined ? formatUnits(ammTotalLp, 18) : null,
    },
  };
}
