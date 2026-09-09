> Seam review entry point. This document is pending approval.

# 11 — AI checkpoints and resume

## Briefing

Jido AI has AI-only checkpoint data, legacy sanitization, and resume examples, but the current root checkpoint test does not compile. The target is portable and versioned AI resume data that core Jido can checkpoint through public contracts. The main change is to exclude live Exec state and state the external-effect delivery limits.

## Why this seam exists

- Owner: AI checkpoint, ReAct checkpoint, token, migration, and resume modules; core Jido owns Agent checkpoint integration.
- Owns: AI phase, domain data, effect data, remaining AI work, bindings, sanitization, migration, and new-execution resume conversion.
- Does not own: PIDs, tasks, monitors, streams, functions, clients, secrets, live Exec state, durable queues, or exactly-once delivery.

## Current and target state

| Area | Current | Target |
| --- | --- | --- |
| AI data | `ReactCheckpoint` separates AI data from Exec state | One versioned portable AI schema |
| Legacy path | Sanitization code and old Agent test shape remain | Explicit migration or removal policy |
| Resume guarantee | Examples exist, but delivery language is not final | Clear duplicate-effect and binding rules |

## Major gaps and work remaining

| Gap | Why it matters | Required outcome | Owner seam |
| --- | --- | --- | --- |
| Root test does not compile | Current behavior is not verified | Compile and pass against the approved core contract | 11 |
| Delivery guarantee is unstated | Resume can repeat external effects | Explicit guarantee and idempotency contract | 11 and host |

## Decisions requested

1. **Resume guarantee:** Approve at-least-once external effect behavior unless a tool supplies idempotency.
   Effect: The API does not claim rollback or exactly-once delivery.
2. **V2 import:** Decide whether V2 checkpoint import is a release requirement.
   Effect: Migration scope and supported versions are known.

## Dependencies

- Prerequisites: 00, 01, 04, 06, 07, and 09; approved core Agent checkpoint contract.
- Dependents: 12 and 90.
- Blockers: Compile failure, delivery guarantee, and V2 import decision.

## Documents

- [Target design](design.md).
- [Alignment plan](alignment.md).
