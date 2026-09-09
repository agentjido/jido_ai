> Seam review entry point. This document is pending approval.

# 08 — AI capabilities and policy

## Briefing

Jido AI contains chat, planning, reasoning, model-routing, policy, retrieval, and quota capabilities. The target is a set of composable AI Plugins with one owned state key and explicit host resources. The main change is to separate AI policy from application services, billing systems, and durable stores.

## Why this seam exists

- Owner: AI capability Plugin and policy modules.
- Owns: Capability options, Plugin state, request hooks, model and tool policy, retrieval enrichment, quota decisions, and external store contracts.
- Does not own: A Plugin platform, billing ledger, durable memory service, application supervision tree, or workflow engine.

## Current and target state

| Area | Current | Target |
| --- | --- | --- |
| Plugin stack | Default and optional capability Plugins exist | Explicit composition and state ownership |
| Retrieval | AI retrieval and store contracts exist | Host-supplied service and durable store |
| Quota | AI admission and usage logic exist | AI policy separated from authoritative billing |

## Major gaps and work remaining

| Gap | Why it matters | Required outcome | Owner seam |
| --- | --- | --- | --- |
| Base capability set is not final | Package scope and compatibility are unclear | Approved first-release capability set | 08 and 90 |
| Store support level is not stated | Users can treat reference stores as production services | Explicit support and durability statement | 08 |

## Decisions requested

1. **Base package set:** Approve chat, model routing, and policy as base capabilities; classify the rest explicitly.
   Effect: The package has a clear minimum surface.
2. **Store status:** Decide whether retrieval and quota stores are supported implementations or reference adapters.
   Effect: Durability and service expectations are clear.

## Dependencies

- Prerequisites: 00 through 07 as applicable to each capability.
- Dependents: 10 and 12; 09 can consume capability contracts.
- Blockers: Base capability and store-status decisions.

## Documents

- [Target design](design.md).
- [Alignment plan](alignment.md).
