import { ConnectButton } from "@rainbow-me/rainbowkit";
import { Link } from "react-router-dom";

export function Navbar() {
  return (
    <header className="navbar">
      <Link to="/" className="navbar__brand">
        <span>🏦</span>
        <span>RWA Platform</span>
        <span className="navbar__brand-badge">Arbitrum Sepolia</span>
      </Link>

      <div className="navbar__right">
        <ConnectButton accountStatus="avatar" chainStatus="icon" showBalance={false} />
      </div>
    </header>
  );
}
