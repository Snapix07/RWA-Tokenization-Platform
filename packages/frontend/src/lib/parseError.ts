/**
 * Превращает любую wagmi/viem ошибку в человекочитаемую строку.
 */
export function parseError(err: unknown): string {
  if (!err) return "Unknown error occurred.";

  const raw = err instanceof Error ? err.message : String(err);

  // ── Wallet / User ──────────────────────────────────────────────────────────
  if (/user rejected|user denied|rejected the request/i.test(raw))
    return "Transaction rejected in wallet.";

  // ── Balance / Funds ────────────────────────────────────────────────────────
  if (/insufficient funds for gas/i.test(raw)) return "Not enough ETH to cover gas fees.";
  if (/insufficient balance|transfer amount exceeds balance/i.test(raw))
    return "Insufficient token balance.";

  // ── Allowance ──────────────────────────────────────────────────────────────
  if (/allowance|ERC20: transfer amount exceeds allowance/i.test(raw))
    return "Token allowance too low. Please approve first.";

  // ── Contract-specific reverts ──────────────────────────────────────────────
  if (/SlippageExceeded/i.test(raw))
    return "Slippage limit exceeded. Try increasing slippage tolerance or reducing amount.";
  if (/ZeroAmount/i.test(raw)) return "Amount must be greater than zero.";
  if (/InsufficientLiquidity/i.test(raw)) return "Insufficient pool liquidity for this swap.";
  if (/DepositCapExceeded/i.test(raw)) return "Vault deposit cap reached. Try a smaller amount.";
  if (/AccessControl|not authorized|Ownable/i.test(raw))
    return "You don't have permission to perform this action.";
  if (/Paused|paused/i.test(raw)) return "Protocol is paused. Try again later.";
  if (/StalePrice|stale/i.test(raw)) return "Oracle price is stale. Try again in a few minutes.";
  if (/HealthFactorTooLow/i.test(raw)) return "Health factor too low. Repay some debt first.";
  if (/AlreadyVoted/i.test(raw)) return "You have already voted on this proposal.";
  if (/VotingNotActive|ProposalNotActive/i.test(raw))
    return "Voting is not active for this proposal.";
  if (/GovernorInvalidProposalId/i.test(raw)) return "Invalid proposal ID.";
  if (/execution reverted/i.test(raw)) {
    // Extract revert reason if present
    const match = raw.match(/reason: (.+?)(\n|$)/);
    if (match) return `Transaction reverted: ${match[1].trim()}`;
    return "Transaction reverted. Check your inputs.";
  }

  // ── Network ────────────────────────────────────────────────────────────────
  if (/network changed|chain mismatch/i.test(raw))
    return "Network changed. Please stay on Arbitrum Sepolia.";
  if (/timeout|could not fetch|network error/i.test(raw))
    return "Network request timed out. Check your connection.";

  // ── Fallback — trim long RPC noise ─────────────────────────────────────────
  const clean = raw.replace(/Details:.*$/s, "").trim();
  return clean.length > 0 && clean.length < 200
    ? clean
    : "Something went wrong. Check the console for details.";
}
