> Seam review entry point. This document is pending approval.

# 05 — Reasoning and planning methods

## Briefing

Jido AI contains several reasoning methods, method state machines, and planning features. The target is to retain AI prompts, candidates, scores, search policy, and completion rules while Flow owns generic execution mechanics. The main change is a behavior-based audit of each machine, not removal based on module names.

## Why this seam exists

- Owner: Reasoning and planning algorithm modules.
- Owns: Method prompts, candidates, scores, AI search policy, method limits, completion, and result values.
- Does not own: Graph scheduling, worker pools, lifecycle supervision, durable plan execution, or business workflows.

## Current and target state

| Area | Current | Target |
| --- | --- | --- |
| Methods | Multiple V2 and V3 method modules exist | An approved public V3 method set |
| Machines | Can mix AI search state with scheduler logic | Retain AI state and use Flow for mechanics |
| Planning | Prompt and execution concerns can overlap | AI plan semantics here; generic execution outside |

## Major gaps and work remaining

| Gap | Why it matters | Required outcome | Owner seam |
| --- | --- | --- | --- |
| Public method list is not final | Compatibility and testing scope are unknown | Approved V3 method set | 05 and 90 |
| Machine duties are not classified | Useful AI behavior can be removed with old runtime code | File-by-file semantic ownership map | 05 |

## Decisions requested

1. **Method set:** Approve the methods that are public V3 commitments.
   Effect: The seam can define stable state and result contracts.
2. **Plan execution:** Approve Flow or host ownership for generic plan execution.
   Effect: Planning does not create a second workflow engine.

## Dependencies

- Prerequisites: 00, 01, 02, and 04; 03 for tool-capable methods.
- Dependents: 07, 08, 10, and 12.
- Blockers: Public method set and execution ownership.

## Documents

- [Target design](design.md).
- [Alignment plan](alignment.md).
