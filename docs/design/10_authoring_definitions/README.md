> Seam review entry point. Pending approval.

# 10 — Authoring and portable definitions

## Briefing

Agent plus DSL plus Profile is the main authoring form. Profile uses Zoi and validated map fields; the illustrative nested target structs are not the actual schema. Portable codecs use trusted references. Tool-source declarations can round-trip without proving their runtime adapters. Generated helpers use current Request/Orchestration paths.

This seam retains the complete target, not only current functionality. Detailed
current evidence and gaps are in [alignment](alignment.md); proposed contracts
and stable requirement IDs are in [design](design.md).

## Why this seam exists

- Owner: Agent, DSL, Profile, Authoring, Portable, Configuration, and trusted reference resolution.
- Owns: authoring and portable definitions within [the package architecture](../ARCHITECTURE.md).
- Does not own: contracts assigned to other seams or private lower-package internals.

## Current and target state

| Area | Current | Target |
| --- | --- | --- |
| Architecture | The module and state ownership above is the code baseline | Preserve complete module/direct/codec authoring parity, advanced source declarations, safe registries, explicit defaults, and one lowering path. Avoid a second Agent or Flow DSL. |
| Evidence | Linked example and boundary tests cover specific cases | Direct requirement-level acceptance, including advanced paths |
| Compatibility | Current APIs remain authoritative | Explicit migration for approved contract changes |

## Major gaps and work remaining

| Gap | Why it matters | Required outcome | Owner |
| --- | --- | --- | --- |
| [AUT-GAP-001](alignment.md#gap-register) | The V2 option-based authoring path is removed; the current Agent/DSL path and rejection tests remain. | Preserve the current single authoring form. | 10; dependencies below |
| [AUT-GAP-002](alignment.md#gap-register) | Inline Action authoring is supported; boundary tests exist. Full input/output/context permutations need explicit mapping. | Retain complete inline authoring conformance. | 10; dependencies below |
| [AUT-GAP-003](alignment.md#gap-register) | Boundary tests cover duplicate routes, result fields, managed Plugins, initialized hosts, and trusted defaults. | Complete the broader Plugin/directive collision matrix. | 10; dependencies below |
| [AUT-GAP-004](alignment.md#gap-register) | A dated source snapshot and current map exist. They do not approve every public contract. | Use actual exported APIs and distinguish static sources from execution support. | 10; dependencies below |
| [AUT-GAP-005](alignment.md#gap-register) | The preceding code run passed compile and the full authoring/example-inclusive suite. | Keep the same checks; this documentation task does not rerun them. | 10; dependencies below |

## Decisions requested

Reconcile target type names with the real Profile schema. Distinguish static declaration support, safe preflight, and executable behavior in every authoring form.

The [target design decisions](design.md#open-design-decisions) remain pending.
No advanced capability is removed by this reconciliation.

## Dependencies

- Prerequisites: [05 Reasoning and planning methods](../05_reasoning_planning/alignment.md), [08 Capabilities and policy](../08_capabilities_policy/alignment.md), [09 Skills and resources](../09_skills_resources/alignment.md).
- Dependents: 12.
- Blockers: unresolved target and prerequisite decisions. Current implementation can be inspected without treating proposed contracts as approved.

## Documents

- [Target design](design.md).
- [Current evidence and alignment](alignment.md).
- [Overall architecture](../ARCHITECTURE.md).
