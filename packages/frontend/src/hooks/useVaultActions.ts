import { useReadContract, useWriteContract } from "wagmi";
import { parseUnits, maxUint256 } from "viem";
import { type Address } from "viem";
import { ADDRESSES } from "../config/addresses";
import { ASSET_TOKEN_ABI, RWA_VAULT_ABI } from "../config/abis";
import { useTx, type TxStatus } from "./useTx";

export type { TxStatus };
export function useApproveAssetToken(owner?: Address) {
  const tx = useTx();
  const { writeContractAsync } = useWriteContract();

  const { data: allowance, refetch: refetchAllowance } = useReadContract({
    address: ADDRESSES.assetToken,
    abi: ASSET_TOKEN_ABI,
    functionName: "allowance",
    args: [owner!, ADDRESSES.rwaVault],
    query: { enabled: !!owner },
  });

  const approve = () =>
    tx.send(() =>
      writeContractAsync({
        address: ADDRESSES.assetToken,
        abi: ASSET_TOKEN_ABI,
        functionName: "approve",
        args: [ADDRESSES.rwaVault, maxUint256],
        maxFeePerGas: 100_000_000n,
      }),
    );

  return { ...tx, approve, allowance, refetchAllowance };
}

export function useVaultDeposit(receiver?: Address) {
  const tx = useTx();
  const { writeContractAsync } = useWriteContract();

  const deposit = (assets: string) =>
    tx.send(() =>
      writeContractAsync({
        address: ADDRESSES.rwaVault,
        abi: RWA_VAULT_ABI,
        functionName: "deposit",
        args: [parseUnits(assets, 18), receiver!],
        maxFeePerGas: 100_000_000n,
      }),
    );

  return { ...tx, deposit };
}

export function useVaultRedeem(owner?: Address) {
  const tx = useTx();
  const { writeContractAsync } = useWriteContract();

  const redeem = (shares: string) =>
    tx.send(() =>
      writeContractAsync({
        address: ADDRESSES.rwaVault,
        abi: RWA_VAULT_ABI,
        functionName: "redeem",
        args: [parseUnits(shares, 18), owner!, owner!],
        maxFeePerGas: 100_000_000n,
      }),
    );

  return { ...tx, redeem };
}

export function useMintAssetToken() {
  const tx = useTx();
  const { writeContractAsync } = useWriteContract();

  const mint = (to: Address, amount: string) =>
    tx.send(() =>
      writeContractAsync({
        address: ADDRESSES.assetToken,
        abi: ASSET_TOKEN_ABI,
        functionName: "mint",
        args: [to, parseUnits(amount, 18)],
        maxFeePerGas: 100_000_000n,
      }),
    );

  return { ...tx, mint };
}
