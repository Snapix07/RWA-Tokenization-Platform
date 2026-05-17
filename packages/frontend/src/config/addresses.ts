import { getAddress } from "viem";

export const ADDRESSES = {
  governanceToken: getAddress("0xB4A3b4bf36168850Bd9Dd7baF75C8599879f59b7"),
  oracleAdapter: getAddress("0xCAddFBa45BE20627f8Ab736d26551A09C1A50BA1"),
  assetNFT: getAddress("0xE558BC297b1D9735ff5B4d6ff09D29a68c94f5B8"),
  assetToken: getAddress("0xF6B92C7500A7AcBA38f1A286f4123D4e36627B8D"),
  assetFactory: getAddress("0xfC83C440Bd3Cd8b6FC5ABB5f1E7a67f38F3A0f7d"),
  rwaVault: getAddress("0x7d71cAa220df8aFe473393Ab646e0fF11ce3cB82"),
  rwaAmm: getAddress("0xd56101f885ADe6B501C47DA940d8EFC972666554"),
  timelockController: getAddress("0xaBa69A2E79d6626DCf9774daDab6BF606df197F7"),
  rwaGovernor: getAddress("0x4DAc8bc9d16665D4AED79bfc62c22dD7CA4Fa072"),
} as const;
