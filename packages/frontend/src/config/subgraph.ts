import { createClient, cacheExchange, fetchExchange } from "urql";

const SUBGRAPH_URL =
  "https://api.studio.thegraph.com/query/1753381/rwa-tokenezation-platform/version/latest";

export const subgraphClient = createClient({
  url: SUBGRAPH_URL,
  exchanges: [cacheExchange, fetchExchange],
});
