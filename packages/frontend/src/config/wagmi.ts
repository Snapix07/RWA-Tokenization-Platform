import { getDefaultConfig } from "@rainbow-me/rainbowkit";
import { arbitrumSepolia } from "viem/chains";

export const wagmiConfig = getDefaultConfig({
  appName: "RWA Tokenization Platform",
  projectId: "2a0d816f728ff0ccc76fcccc122759d8",
  chains: [arbitrumSepolia],
  ssr: false,
});

export { arbitrumSepolia };
