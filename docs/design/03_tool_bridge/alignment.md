> Seam alignment review. Pending approval.

# Tools, sources, and effect policy alignment

## Status

- Reviewed: 2026-09-15.
- Code: `v3-spike`, HEAD `c4e57c8d34d09ffc922c37fb41cccc2e1491123e`, plus the uncommitted Orchestration and canonical-value file reorganization.
- Prerequisite alignments used: [01 Canonical interaction and AI values](../01_ai_values/alignment.md).
- Alignment state: Draft. Current ownership is mapped; target decisions and full acceptance proof remain.
- Verification: source and test inspection in this documentation task. The preceding code-change run reported 2,809 passing tests and one existing exclusion, including authoring and MockLLM examples. That run is not proof of every target requirement; no Elixir tests were rerun here.

## Current architecture

Tools.Executor uses core Exec and normalizes tool results. Runtime.ToolAttempt adds Profile policy, retry, and interception. Effects remain proposals until their owner applies them through core contracts. ToolSource validates inert declarations, including subagent and handoff; this does not implement dynamic discovery or delegation.

- Current owner: ToolCatalog, ToolAdapter, ToolSource, ToolContext, ToolInterceptor, ToolResult, Tools.Executor, and Effects.
- Cross-package ownership: core Jido owns Agent commit and topology; Flow/Exec and Signal internals remain in their respective packages.
- Overall placement: [architecture overview](../ARCHITECTURE.md).
- Full target: [design](design.md). Preserve static and advanced tool sources, provider-native tools, interception, approvals, bounded results, and replay-aware effect semantics. Separate tool policy from batch scheduling and Agent commit.

## Inputs and evidence

### Canonical code

| Source | Evidence scope |
| --- | --- |
| [lib/jido_ai/tools/executor.ex](../../../lib/jido_ai/tools/executor.ex) | Shared execution boundary |
| [lib/jido_ai/tool_catalog.ex](../../../lib/jido_ai/tool_catalog.ex) | Catalog validation |
| [lib/jido_ai/tool_source.ex](../../../lib/jido_ai/tool_source.ex) | Inert source kinds |
| [lib/jido_ai/tool_result.ex](../../../lib/jido_ai/tool_result.ex) | Normalized tool output |
| [lib/jido_ai/effects.ex](../../../lib/jido_ai/effects.ex) | Effect policy entry point |
| [lib/jido_ai/runtime/tool_attempt.ex](../../../lib/jido_ai/runtime/tool_attempt.ex) | Bounded attempts |

### Examples and tests

- [Example briefing](../../../examples/03_tools/03_03_numeric_inputs/README.md): public behavior and documented limits.
- [Matching example tests](../../../test/examples/03_tools/03_03_numeric_inputs): deterministic example evidence.
- [test/jido_ai/tools/executor_boundary_test.exs](../../../test/jido_ai/tools/executor_boundary_test.exs): detailed boundary evidence.
- [test/authoring/agents/plugins_controls_test.exs](../../../test/authoring/agents/plugins_controls_test.exs): detailed boundary evidence.

These are evidence entry points, not blanket acceptance claims. The requirement
matrix below separates target decisions from implemented behavior whose full
proof is still incomplete. Inert declaration support is not runtime support.

## Retained baseline

Preserve static and advanced tool sources, provider-native tools, interception, approvals, bounded results, and replay-aware effect semantics. Separate tool policy from batch scheduling and Agent commit.

Preserve current public behavior unless an approved decision includes a
migration. No runtime or example changes are authorized by this review.
Advanced requirements remain in the target even when they are not implemented.

## Gap register

Existing gap IDs remain stable. Superseded rows identify resolved historical
findings, not removed target requirements. Old acceptance labels and erroneous
requirement associations are not carried forward as proof.

| Gap | Requirement or proposal | Current evidence or difference | State | Required outcome and owner |
| --- | --- | --- | --- | --- |
| `TLS-GAP-001` | `TLS-REQ-001`, `TLS-REQ-002`, `TLS-REQ-003`, `TLS-REQ-004`, `TLS-REQ-005` | Static catalog validation exists; dynamic sources are not proved executable by their schema declarations. | Partially implemented | Retain source discovery, trust, collision, and precedence requirements. |
| `TLS-GAP-002` | Catalog snapshot proposal; not TLS-REQ-011 | A general prebuilt snapshot contract is not established. TLS-REQ-011 is actually the provider-native/local boundary. | Proposed; not implemented | Keep snapshot proposal as a design decision, not evidence for the wrong requirement. |
| `TLS-GAP-003` | `TLS-REQ-012`, `TLS-REQ-013`, `TLS-REQ-014` | ToolResult normalization exists. Target portability and error guarantees need all return-form cases. | Partially implemented | Review result, error, and effect cases against TLS-REQ-012/013/014. |
| `TLS-GAP-004` | `TLS-REQ-018`, `TLS-REQ-019` | ToolsFlow uses Map; NextBatch partitions bounded batches. The target explicitly requires a Map max_concurrency setting. | Decision required | Decide whether bounded batching satisfies the intended guarantee or migrate the Flow declaration. |
| `TLS-GAP-005` | `TLS-REQ-014`, `TLS-REQ-020`, `TLS-REQ-021` | Effect proposals and idempotency policy exist, but general durable deduplication does not. | Partially implemented | Retain replay-safety work in 11. Correct old references: effect proposals are TLS-REQ-014. |
| `TLS-GAP-006` | `TLS-REQ-022` | ToolAttempt still performs bounded sleep before a continuation. | Decision required | Resolve TLS-REQ-022 with the execution seam. |

