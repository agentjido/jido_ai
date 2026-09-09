> Seam review entry point. This document is pending approval.

# 04 — Bounded AI execution and streaming

## Briefing

The current V3 runtime already uses core Flow components for model and tool work. The target is one bounded Flow-based execution path for Agent requests and standalone requests. The main change is to remove or adapt any remaining graph, worker, timeout, cancellation, or continuation mechanics that duplicate `Jido.Flow` and `Jido.Exec`.

## Why this seam exists

- Owner: AI runtime Actions and AI Flow definitions.
- Owns: One model-tool request, AI limits, stream event order, usage, context, continuation data, and terminal AI results.
- Does not own: A graph engine, durable workflow, persistent Exec state, generic queue, Agent commit, or unbounded continuation.

## Current and target state

| Area | Current | Target |
| --- | --- | --- |
| Execution shape | Runtime and tool-call modules build core Flows | One shared Flow for all request entry points |
| Bounds | AI and Exec limits exist | One documented set of AI and Exec bounds |
| Standalone stream | Uses a private V3 Agent process | Keep only if separate Agent identity is required |

## Major gaps and work remaining

| Gap | Why it matters | Required outcome | Owner seam |
| --- | --- | --- | --- |
| Loop form is not approved | Two loop forms can diverge | One canonical Iterate or Dispatch contract | 04 |
| Runner ownership is not proven | It can duplicate core runtime mechanics | Public-contract-only standalone path | 04 and 06 |

## Decisions requested

1. **Loop contract:** Approve terminal `Dispatch` for dynamic AI choice unless `Iterate` gives a simpler bounded contract.
   Effect: The runtime has one continuation model.
2. **Standalone process:** Require evidence of a distinct Agent lifecycle before a private Agent remains.
   Effect: Process ownership follows product identity.

## Dependencies

- Prerequisites: 00, 01, 02, and 03.
- Dependents: 05, 06, 07, 08, 10, 11, and 12.
- Blockers: Tool retry ownership and loop-form decisions.

## Documents

- [Target design](design.md).
- [Alignment plan](alignment.md).
