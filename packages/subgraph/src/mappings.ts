import { BigInt, Bytes } from "@graphprotocol/graph-ts";
import {
  TokenDeployed as TokenDeployedEvent,
} from "../generated/AssetFactory/AssetFactory";
import {
  Deposit as DepositEvent,
  Withdraw as WithdrawEvent,
} from "../generated/RWAVault/RWAVault";
import {
  Swap as SwapEvent,
  Sync as SyncEvent,
} from "../generated/RWAAMM/RWAAMM";
import {
  ProposalCreated as ProposalCreatedEvent,
  VoteCast as VoteCastEvent,
  ProposalQueued as ProposalQueuedEvent,
  ProposalExecuted as ProposalExecutedEvent,
  ProposalCanceled as ProposalCanceledEvent,
} from "../generated/RWAGovernor/RWAGovernor";
import {
  AssetToken,
  VaultPosition,
  AmmSwap,
  GovernanceProposal,
  ProposalVote,
} from "../generated/schema";

// ---------------------------------------------------------------------------
// AssetFactory — handleTokenDeployed
// ---------------------------------------------------------------------------

export function handleTokenDeployed(event: TokenDeployedEvent): void {
  let id = event.params.proxy.toHexString();
  let entity = new AssetToken(id);
  entity.assetId = event.params.assetId;
  entity.deterministic = event.params.deterministic;
  entity.deployedAt = event.block.timestamp;
  entity.deployedBlock = event.block.number;
  entity.save();
}

// ---------------------------------------------------------------------------
// RWAVault — handleDeposit / handleWithdraw
// ---------------------------------------------------------------------------

function vaultPositionId(vault: Bytes, user: Bytes): string {
  return vault.toHexString() + "-" + user.toHexString();
}

export function handleDeposit(event: DepositEvent): void {
  let id = vaultPositionId(event.address, event.params.owner);
  let pos = VaultPosition.load(id);
  if (pos == null) {
    pos = new VaultPosition(id);
    pos.vault = event.address;
    pos.user = event.params.owner;
    pos.totalDeposited = BigInt.zero();
    pos.totalWithdrawn = BigInt.zero();
    pos.sharesBalance = BigInt.zero();
    pos.assetToken = null;
  }
  pos.totalDeposited = pos.totalDeposited.plus(event.params.assets);
  pos.sharesBalance = pos.sharesBalance.plus(event.params.shares);
  pos.lastUpdated = event.block.timestamp;
  pos.save();
}

export function handleWithdraw(event: WithdrawEvent): void {
  let id = vaultPositionId(event.address, event.params.owner);
  let pos = VaultPosition.load(id);
  if (pos == null) return; // should always exist, guard for safety
  pos.totalWithdrawn = pos.totalWithdrawn.plus(event.params.assets);
  pos.sharesBalance = pos.sharesBalance.minus(event.params.shares);
  pos.lastUpdated = event.block.timestamp;
  pos.save();
}

// ---------------------------------------------------------------------------
// RWAAMM — handleSwap / handleSync
// ---------------------------------------------------------------------------

// Latest reserves stored in a singleton — keyed by AMM address
let _reserveA: BigInt = BigInt.zero();
let _reserveB: BigInt = BigInt.zero();

export function handleSync(event: SyncEvent): void {
  _reserveA = event.params.reserveA;
  _reserveB = event.params.reserveB;
}

export function handleSwap(event: SwapEvent): void {
  let id = event.transaction.hash.toHexString() + "-" + event.logIndex.toString();
  let swap = new AmmSwap(id);
  swap.amm = event.address;
  swap.sender = event.params.sender;
  swap.tokenIn = event.params.tokenIn;
  swap.amountIn = event.params.amountIn;
  swap.amountOut = event.params.amountOut;
  swap.reserveAAfter = _reserveA;
  swap.reserveBAfter = _reserveB;
  swap.timestamp = event.block.timestamp;
  swap.blockNumber = event.block.number;
  swap.save();
}

// ---------------------------------------------------------------------------
// RWAGovernor — proposal lifecycle
// ---------------------------------------------------------------------------

export function handleProposalCreated(event: ProposalCreatedEvent): void {
  let id = event.params.proposalId.toString();
  let proposal = new GovernanceProposal(id);
  proposal.proposalId = event.params.proposalId;
  proposal.proposer = event.params.proposer;
  proposal.targets = changetype<Bytes[]>(event.params.targets);
  proposal.values = event.params.values;
  proposal.calldatas = event.params.calldatas;
  proposal.description = event.params.description;
  proposal.voteStart = event.params.voteStart;
  proposal.voteEnd = event.params.voteEnd;
  proposal.state = 0; // Pending
  proposal.forVotes = BigInt.zero();
  proposal.againstVotes = BigInt.zero();
  proposal.abstainVotes = BigInt.zero();
  proposal.createdAt = event.block.timestamp;
  proposal.save();
}

export function handleVoteCast(event: VoteCastEvent): void {
  let proposalId = event.params.proposalId.toString();
  let proposal = GovernanceProposal.load(proposalId);
  if (proposal == null) return;

  // Upsert vote record
  let voteId = proposalId + "-" + event.params.voter.toHexString();
  let vote = new ProposalVote(voteId);
  vote.proposal = proposalId;
  vote.voter = event.params.voter;
  vote.support = event.params.support;
  vote.weight = event.params.weight;
  vote.reason = event.params.reason;
  vote.save();

  // Tally
  if (event.params.support == 1) {
    proposal.forVotes = proposal.forVotes.plus(event.params.weight);
  } else if (event.params.support == 0) {
    proposal.againstVotes = proposal.againstVotes.plus(event.params.weight);
  } else {
    proposal.abstainVotes = proposal.abstainVotes.plus(event.params.weight);
  }
  proposal.state = 1; // Active
  proposal.save();
}

export function handleProposalQueued(event: ProposalQueuedEvent): void {
  let proposal = GovernanceProposal.load(event.params.proposalId.toString());
  if (proposal == null) return;
  proposal.state = 5; // Queued
  proposal.etaSeconds = event.params.etaSeconds;
  proposal.save();
}

export function handleProposalExecuted(event: ProposalExecutedEvent): void {
  let proposal = GovernanceProposal.load(event.params.proposalId.toString());
  if (proposal == null) return;
  proposal.state = 7; // Executed
  proposal.executedAt = event.block.timestamp;
  proposal.save();
}

export function handleProposalCanceled(event: ProposalCanceledEvent): void {
  let proposal = GovernanceProposal.load(event.params.proposalId.toString());
  if (proposal == null) return;
  proposal.state = 2; // Canceled
  proposal.save();
}
