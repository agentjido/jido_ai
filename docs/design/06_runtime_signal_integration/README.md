> Seam review entry point. This document is pending approval.

# 06 — Core runtime and Signal integration

## Briefing

Jido AI now uses core Agent, Plugin, Directive, Flow, Exec, and Signal contracts in its main V3 path. The target is a thin integration layer that never uses private runtime state or duplicates Signal transport. The main change is to define exact AI route, Plugin state, candidate, Directive, runtime binding, and typed Signal contracts.

## Why this seam exists

- Owner: Jido AI integration modules, with core Jido and Signal contract review.
- Owns: AI route targets, Plugin state, admission data, candidate data, AI Directives, runtime bindings, and typed AI Signal data.
- Does not own: AgentServer internals, commit, PID identity, Signal envelopes, routing, dispatch, or the bus.

## Current and target state

| Area | Current | Target |
| --- | --- | --- |
| Agent integration | Authoring lowers to core Agents and Flows | All paths use the same public Turn and Plugin rules |
| Runtime resources | Runtime binding exists | No resource handle enters portable state |
| Signals | Typed AI Signal modules exist | AI owns data; `jido_signal` owns transport |

## Major gaps and work remaining

| Gap | Why it matters | Required outcome | Owner seam |
| --- | --- | --- | --- |
| Event and command roles are not final | Signals can become a second control protocol | Clear route and event contracts | 06 and 12 |
| Post-commit path choices are not final | Effects can run at the wrong time | Directive and Plugin callback rules | 06 |

## Decisions requested

1. **Signal roles:** Approve typed AI Signals as event data and explicit routed request input only.
   Effect: Event transport cannot bypass request admission.
2. **Runtime handles:** Approve a strict no-portable-handle invariant.
   Effect: Agents and checkpoints remain serializable.

## Dependencies

- Prerequisites: 00, 01, and 04; public contracts from `jido` and `jido_signal`.
- Dependents: 07, 08, 09, 10, 11, and 12.
- Blockers: AI event role and post-commit effect decisions.

## Documents

- [Target design](design.md).
- [Alignment plan](alignment.md).
