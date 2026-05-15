import { createClient, cacheExchange, fetchExchange } from "urql";

const SUBGRAPH_URL =
  "https://api.studio.thegraph.com/query/bsqj33s45/rwa-tokenization-platform/version/latest";

export const subgraphClient = createClient({
  url: SUBGRAPH_URL,
  exchanges: [cacheExchange, fetchExchange],
});
