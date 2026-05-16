import { createConfig, http } from "wagmi";
import { arbitrumSepolia } from "viem/chains";
import { connectorsForWallets } from "@rainbow-me/rainbowkit";
import { metaMaskWallet, injectedWallet } from "@rainbow-me/rainbowkit/wallets";

const connectors = connectorsForWallets(
  [
    {
      groupName: "Recommended",
      wallets: [metaMaskWallet, injectedWallet],
    },
  ],
  {
    appName: "RWA Tokenization Platform",
    projectId: "dummy",
  },
);

export const wagmiConfig = createConfig({
  chains: [arbitrumSepolia],
  connectors,
  transports: {
    [arbitrumSepolia.id]: http("https://sepolia-rollup.arbitrum.io/rpc"),
  },
});

export { arbitrumSepolia };
