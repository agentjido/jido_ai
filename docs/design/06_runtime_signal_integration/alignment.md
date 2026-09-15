> Seam alignment review. Pending approval.

# Core runtime and Signal integration alignment

## Status

- Reviewed: 2026-09-15.
- Code: `v3-spike`, HEAD `c4e57c8d34d09ffc922c37fb41cccc2e1491123e`, plus the uncommitted Orchestration and canonical-value file reorganization.
- Prerequisite alignments used: [00 Package boundary and invariants](../00_boundary_invariants/alignment.md), [01 Canonical interaction and AI values](../01_ai_values/alignment.md), [04 Shared AI execution](../04_ai_execution/alignment.md).
- Alignment state: Draft. Current ownership is mapped; target decisions and full acceptance proof remain.
- Verification: source and test inspection in this documentation task. The preceding code-change run reported 2,809 passing tests and one existing exclusion, including authoring and MockLLM examples. That run is not proof of every target requirement; no Elixir tests were rerun here.

## Current architecture

Runtime and Orchestration Plugins use separate core Agent and AgentServer facets. Orchestration owns AI request coordination above core commit. Canonical Session/Thread values are local to jido_ai. Signal types and existing internal wire names were preserved during the module rename.

- Current owner: Runtime.Plugin and Orchestration.Plugin Agent/AgentServer facets, route/directive adapters, and typed Signal data.
- Cross-package ownership: core Jido owns Agent commit and topology; Flow/Exec and Signal internals remain in their respective packages.
- Overall placement: [architecture overview](../ARCHITECTURE.md).
- Full target: [design](design.md). Use only public core Plugin, Agent, Flow, and Signal contracts. Preserve route validation, trusted runtime binding, post-commit work, event transport, and topology integration.

## Inputs and evidence

### Canonical code

| Source | Evidence scope |
| --- | --- |
| [lib/jido_ai/runtime/plugin.ex](../../../lib/jido_ai/runtime/plugin.ex) | Runtime integration |
| [lib/jido_ai/runtime/plugin/agent.ex](../../../lib/jido_ai/runtime/plugin/agent.ex) | Agent facet |
| [lib/jido_ai/orchestration/plugin/agent_server.ex](../../../lib/jido_ai/orchestration/plugin/agent_server.ex) | Coordinator child and admission |
| [lib/jido_ai/orchestration/plugin/agent.ex](../../../lib/jido_ai/orchestration/plugin/agent.ex) | Record and directive ownership |
| [lib/jido_ai/signal.ex](../../../lib/jido_ai/signal.ex) | Signal facade |
| [lib/jido_ai/orchestration/delivery.ex](../../../lib/jido_ai/orchestration/delivery.ex) | Event delivery |

### Examples and tests

- [Example briefing](../../../examples/01_authoring/01_06_ai_extension/README.md): public behavior and documented limits.
- [Matching example tests](../../../test/examples/01_authoring/01_06_ai_extension): deterministic example evidence.
- [test/jido_ai/plugin_facets_test.exs](../../../test/jido_ai/plugin_facets_test.exs): detailed boundary evidence.
- [test/authoring/agents/boundaries_test.exs](../../../test/authoring/agents/boundaries_test.exs): detailed boundary evidence.

These are evidence entry points, not blanket acceptance claims. The requirement
matrix below separates target decisions from implemented behavior whose full
proof is still incomplete. Inert declaration support is not runtime support.

## Retained baseline

Use only public core Plugin, Agent, Flow, and Signal contracts. Preserve route validation, trusted runtime binding, post-commit work, event transport, and topology integration.

Preserve current public behavior unless an approved decision includes a
migration. No runtime or example changes are authorized by this review.
Advanced requirements remain in the target even when they are not implemented.

## Gap register

Existing gap IDs remain stable. Superseded rows identify resolved historical
findings, not removed target requirements. Old acceptance labels and erroneous
requirement associations are not carried forward as proof.

| Gap | Requirement or proposal | Current evidence or difference | State | Required outcome and owner |
| --- | --- | --- | --- | --- |
| `INT-GAP-001` | `INT-REQ-006` | Core route validation and boundary tests are present; complete route reachability/collision proof is not inferred. | Implemented; evidence incomplete | Review INT-REQ-006 and facet ownership. |
| `INT-GAP-002` | `INT-REQ-002`, `INT-REQ-009`, `INT-REQ-010` | Static authoring and runtime binding are separated. Every optional Plugin callback still needs a purity audit for the full target. | Implemented; evidence incomplete | Keep runtime services out of static preparation. |
| `INT-GAP-003` | `INT-REQ-016` | Thread and Session are package-owned values, not missing sibling APIs. | Superseded | Use selected domain-field and projection tests. |
| `INT-GAP-004` | `INT-REQ-023`, `INT-REQ-024` | Typed Signal modules exist; complete field-by-field correlation across all events remains a separate matrix. | Implemented; evidence incomplete | Align with seam 12. |
| `INT-GAP-005` | `INT-REQ-026`, `INT-REQ-027` | Current delivery behavior must be compared with the no-hidden-self-routing proposal, not changed by documentation. | Decision required | Review explicit dispatcher and loop-prevention cases. |
| `INT-GAP-006` | `INT-REQ-008`, `INT-REQ-010`, `INT-REQ-011`, `INT-REQ-012` | Agent/AgentServer facets are integrated and the earlier compile blocker is resolved. | Superseded | Retain conformance checks against supported V3 dependencies. |

