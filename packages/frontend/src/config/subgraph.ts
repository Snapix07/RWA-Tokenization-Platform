import { request, gql } from "graphql-request";

const SUBGRAPH_URL =
  "https://api.studio.thegraph.com/query/1753381/rwa-tokenezation-platform/version/latest";

const SUBGRAPH_HEADERS = {
  Authorization: "Bearer c6c170a8fe6381c89fcd277b0834e7e6",
};

export async function querySubgraph<T>(
  query: string,
  variables?: Record<string, unknown>,
): Promise<T> {
  return request<T>(SUBGRAPH_URL, query, variables, SUBGRAPH_HEADERS);
}

export const ASSETS_QUERY = gql`
  query GetAssets {
    assetTokens(first: 20, orderBy: deployedAt, orderDirection: desc) {
      id
      assetId
      deterministic
      deployedAt
      deployedBlock
    }
  }
`;

export const VAULT_POSITIONS_QUERY = gql`
  query GetVaultPositions($user: Bytes!) {
    vaultPositions(where: { user: $user }, first: 10) {
      id
      vault
      totalDeposited
      totalWithdrawn
      sharesBalance
      lastUpdated
    }
  }
`;

export const AMM_SWAPS_QUERY = gql`
  query GetRecentSwaps {
    ammSwaps(first: 20, orderBy: timestamp, orderDirection: desc) {
      id
      sender
      tokenIn
      amountIn
      amountOut
      reserveAAfter
      reserveBAfter
      timestamp
    }
  }
`;

export const GOVERNANCE_PROPOSALS_QUERY = gql`
  query GetProposals {
    governanceProposals(first: 20, orderBy: createdAt, orderDirection: desc) {
      id
      proposalId
      proposer
      targets
      values
      calldatas
      description
      forVotes
      againstVotes
      abstainVotes
      voteStart
      voteEnd
      state
      etaSeconds
      createdAt
    }
  }
`;

export interface SubgraphAsset {
  id: string;
  assetId: string;
  deterministic: boolean;
  deployedAt: string;
  deployedBlock: string;
}

export interface SubgraphVaultPosition {
  id: string;
  vault: string;
  totalDeposited: string;
  totalWithdrawn: string;
  sharesBalance: string;
  lastUpdated: string;
}

export interface SubgraphSwap {
  id: string;
  sender: string;
  tokenIn: string;
  amountIn: string;
  amountOut: string;
  reserveAAfter: string;
  reserveBAfter: string;
  timestamp: string;
}

export interface SubgraphProposal {
  id: string;
  proposalId: string;
  proposer: string;
  targets: string[];
  values: string[];
  calldatas: string[];
  description: string;
  forVotes: string;
  againstVotes: string;
  abstainVotes: string;
  voteStart: string;
  voteEnd: string;
  state: number;
  etaSeconds: string | null;
  createdAt: string;
}