## Decisions and dependency gates

Define executable source contracts separately from declaration support; settle retry delay and stable effect identity with 04/11.

- Prerequisites: [01 Canonical interaction and AI values](../01_ai_values/alignment.md).
- Dependents: 04, 08, 09.
- Blocker: approval of the affected target decisions, not a historical package compile failure.
- Assumption: the current public lower-package contracts remain the integration boundary. A proposed API in this design is not evidence of an upstream API.
- Re-review dependents when an owning contract changes. Do not infer approval from a passing test or a category rename.

## High-level work sequence

1. Resolve prerequisite ownership and the decisions above. Exit: each changed contract has an explicit decision and compatibility scope.
2. Align current public contracts and retained target requirements. Exit: current behavior and intended changes are distinct, with no fictional API presented as implemented.
3. Specify acceptance cases for each approved change, including examples, failure paths, and cleanup. Exit: each requirement has direct evidence or a named missing test outcome.
4. Review dependent seams, migrations, and release implications. Exit: no dependent document assumes an unapproved guarantee.

This is a dependency and outcome plan, not a formal implementation task list.
Implementation planning follows approval of the seam intent and requirements.

## Acceptance matrix

This table is rebuilt from the actual requirement IDs in `design.md`; earlier
tables sometimes mapped evidence to the wrong requirement. “Implemented;
evidence incomplete” means the subsystem has relevant code, not that every
clause is met. No row below grants approval or claims a fresh test run.

| Requirement | Evidence state | Current evidence | Required acceptance outcome |
| --- | --- | --- | --- |
| `TLS-REQ-001` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: When a local Action is added to a tool catalog, the bridge shall validate the Action and derive a provider-safe name, description, and input schema. |
| `TLS-REQ-002` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: A tool catalog shall reject duplicate public names, invalid Action targets, invalid schemas, and unsupported provider-native entries. |
| `TLS-REQ-003` | Proposed; not implemented | No complete implementation claimed | Verify the target behavior: A dynamic tool source shall return a validated list of catalog entries and shall identify its trust level and runtime resource needs. |
| `TLS-REQ-004` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: When an allowlist is present, the effective catalog shall exclude every tool that is not explicitly allowed. |
| `TLS-REQ-005` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: Tool context in a profile or request record shall be portable data; runtime resources shall be resolved through trusted binding. |
| `TLS-REQ-006` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: When a model proposes a tool call, the bridge shall normalize and validate its identifier, name, and arguments before execution. |
| `TLS-REQ-007` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: When the call name is absent from the effective catalog, the bridge shall return a model-visible tool error without executing a fallback Action. |
| `TLS-REQ-008` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: Before a local Action runs, the bridge shall apply effect policy and the configured interceptor. |
| `TLS-REQ-009` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: A local tool attempt shall execute as one `Jido.Instruction` through the public `Jido.Exec` contract. |
| `TLS-REQ-010` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: The bridge shall honor Action input validation, context validation, timeout, and result rules without an alternate execution path. |
| `TLS-REQ-011` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: A provider-native tool shall never be executed as a local Action unless a separate approved adapter declares that mapping. |
| `TLS-REQ-012` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: Each tool attempt shall return one normalized `ToolResult` correlated with the original call identifier. |
| `TLS-REQ-013` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: The model-visible result shall be bounded, transport-safe content and shall not contain a process, exception stack, credential, or arbitrary inspected runtime term. |
| `TLS-REQ-014` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: When a tool proposes Agent state changes or Directives, the bridge shall return portable effect proposals and shall not commit them. |
| `TLS-REQ-015` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: When the Action returns extra direct-caller data that Flow does not preserve, the bridge shall not depend on that data for Flow behavior. |
| `TLS-REQ-016` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: An after-call interceptor shall receive the normalized result and shall not replace the call identifier or bypass effect validation. |
| `TLS-REQ-017` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: The tool bridge shall not create workers or schedule a tool batch. |
| `TLS-REQ-018` | Decision required | See current contract and gap register | Verify the target behavior: When multiple tool calls are selected, seam 04 shall execute them with `Jido.Flow.Map` and an explicit `max_concurrency` value. |
| `TLS-REQ-019` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: Tool results returned to the model shall preserve the model's original tool-call order, independent of completion order. |
| `TLS-REQ-020` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: The bridge shall classify retry eligibility from the tool contract, error category, attempt count, and AI policy. |
| `TLS-REQ-021` | Decision required | See current contract and gap register | Verify the target behavior: A retry decision shall be portable data and shall include `retry?`, `attempt`, `max_attempts`, and an optional delay request. |
| `TLS-REQ-022` | Decision required | See current contract and gap register | Verify the target behavior: The bridge shall not sleep, spawn a retry worker, or persist retry execution state. |

## Migration and compatibility

Define executable source contracts separately from declaration support; settle retry delay and stable effect identity with 04/11.

Keep existing request, data, Signal, and provider contracts until a change is
approved. A documentation rename does not authorize a wire-format change.
Retained advanced proposals need their own migration and operational review.
Source paths above replace old `operations/`, `shared/`, live Session, and
`examples/v3/` references as evidence; historical paths are not current owners.

## Completion criteria

- [ ] All approved requirements have direct implementation and acceptance evidence.
- [ ] All material decisions have an explicit owner and resolution.
- [ ] Examples state what they prove and do not claim unsupported target features.
- [ ] Migrations and dependent seam reviews are complete.
- [ ] No previous test result is used as proof of an untested target requirement.
