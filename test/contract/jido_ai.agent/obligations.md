---
modules:
  - Jido.AI.Agent
  - Jido.AI.Plugin
  - Jido.AI.Plugin.Authoring
---

## Purpose

Protect the stable Agent-definition layer of Jido AI. The component owns the
AI Agent convenience macro, static AI Plugin configuration, Plugin preparation,
and the Jido Authoring adapter for that configuration.

It does not own model calls, routed AI execution, tool loops, control execution,
request-option propagation, traces, or streaming.

## Obligations

### jido_ai.agent.I1 — Compose the AI Plugin once

- **scope:** `use Jido.AI.Agent`, Agent extension declarations
- **must:** Add `Jido.AI.Plugin` exactly once and preserve every other declared Agent extension.
- **kind:** functional
- **status:** active

### jido_ai.agent.I2 — Keep one small AI definition

- **scope:** the `ai` block, `Jido.AI.Plugin.config/1`
- **must:** Normalize the AI definition to model, instructions, tools, and controls only. Apply the documented empty instructions, tool, and control defaults.
- **kind:** functional
- **status:** active

### jido_ai.agent.I3 — Use Jido executable primitives

- **scope:** AI tools and controls
- **must:** Accept only Jido Actions or Flows as tools. Accept at most one Jido Action as the input control and at most one Jido Action as the output control. Keep each normalized target kind and registered module reference.
- **kind:** functional
- **status:** active

### jido_ai.agent.I4 — Prepare normalized AI configuration

- **scope:** `Jido.AI.Plugin.prepare/2`, direct Agent command preparation
- **must:** Put the normalized AI configuration in the prepared input slot owned by `Jido.AI.Plugin`. Do not put it in caller context or Agent state.
- **kind:** functional
- **status:** active

### jido_ai.agent.I5 — Round-trip trusted JSON definitions

- **scope:** `Jido.AI.Plugin.Authoring`, `Jido.Authoring` Agent documents
- **must:** Encode Actions, Flows, controls, Plugins, extensions, handlers, and atoms through registered references. Decode the same Agent definition. Reject unknown model aliases without creating atoms from document text.
- **kind:** security
- **status:** active

### jido_ai.agent.I6 — Keep reply shape on the route

- **scope:** normalized and encoded AI definitions, route reply projections
- **must:** Store no Agent-level output contract in the AI definition. Keep the structured reply schema on the route handler output path selected by the reply projection. Output control Actions are not reply schemas.
- **kind:** functional
- **status:** active

### jido_ai.agent.I7 — Initialize dynamic instance state

- **scope:** `Jido.AI.Agent`, `Jido.Agent.initialize/2`, `Jido.Agent.instantiate/2`
- **must:** An Agent can create a new Session or Thread for each instance through `initialize/2`. The callback receives static initial state merged with explicit caller state and returns the complete candidate state. It preserves a supplied Session or Thread and creates one only when absent. Separate instances do not share generated identities.
- **kind:** functional
- **status:** active
