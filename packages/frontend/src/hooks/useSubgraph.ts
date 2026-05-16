import { useQuery } from "@tanstack/react-query";
import {
  querySubgraph,
  AMM_SWAPS_QUERY,
  VAULT_POSITIONS_QUERY,
  GOVERNANCE_PROPOSALS_QUERY,
  ASSETS_QUERY,
  type SubgraphSwap,
  type SubgraphVaultPosition,
  type SubgraphProposal,
  type SubgraphAsset,
} from "../config/subgraph";

export function useRecentSwaps(count = 10) {
  const { data, isLoading, error } = useQuery({
    queryKey: ["subgraph-swaps", count],
    queryFn: () => querySubgraph<{ ammSwaps: SubgraphSwap[] }>(AMM_SWAPS_QUERY),
    staleTime: 30_000,
  });

  return {
    swaps: (data?.ammSwaps ?? []).slice(0, count),
    fetching: isLoading,
    error: error as Error | null,
  };
}

export function useUserVaultPositions(user?: string) {
  const { data, isLoading, error } = useQuery({
    queryKey: ["subgraph-vault-positions", user],
    queryFn: () =>
      querySubgraph<{ vaultPositions: SubgraphVaultPosition[] }>(VAULT_POSITIONS_QUERY, {
        user: user?.toLowerCase(),
      }),
    enabled: !!user,
    staleTime: 30_000,
  });

  return {
    positions: data?.vaultPositions ?? [],
    fetching: isLoading,
    error: error as Error | null,
  };
}

export function useAllProposals() {
  const { data, isLoading, error } = useQuery({
    queryKey: ["subgraph-proposals"],
    queryFn: () =>
      querySubgraph<{ governanceProposals: SubgraphProposal[] }>(GOVERNANCE_PROPOSALS_QUERY),
    staleTime: 60_000,
  });

  return {
    proposals: data?.governanceProposals ?? [],
    fetching: isLoading,
    error: error as Error | null,
  };
}

export function useActiveProposals() {
  const { proposals, fetching, error } = useAllProposals();

  return {
    proposals: proposals.filter((p) => p.state === 1),
    fetching,
    error,
  };
}

export function useAssetTokens() {
  const { data, isLoading, error } = useQuery({
    queryKey: ["subgraph-assets"],
    queryFn: () => querySubgraph<{ assetTokens: SubgraphAsset[] }>(ASSETS_QUERY),
    staleTime: 120_000,
  });

  return {
    tokens: data?.assetTokens ?? [],
    fetching: isLoading,
    error: error as Error | null,
  };
}
