> Seam review entry point. Pending approval.

# 03 — Tools, sources, and effect policy

## Briefing

Tools.Executor uses core Exec and normalizes tool results. Runtime.ToolAttempt adds Profile policy, retry, and interception. Effects remain proposals until their owner applies them through core contracts. ToolSource validates inert declarations, including subagent and handoff; this does not implement dynamic discovery or delegation.

This seam retains the complete target, not only current functionality. Detailed
current evidence and gaps are in [alignment](alignment.md); proposed contracts
and stable requirement IDs are in [design](design.md).

## Why this seam exists

- Owner: ToolCatalog, ToolAdapter, ToolSource, ToolContext, ToolInterceptor, ToolResult, Tools.Executor, and Effects.
- Owns: tools, sources, and effect policy within [the package architecture](../ARCHITECTURE.md).
- Does not own: contracts assigned to other seams or private lower-package internals.

## Current and target state

| Area | Current | Target |
| --- | --- | --- |
| Architecture | The module and state ownership above is the code baseline | Preserve static and advanced tool sources, provider-native tools, interception, approvals, bounded results, and replay-aware effect semantics. Separate tool policy from batch scheduling and Agent commit. |
| Evidence | Linked example and boundary tests cover specific cases | Direct requirement-level acceptance, including advanced paths |
| Compatibility | Current APIs remain authoritative | Explicit migration for approved contract changes |

## Major gaps and work remaining

| Gap | Why it matters | Required outcome | Owner |
| --- | --- | --- | --- |
| [TLS-GAP-001](alignment.md#gap-register) | Static catalog validation exists; dynamic sources are not proved executable by their schema declarations. | Retain source discovery, trust, collision, and precedence requirements. | 03; dependencies below |
| [TLS-GAP-002](alignment.md#gap-register) | A general prebuilt snapshot contract is not established. TLS-REQ-011 is actually the provider-native/local boundary. | Keep snapshot proposal as a design decision, not evidence for the wrong requirement. | 03; dependencies below |
| [TLS-GAP-003](alignment.md#gap-register) | ToolResult normalization exists. Target portability and error guarantees need all return-form cases. | Review result, error, and effect cases against TLS-REQ-012/013/014. | 03; dependencies below |
| [TLS-GAP-004](alignment.md#gap-register) | ToolsFlow uses Map; NextBatch partitions bounded batches. The target explicitly requires a Map max_concurrency setting. | Decide whether bounded batching satisfies the intended guarantee or migrate the Flow declaration. | 03; dependencies below |
| [TLS-GAP-005](alignment.md#gap-register) | Effect proposals and idempotency policy exist, but general durable deduplication does not. | Retain replay-safety work in 11. Correct old references: effect proposals are TLS-REQ-014. | 03; dependencies below |
| [TLS-GAP-006](alignment.md#gap-register) | ToolAttempt still performs bounded sleep before a continuation. | Resolve TLS-REQ-022 with the execution seam. | 03; dependencies below |

## Decisions requested

Define executable source contracts separately from declaration support; settle retry delay and stable effect identity with 04/11.

The [target design decisions](design.md#open-design-decisions) remain pending.
No advanced capability is removed by this reconciliation.

## Dependencies

- Prerequisites: [01 Canonical interaction and AI values](../01_ai_values/alignment.md).
- Dependents: 04, 08, 09.
- Blockers: unresolved target and prerequisite decisions. Current implementation can be inspected without treating proposed contracts as approved.

## Documents

- [Target design](design.md).
- [Current evidence and alignment](alignment.md).
- [Overall architecture](../ARCHITECTURE.md).
