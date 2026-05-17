import { BrowserRouter, Routes, Route } from "react-router-dom";
import { Navbar } from "./components/layout/Navbar";
import { Sidebar } from "./components/layout/Sidebar";
import { NetworkGuard } from "./components/layout/NetworkGuard";
import { ToastProvider } from "./components/Toast";
import { DashboardPage } from "./pages/DashboardPage";
import { VaultPage } from "./pages/VaultPage";
import { AmmPage } from "./pages/AmmPage";
import { GovernancePage } from "./pages/GovernancePage";

export default function App() {
  return (
    <BrowserRouter>
      <ToastProvider>
        {" "}
        <Navbar />
        <div className="layout">
          <Sidebar />
          <main className="main-content">
            <NetworkGuard />
            <Routes>
              <Route path="/" element={<DashboardPage />} />
              <Route path="/vault" element={<VaultPage />} />
              <Route path="/amm" element={<AmmPage />} />
              <Route path="/governance" element={<GovernancePage />} />
            </Routes>
          </main>
        </div>
      </ToastProvider>{" "}
    </BrowserRouter>
  );
}
