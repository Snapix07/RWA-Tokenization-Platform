interface Props {
  fetching?: boolean;
  error?: Error | { message: string } | null;
  label?: string;
}

export function SubgraphBadge({ fetching, error, label = "The Graph" }: Props) {
  const color = error ? "var(--danger)" : fetching ? "var(--warning)" : "var(--success)";

  const text = error ? "Subgraph unavailable" : fetching ? "Syncing…" : `Live · ${label}`;

  return (
    <div style={{ display: "flex", alignItems: "center", gap: 6, fontSize: 12 }}>
      <span
        style={{
          width: 7,
          height: 7,
          borderRadius: "50%",
          background: color,
          flexShrink: 0,
          boxShadow: error || fetching ? "none" : `0 0 6px ${color}`,
        }}
      />
      <span style={{ color: "var(--text)", opacity: 0.7 }}>{text}</span>
    </div>
  );
}
