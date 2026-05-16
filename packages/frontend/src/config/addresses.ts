import { type Address } from "viem";

export const ADDRESSES = {
  governanceToken: "0x57B0e45C40CCE6248a102Cdf8612Cdc683Cf3Fd9" as Address,
  oracleAdapter: "0x213B4519E7a59Bd2BEEDde148B8b6fFFCE5dEB53" as Address,
  assetNFT: "0x88AbE0eB4Beb185c3e63BCD58892758C9f0ac3D6" as Address,
  assetToken: "0xBE60c53E15328b18E82E7204fbECA45e11628caa" as Address,
  assetFactory: "0x0d41539C9B43cd675dEBBC3dB8754e26ec274eDF" as Address,
  rwaVault: "0xFbECEB9447925e0c2e433f5eD674F7110AF67018" as Address,
  rwaAmm: "0x658eD17F2686A652ACC89162c7aA99b957e7938E" as Address,
  timelockController: "0x1C9e29A66561B1533578cFc27AB0A4cB7F740c8e" as Address,
  rwaGovernor: "0x091858adb6f82c323c4B4d1b0aA59Cec953B9E75" as Address,
} as const;
