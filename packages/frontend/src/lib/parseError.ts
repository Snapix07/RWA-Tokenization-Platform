export function parseError(err: unknown): string {
  if (!err) return "Unknown error occurred.";

  const raw = err instanceof Error ? err.message : String(err);

  if (/user rejected|user denied|rejected the request/i.test(raw))
    return "Transaction rejected in wallet.";

  if (/insufficient funds for gas/i.test(raw)) return "Not enough ETH to cover gas fees.";
  if (/insufficient balance|transfer amount exceeds balance/i.test(raw))
    return "Insufficient token balance.";

  if (/allowance|ERC20: transfer amount exceeds allowance/i.test(raw))
    return "Token allowance too low. Please approve first.";

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
  if (/GovernorNonexistentProposal/i.test(raw))
    return "Proposal not found — parameters (targets/calldatas/description) don't match the original.";
  if (/GovernorUnexpectedProposalState/i.test(raw))
    return "Proposal is not in the expected state (check if voting period has ended).";
  if (/TimelockController.*already scheduled/i.test(raw))
    return "This operation is already scheduled in the Timelock.";
  if (/TimelockUnexpectedOperationState/i.test(raw))
    return "Timelock not ready — wait for the 1-min delay to pass after queuing, then try again.";
  if (/execution reverted/i.test(raw)) {
    const match = raw.match(/reason: (.+?)(\n|$)/);
    if (match) return `Transaction reverted: ${match[1].trim()}`;
    const detailMatch = raw.match(/Error: (.+?)(\n|$)/);
    if (detailMatch) return `Reverted: ${detailMatch[1].trim()}`;
    return "Transaction reverted. Check your inputs.";
  }

  if (/network changed|chain mismatch/i.test(raw))
    return "Network changed. Please stay on Arbitrum Sepolia.";
  if (/timeout|could not fetch|network error/i.test(raw))
    return "Network request timed out. Check your connection.";

  if (
    err &&
    typeof err === "object" &&
    "name" in err &&
    (err as { name: string }).name === "ContractFunctionRevertedError"
  ) {
    const vErr = err as { data?: { errorName?: string; args?: unknown[] }; shortMessage?: string };
    if (vErr.data?.errorName) {
      const args = vErr.data.args ? ` (${JSON.stringify(vErr.data.args)})` : "";
      return `Contract error: ${vErr.data.errorName}${args}`;
    }
    if (vErr.shortMessage) return vErr.shortMessage;
  }

  if (raw.startsWith("Parameter mismatch!") || raw.startsWith("Hash mismatch")) {
    return raw.slice(0, 500);
  }

  const clean = raw.replace(/Details:.*$/s, "").trim();
  return clean.length > 0 && clean.length < 300
    ? clean
    : "Something went wrong. Check the console for details.";
}
