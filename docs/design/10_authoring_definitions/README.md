> Seam review entry point. This document is pending approval.

# 10 — AI authoring and portable definitions

## Briefing

The current V3 authoring layer has profiles, an Agent DSL, Plugin stack assembly, and lowering to core Agent and Flow values. The target is one inert and portable definition model with parity across module, direct-data, and codec forms. The main change is to make authoring assemble approved behavior without creating new runtime behavior.

## Why this seam exists

- Owner: Profile, Authoring, Agent DSL, codec, portable definition, and convenience-agent modules.
- Owns: Profile data, authoring parity, lowering, route targets, Plugin stack assembly, defaults, and convenience request calls.
- Does not own: Compile-time effects, a second Flow DSL, provider clients, store supervision, or format-specific behavior.

## Current and target state

| Area | Current | Target |
| --- | --- | --- |
| Profile | Broad portable fields and validation exist | Approved versioned profile contract |
| Lowering | Profiles lower to core Agents, Plugins, and Flows | One deterministic lowering result |
| Formats | DSL parity tests exist | Module, data, and codec forms have full behavior parity |

## Major gaps and work remaining

| Gap | Why it matters | Required outcome | Owner seam |
| --- | --- | --- | --- |
| Defaults are not approved | Small changes can break consumers | Stable default and compatibility policy | 10 and 90 |
| Callback portability is not final | Encoded profiles can contain unsafe or local behavior | Explicit callback and codec rule | 10 |

## Decisions requested

1. **Authoring model:** Approve one profile value as the canonical authoring form.
   Effect: All input formats can lower through one validation path.
2. **Callbacks:** Reject anonymous functions in portable encoded profiles.
   Effect: Definitions remain safe to inspect and move.

## Dependencies

- Prerequisites: 00 through 09.
- Dependents: 12 and 90.
- Blockers: Defaults, alias portability, callbacks, and codec safety.

## Documents

- [Target design](design.md).
- [Alignment plan](alignment.md).
