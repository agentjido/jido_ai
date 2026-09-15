> Seam review entry point. Pending approval.

# 09 — Skills and resources

## Briefing

Skill modules cover discovery, loading, activation, prompt/tool contributions, and resource policy. Orchestration prepares automatic skill catalogs. Skill.Registry still permits lazy global startup. Resource providers and policy are separate from canonical Session/Thread values.

This seam retains the complete target, not only current functionality. Detailed
current evidence and gaps are in [alignment](alignment.md); proposed contracts
and stable requirement IDs are in [design](design.md).

## Why this seam exists

- Owner: Skill discovery, source, specification, activation, registry, runtime, resources, providers, and Actions.Skill.
- Owns: skills and resources within [the package architecture](../ARCHITECTURE.md).
- Does not own: contracts assigned to other seams or private lower-package internals.

## Current and target state

| Area | Current | Target |
| --- | --- | --- |
| Architecture | The module and state ownership above is the code baseline | Keep rich skill and resource functionality, deterministic dependencies/collisions, trust boundaries, bounded loading, and versioned restoration. Do not remove advanced resource work because the current implementation is narrower. |
| Evidence | Linked example and boundary tests cover specific cases | Direct requirement-level acceptance, including advanced paths |
| Compatibility | Current APIs remain authoritative | Explicit migration for approved contract changes |

## Major gaps and work remaining

| Gap | Why it matters | Required outcome | Owner |
| --- | --- | --- | --- |
| [SKL-GAP-001](alignment.md#gap-register) | Skill identity, validation, and activation exist; complete dependency/collision guarantees need a contribution matrix. | Retain deterministic ordering and conflict cases. | 09; dependencies below |
| [SKL-GAP-002](alignment.md#gap-register) | Resource policy/provider boundaries exist, but the complete portable content contract needs review. | Retain content type, normalization, and bounds work. | 09; dependencies below |
| [SKL-GAP-003](alignment.md#gap-register) | Action/tool contributions and runtime composition exist. General Plugin contribution collision policy is not established. | Resolve with 06/08 rather than adding another composition engine. | 09; dependencies below |
| [SKL-GAP-004](alignment.md#gap-register) | Registry.ensure_started still permits lazy global startup. | Decide host/runtime ownership and migration for lookup behavior. | 09; dependencies below |
| [SKL-GAP-005](alignment.md#gap-register) | Skill source and activation data exist; a complete versioned resource-restoration contract needs 11. | Retain identity, version, and binding reference requirements. | 09; dependencies below |
| [SKL-GAP-006](alignment.md#gap-register) | The old alignment requested legacy decoding while other seams reject V2 checkpoint formats. | Define the exact supported skill versions; do not silently add a V2 importer. | 09; dependencies below |

## Decisions requested

Resolve explicit versus lazy registry ownership and atomic re-resolution. Define skill compatibility policy with checkpoint and authoring seams.

The [target design decisions](design.md#open-design-decisions) remain pending.
No advanced capability is removed by this reconciliation.

## Dependencies

- Prerequisites: [03 Tools, sources, and effect policy](../03_tool_bridge/alignment.md), [06 Core runtime and Signal integration](../06_runtime_signal_integration/alignment.md), [07 Request orchestration and active input](../07_request_sessions/alignment.md).
- Dependents: 10, 11.
- Blockers: unresolved target and prerequisite decisions. Current implementation can be inspected without treating proposed contracts as approved.

## Documents

- [Target design](design.md).
- [Current evidence and alignment](alignment.md).
- [Overall architecture](../ARCHITECTURE.md).
