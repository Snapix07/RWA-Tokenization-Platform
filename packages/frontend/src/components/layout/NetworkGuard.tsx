import { useAccount, useSwitchChain } from "wagmi";
import { arbitrumSepolia } from "../../config/wagmi";

export function NetworkGuard() {
  const { isConnected, chainId } = useAccount();
  const { switchChain, isPending } = useSwitchChain();

  if (!isConnected) return null;
  if (chainId === arbitrumSepolia.id) return null;

  return (
    <div className="network-banner">
      <span className="network-banner__text">
        ⚠️ Wrong network detected. Please switch to <strong>Arbitrum Sepolia</strong>.
      </span>
      <button
        className="network-banner__btn"
        disabled={isPending}
        onClick={() => switchChain({ chainId: arbitrumSepolia.id })}
      >
        {isPending ? "Switching…" : "Switch Network"}
      </button>
    </div>
  );
}
