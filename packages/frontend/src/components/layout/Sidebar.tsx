import { NavLink } from "react-router-dom";

const NAV_ITEMS = [
  { to: "/", icon: "📊", label: "Dashboard" },
  { to: "/vault", icon: "🏛️", label: "Vault" },
  { to: "/amm", icon: "🔄", label: "AMM Swap" },
  { to: "/governance", icon: "🗳️", label: "Governance" },
];

export function Sidebar() {
  return (
    <aside className="sidebar">
      <span className="sidebar__section-label">Protocol</span>

      {NAV_ITEMS.map(({ to, icon, label }) => (
        <NavLink
          key={to}
          to={to}
          end={to === "/"}
          className={({ isActive }) => "sidebar__link" + (isActive ? " active" : "")}
        >
          <span className="sidebar__link-icon">{icon}</span>
          {label}
        </NavLink>
      ))}

      <span className="sidebar__section-label" style={{ marginTop: "auto" }}>
        Links
      </span>
      <a
        href="https://sepolia.arbiscan.io"
        target="_blank"
        rel="noreferrer"
        className="sidebar__link"
      >
        <span className="sidebar__link-icon">🔍</span>
        Arbiscan
      </a>
      <a
        href="https://subgraph.satsuma-prod.com"
        target="_blank"
        rel="noreferrer"
        className="sidebar__link"
      >
        <span className="sidebar__link-icon">📈</span>
        Subgraph
      </a>
    </aside>
  );
}
