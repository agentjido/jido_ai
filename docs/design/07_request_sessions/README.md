> Seam review entry point. This document is pending approval.

# 07 — Request sessions and active input

## Briefing

The V3 branch has request handles, portable request records, streams, cancellation, and steering. The target is one AI request lifecycle for authored Agents and standalone use. The main change is to leave process, admission, and commit mechanics in core Jido while this seam owns request policy and user controls.

## Why this seam exists

- Owner: Session, Request, PendingInput, and public request API modules.
- Owns: Request identity, records, status, await, stream, sync, cancellation, steering, settlement, and active-input correlation.
- Does not own: A general job queue, private AgentServer protocol, durable workflow, provider transport, or process registry.

## Current and target state

| Area | Current | Target |
| --- | --- | --- |
| Lifecycle | Session Actions and Plugin implement admission and settlement | One documented request state model |
| Entry points | Agent and standalone paths exist | Both paths use the same execution and result rules |
| Active input | Steering and pending input exist | Stable and bounded steering points |

## Major gaps and work remaining

| Gap | Why it matters | Required outcome | Owner seam |
| --- | --- | --- | --- |
| Concurrency policy is not final | Busy and duplicate behavior can vary | One active-request policy | 07 |
| Late cancellation is not final | Callers can see inconsistent results | One terminal cancel contract | 07 |

## Decisions requested

1. **Active request count:** Approve one active AI request per Agent for the first V3 release.
   Effect: Admission and steering remain simple and deterministic.
2. **Late cancel:** Approve completion as authoritative after settlement starts.
   Effect: Cancellation cannot replace an already committed terminal result.

## Dependencies

- Prerequisites: 00, 01, 04, 05, and 06.
- Dependents: 08, 09, 10, 11, and 12.
- Blockers: Request concurrency and late-cancel decisions.

## Documents

- [Target design](design.md).
- [Alignment plan](alignment.md).
