import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useRef,
  useState,
  type ReactNode,
} from "react";

export type ToastType = "success" | "error" | "warning" | "info";

interface Toast {
  id: number;
  type: ToastType;
  title: string;
  message?: string;
  duration?: number;
}

interface ToastContextValue {
  addToast: (toast: Omit<Toast, "id">) => void;
  success: (title: string, message?: string) => void;
  error: (title: string, message?: string) => void;
  warning: (title: string, message?: string) => void;
  info: (title: string, message?: string) => void;
}

const ToastContext = createContext<ToastContextValue | null>(null);

export function useToast(): ToastContextValue {
  const ctx = useContext(ToastContext);
  if (!ctx) throw new Error("useToast must be used within <ToastProvider>");
  return ctx;
}

const ICONS: Record<ToastType, string> = {
  success: "✅",
  error: "❌",
  warning: "⚠️",
  info: "ℹ️",
};

const COLORS: Record<ToastType, { bg: string; border: string; color: string }> = {
  success: {
    bg: "var(--success-bg)",
    border: "var(--success)",
    color: "var(--success)",
  },
  error: {
    bg: "var(--danger-bg)",
    border: "var(--danger)",
    color: "var(--danger)",
  },
  warning: {
    bg: "var(--warning-bg)",
    border: "var(--warning)",
    color: "var(--warning)",
  },
  info: {
    bg: "var(--accent-bg)",
    border: "var(--accent)",
    color: "var(--accent)",
  },
};

function ToastItem({ toast, onRemove }: { toast: Toast; onRemove: (id: number) => void }) {
  const [visible, setVisible] = useState(false);
  const [leaving, setLeaving] = useState(false);
  const timerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  const colors = COLORS[toast.type];

  const dismiss = useCallback(() => {
    setLeaving(true);
    setTimeout(() => onRemove(toast.id), 300);
  }, [onRemove, toast.id]);

  useEffect(() => {
    const t = setTimeout(() => setVisible(true), 10);
    return () => clearTimeout(t);
  }, []);

  useEffect(() => {
    const duration = toast.duration ?? 5000;
    const id = setTimeout(dismiss, duration);
    timerRef.current = id;
    return () => {
      clearTimeout(id);
    };
  }, [dismiss, toast.duration]);
  return (
    <div
      style={{
        display: "flex",
        alignItems: "flex-start",
        gap: 10,
        padding: "12px 14px",
        borderRadius: 10,
        border: `1px solid ${colors.border}`,
        background: "var(--bg-surface)",
        boxShadow: "0 4px 20px rgba(0,0,0,0.18)",
        minWidth: 280,
        maxWidth: 360,
        cursor: "pointer",
        userSelect: "none",
        opacity: visible && !leaving ? 1 : 0,
        transform: visible && !leaving ? "translateX(0)" : "translateX(24px)",
        transition: "opacity 0.3s ease, transform 0.3s ease",
        position: "relative",
        overflow: "hidden",
      }}
      onClick={dismiss}
    >
      <div
        style={{
          position: "absolute",
          left: 0,
          top: 0,
          bottom: 0,
          width: 4,
          background: colors.border,
          borderRadius: "10px 0 0 10px",
        }}
      />

      <span style={{ fontSize: 16, marginLeft: 6, flexShrink: 0 }}>{ICONS[toast.type]}</span>

      <div style={{ flex: 1, minWidth: 0 }}>
        <div
          style={{
            fontSize: 13,
            fontWeight: 700,
            color: colors.color,
            marginBottom: toast.message ? 3 : 0,
            lineHeight: 1.3,
          }}
        >
          {toast.title}
        </div>
        {toast.message && (
          <div
            style={{
              fontSize: 12,
              color: "var(--text)",
              lineHeight: 1.4,
              wordBreak: "break-word",
            }}
          >
            {toast.message}
          </div>
        )}
      </div>

      <button
        style={{
          background: "none",
          border: "none",
          color: "var(--text)",
          fontSize: 16,
          cursor: "pointer",
          padding: 0,
          lineHeight: 1,
          flexShrink: 0,
          opacity: 0.5,
        }}
        onClick={(e) => {
          e.stopPropagation();
          dismiss();
        }}
        aria-label="Dismiss"
      >
        ×
      </button>

      <div
        style={{
          position: "absolute",
          bottom: 0,
          left: 0,
          height: 2,
          background: colors.border,
          opacity: 0.4,
          animation: `toast-progress ${toast.duration ?? 5000}ms linear forwards`,
        }}
      />
    </div>
  );
}

let _nextId = 1;

export function ToastProvider({ children }: { children: ReactNode }) {
  const [toasts, setToasts] = useState<Toast[]>([]);

  const addToast = useCallback((t: Omit<Toast, "id">) => {
    setToasts((prev) => [...prev, { ...t, id: _nextId++ }]);
  }, []);

  const removeToast = useCallback((id: number) => {
    setToasts((prev) => prev.filter((t) => t.id !== id));
  }, []);

  const success = useCallback(
    (title: string, message?: string) => addToast({ type: "success", title, message }),
    [addToast],
  );
  const error = useCallback(
    (title: string, message?: string) =>
      addToast({ type: "error", title, message, duration: 7000 }),
    [addToast],
  );
  const warning = useCallback(
    (title: string, message?: string) => addToast({ type: "warning", title, message }),
    [addToast],
  );
  const info = useCallback(
    (title: string, message?: string) => addToast({ type: "info", title, message }),
    [addToast],
  );

  return (
    <ToastContext.Provider value={{ addToast, success, error, warning, info }}>
      {children}

      <div
        style={{
          position: "fixed",
          bottom: 24,
          right: 24,
          display: "flex",
          flexDirection: "column",
          gap: 10,
          zIndex: 9999,
          pointerEvents: "none",
        }}
      >
        {toasts.map((t) => (
          <div key={t.id} style={{ pointerEvents: "all" }}>
            <ToastItem toast={t} onRemove={removeToast} />
          </div>
        ))}
      </div>

      <style>{`
        @keyframes toast-progress {
          from { width: 100%; }
          to   { width: 0%; }
        }
      `}</style>
    </ToastContext.Provider>
  );
}