## Resource ownership alignment gap

The [selected ownership](design.md#selected-ai-runtime-resource-ownership)
needs explicit per-AgentServer bindings and selected Jido Task Supervisor
use. Current Coordinator starts request execution with Task.async. Preserve
its cancellation, completion, and ordered commit duties while aligning worker
ownership. Future evidence covers one owner, worker cleanup, binding isolation,
and admission before execution. Session activation restart policy is unresolved.

## Decisions and dependency gates

Review delivery defaults and callback purity against current core contracts. AI delegation must not introduce a second topology owner.

- Prerequisites: [00 Package boundary and invariants](../00_boundary_invariants/alignment.md), [01 Canonical interaction and AI values](../01_ai_values/alignment.md), [04 Shared AI execution](../04_ai_execution/alignment.md).
- Dependents: 07, 09.
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
| `INT-REQ-001` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: The AI Agent DSL shall implement the public `Jido.Agent.Extension` contract and shall lower static AI declarations to an ordinary neutral Agent definition. |
| `INT-REQ-002` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: Lowering shall perform no model call, tool call, process start, store access, or other runtime side effect. |
| `INT-REQ-003` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: Each AI route target shall resolve to a validated core Action or Flow before the Agent definition is accepted. |
| `INT-REQ-004` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: Turn-mode AI routes shall target the canonical AI Flow without a second graph runner. |
| `INT-REQ-005` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: Session-mode AI routes shall target one admission Action that returns a candidate and a post-commit start-work Directive. |
| `INT-REQ-006` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: AI-generated routes shall use core route conflict validation and shall not override an explicit host route silently. |
| `INT-REQ-007` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: Route-target options shall be owned and validated by the AI extension and shall reject unknown options. |
| `INT-REQ-008` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: Each AI Plugin shall declare at most one portable Agent state key through `state_spec/1`. |
| `INT-REQ-009` | Decision required | See current contract and gap register | Verify the target behavior: AI Plugin `prepare/2` and `update_state/3` callbacks shall be pure and shall not use a live runtime resource. |
| `INT-REQ-010` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: When an AI Plugin uses `admit/3`, the callback shall run through the core live-admission contract and shall return a validated command or error. |
| `INT-REQ-011` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: An AI Plugin shall define `child_spec/1` only when it needs a connection, timer, live task owner, or other process-local state. |
| `INT-REQ-012` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: A Plugin runtime shall receive only its public runtime reference and core callback context; it shall not read private AgentServer state. |
| `INT-REQ-013` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: A Plugin state update shall reject a stale request ID, run ID, or Directive version without changing state. |
| `INT-REQ-014` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: Jido AI shall read provider resources, request-local trusted options, and stream sinks only from trusted core command context or Plugin runtime state. |
| `INT-REQ-015` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: Signal data shall not override a trusted model client, credential, HTTP client, tool runtime resource, or stream sink. |
| `INT-REQ-016` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: Message history shall be stored in a declared Agent domain field and shall be returned as part of the complete candidate Agent. |
| `INT-REQ-017` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: Runtime bindings shall be removed before data enters an Agent candidate, Plugin state, Signal data, or checkpoint. |
| `INT-REQ-018` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: Every AI Directive type shall be declared by exactly one Plugin and validated before commit. |
| `INT-REQ-019` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: A Directive that updates Plugin state shall reduce only that Plugin's owned state key. |
| `INT-REQ-020` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: A Directive that starts or delivers runtime work shall dispatch only after core commit succeeds. |
| `INT-REQ-021` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: If core candidate validation or commit fails, Jido AI shall not dispatch post-commit runtime work. |
| `INT-REQ-022` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: Jido AI shall not treat a successful pre-commit model or tool call as proof that Agent state committed. |
| `INT-REQ-023` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: Each public AI event Signal shall use a stable type string, default source, strict Zoi data schema, and portable data. |
| `INT-REQ-024` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: AI event data shall include the correlation identifiers required by seam 12 for its lifecycle stage. |
| `INT-REQ-025` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: Jido AI shall create, serialize, route, and dispatch AI Signals only through public `jido_signal` contracts. |
| `INT-REQ-026` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: An event Signal shall not act as a private control message unless an explicit Agent route admits that type as a command. |
| `INT-REQ-027` | Decision required | See current contract and gap register | Verify the target behavior: When an Agent has no route for an outbound AI event, event delivery shall follow the configured public dispatcher policy and shall not re-enter the same Agent by hidden default. |

## Migration and compatibility

Review delivery defaults and callback purity against current core contracts. AI delegation must not introduce a second topology owner.

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
