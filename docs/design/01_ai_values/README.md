> Seam review entry point. This document is pending approval.

# 01 — AI values and result contracts

## Briefing

Jido AI has query, context, turn, output, usage, and error modules, but their complete public and portable boundary is not in one contract. The target is one stable value layer for all later seams. The main change is to keep provider types and process resources out of public AI data.

## Why this seam exists

- Owner: `Jido.AI.Query`, `Jido.AI.Context`, `Jido.AI.Turn`, `Jido.AI.Output`, `Jido.AI.Usage`, and `Jido.AI.Error`.
- Owns: Portable AI input, content, history, turn, output, usage, metadata, and errors.
- Does not own: Provider calls, processes, stores, request admission, Flow scheduling, or Agent commit.

## Current and target state

| Area | Current | Target |
| --- | --- | --- |
| Values | Implemented across shared modules | One documented and versioned public value layer |
| Provider data | Adapter boundaries exist, but the full leak test is not defined | Provider data stays behind adapters |
| Errors | AI normalization exists | Stable error codes, causes, and safe inspection rules |

## Major gaps and work remaining

| Gap | Why it matters | Required outcome | Owner seam |
| --- | --- | --- | --- |
| Public struct list is not approved | Consumers cannot know what is stable | Approved public value list | 01 |
| Codec and version rules are incomplete | Resume and remote input can become unsafe | Explicit codec and version rules | 01 |

## Decisions requested

1. **Public values:** Approve a small stable set of public structs.
   Effect: Other seams can depend on portable data without provider coupling.
2. **Output repair:** Choose whether repair belongs to this value seam or to the model gateway.
   Effect: Output behavior has one owner.

## Dependencies

- Prerequisites: [00 — Package boundary and invariants](../00_boundary_invariants/README.md).
- Dependents: 02, 03, 04, 05, 06, 07, 08, 09, 10, 11, and 12.
- Blockers: Public value and version decisions.

## Documents

- [Target design](design.md).
- [Alignment plan](alignment.md).
