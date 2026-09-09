> Seam review entry point. This document is pending approval.

# 03 — Tool bridge and effect policy

## Briefing

Jido AI already converts Actions to provider tools and normalizes tool results. The target is a small and safe provider-tool bridge that runs one selected Action through `Jido.Exec`. The main change is to move batching, continuation, backoff, and other generic execution mechanics out of this seam.

## Why this seam exists

- Owner: Tool catalog, adapter, result, interceptor, and AI effect-policy modules.
- Owns: Provider schemas, tool admission, context binding, one tool attempt, result conversion, callbacks, and AI retry classification.
- Does not own: Graph execution, retry scheduling, TaskSupervisor, browser adapters, business transactions, or Agent commit.

## Current and target state

| Area | Current | Target |
| --- | --- | --- |
| Tool conversion | Catalog and adapter modules are implemented | One approved Action-to-provider contract |
| Tool execution | One attempt uses `Jido.Exec` | Exec remains the only Action execution boundary |
| Retry | AI classification and sleep-based backoff are together | AI classifies; an approved external owner schedules delay |

## Major gaps and work remaining

| Gap | Why it matters | Required outcome | Owner seam |
| --- | --- | --- | --- |
| Backoff owner is unclear | Jido AI can become a second scheduler | One approved scheduling owner | 00 and 03 |
| Effect result is not final | Tool work can bypass commit rules | Portable result and effect contract | 03 and 06 |

## Decisions requested

1. **Backoff owner:** Approve host policy until a lower-level contract exists.
   Effect: Jido AI keeps classification but not generic scheduling.
2. **Tool Directives:** Decide whether tools can return core Directives directly.
   Effect: Effect validation has one clear path.

## Dependencies

- Prerequisites: [00 — Package boundary and invariants](../00_boundary_invariants/README.md) and [01 — AI values](../01_ai_values/README.md).
- Dependents: 04, 05, 08, 09, 10, 11, and 12.
- Blockers: Retry scheduling and effect-result decisions.

## Documents

- [Target design](design.md).
- [Alignment plan](alignment.md).
