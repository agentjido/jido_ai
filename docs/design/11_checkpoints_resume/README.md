> Seam review entry point. This document is pending approval.

# 11 — AI checkpoints and resume

## Briefing

Jido AI has AI-only checkpoint data and resume examples. The target is portable,
strictly versioned AI resume data that core Jido can checkpoint through public
contracts. Live Exec state and V2 formats are not accepted.

## Why this seam exists

- Owner: AI checkpoint, ReAct checkpoint, token, and resume modules; core Jido owns Agent checkpoint integration.
- Owns: AI phase, domain data, effect data, remaining AI work, bindings, sanitization, and new-execution resume conversion.
- Does not own: PIDs, tasks, monitors, streams, functions, clients, secrets, live Exec state, durable queues, or exactly-once delivery.

## Current and target state

| Area | Current | Target |
| --- | --- | --- |
| AI data | `ReactCheckpoint` separates AI data from Exec state | One versioned portable AI schema |
| Unsupported data | Old Agent and checkpoint data is not accepted | Strict current-version validation |
| Resume guarantee | Examples exist, but delivery language is not final | Clear duplicate-effect and binding rules |

## Major gaps and work remaining

| Gap | Why it matters | Required outcome | Owner seam |
| --- | --- | --- | --- |
| Delivery guarantee is unstated | Resume can repeat external effects | Explicit guarantee and idempotency contract | 11 and host |

## Decisions requested

1. **Resume guarantee:** Approve at-least-once external effect behavior unless a tool supplies idempotency.
   Effect: The API does not claim rollback or exactly-once delivery.
2. **V2 import:** Do not provide a V2 checkpoint importer.
   Effect: V3 has one checkpoint contract.

## Dependencies

- Prerequisites: 00, 01, 04, 06, 07, and 09; approved core Agent checkpoint contract.
- Dependents: 12 and 90.
- Blockers: Delivery guarantee and final resume contract approval.

## Documents

- [Target design](design.md).
- [Alignment plan](alignment.md).
