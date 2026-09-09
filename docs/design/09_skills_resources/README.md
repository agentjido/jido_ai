> Seam review entry point. This document is pending approval.

# 09 — Skills and resource augmentation

## Briefing

Jido AI has skill specifications, discovery, activation, prompt assembly, Actions, Plugins, and resources. The target is a portable skill contract with explicit trust and resource limits. The main change is to send activated tools and Plugins through the normal tool, Plugin, session, and Flow paths.

## Why this seam exists

- Owner: `Jido.AI.Skill` and skill runtime modules.
- Owns: Skill identity, specification, discovery, activation, prompt content, Actions, Plugins, resource references, options, and audit data.
- Does not own: Unrestricted filesystem access, a package manager, a marketplace, arbitrary code loading, provider clients, or an execution engine.

## Current and target state

| Area | Current | Target |
| --- | --- | --- |
| Skill definition | Specification and macro code exist | One portable and versioned manifest |
| Resources | Policy and provider modules exist | Explicit trust, scope, and binding rules |
| Activation | Prompt, tools, and Plugins can be assembled | Normal seam contracts receive every activated item |

## Major gaps and work remaining

| Gap | Why it matters | Required outcome | Owner seam |
| --- | --- | --- | --- |
| Package ownership is not final | Skills can become a separate general subsystem | V3 package ownership decision | 00 and 09 |
| Executable trust is not final | Skill content can run code or access data | Explicit approval and resource policy | 09 |

## Decisions requested

1. **Package location:** Approve skills in `jido_ai` for V3 and defer extraction.
   Effect: The current integration can stabilize before a package split.
2. **Executable content:** Require explicit host approval for executable skill content.
   Effect: Discovery alone cannot authorize code execution.

## Dependencies

- Prerequisites: 00, 01, 03, 06, and 07; 08 for capability integration.
- Dependents: 10, 11, and 12.
- Blockers: Package location and trust-policy decisions.

## Documents

- [Target design](design.md).
- [Alignment plan](alignment.md).
