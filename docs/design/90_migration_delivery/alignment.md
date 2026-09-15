> Seam alignment review. Pending approval.

# Migration and delivery alignment

## Status

- Reviewed: 2026-09-15.
- Code: `v3-spike`, HEAD `c4e57c8d34d09ffc922c37fb41cccc2e1491123e`, plus the uncommitted Orchestration and canonical-value file reorganization.
- Prerequisite alignments used: [12 Observation and diagnostics](../12_observation_diagnostics/alignment.md).
- Alignment state: Draft. Current ownership is mapped; target decisions and full acceptance proof remain.
- Verification: source and test inspection in this documentation task. The preceding code-change run reported 2,809 passing tests and one existing exclusion, including authoring and MockLLM examples. That run is not proof of every target requirement; no Elixir tests were rerun here.

## Current architecture

The execution CLI is removed. Install, skill, and quality Mix tasks and consumer test helpers remain. The package is version 2.3.0 using V3 beta Hex dependencies and a pinned ReqLLM Git source. Current guides/examples use V3 authoring. The preceding full verification passed 2,809 tests with one existing exclusion; it is not a complete stable-release rehearsal.

- Current owner: Package metadata, guides, examples, public test helpers, Mix tasks, and release evidence.
- Cross-package ownership: core Jido owns Agent commit and topology; Flow/Exec and Signal internals remain in their respective packages.
- Overall placement: [architecture overview](../ARCHITECTURE.md).
- Full target: [design](design.md). Preserve the complete capability/disposition inventory, migrations, compatibility decisions, deterministic consumer support, and release/security/performance/operational gates.

## Inputs and evidence

### Canonical code

| Source | Evidence scope |
| --- | --- |
| [mix.exs](../../../mix.exs) | Version, dependencies, and package metadata |
| [lib/jido_ai/test/mock_llm.ex](../../../lib/jido_ai/test/mock_llm.ex) | Deterministic model support |
| [lib/jido_ai/test/react_script.ex](../../../lib/jido_ai/test/react_script.ex) | Standalone scripting support |
| [lib/mix/tasks/jido_ai.install.ex](../../../lib/mix/tasks/jido_ai.install.ex) | Retained installer |
| [lib/mix/tasks/jido_ai.quality.ex](../../../lib/mix/tasks/jido_ai.quality.ex) | Quality tooling |

### Examples and tests

- [Example briefing](../../../examples/01_authoring/01_02_tool_flow/README.md): public behavior and documented limits.
- [Matching example tests](../../../test/examples/01_authoring/01_02_tool_flow): deterministic example evidence.
- [test/examples/support/catalog_test.exs](../../../test/examples/support/catalog_test.exs): detailed boundary evidence.
- [test/jido_ai/api_inventory_test.exs](../../../test/jido_ai/api_inventory_test.exs): detailed boundary evidence.

These are evidence entry points, not blanket acceptance claims. The requirement
matrix below separates target decisions from implemented behavior whose full
proof is still incomplete. Inert declaration support is not runtime support.

## Retained baseline

Preserve the complete capability/disposition inventory, migrations, compatibility decisions, deterministic consumer support, and release/security/performance/operational gates.

Preserve current public behavior unless an approved decision includes a
migration. No runtime or example changes are authorized by this review.
Advanced requirements remain in the target even when they are not implemented.

## Gap register

Existing gap IDs remain stable. Superseded rows identify resolved historical
findings, not removed target requirements. Old acceptance labels and erroneous
requirement associations are not carried forward as proof.

| Gap | Requirement or proposal | Current evidence or difference | State | Required outcome and owner |
| --- | --- | --- | --- | --- |
| `DEL-GAP-001` | `DEL-REQ-001`, `DEL-REQ-002`, `DEL-REQ-003`, `DEL-REQ-004`, `DEL-REQ-005` | Current API and feature inventories exist; complete approved V2 disposition and target acceptance coverage remains. | Partially implemented | Preserve every capability until disposition is explicit. |
| `DEL-GAP-002` | `DEL-REQ-007`, `DEL-REQ-008`, `DEL-REQ-009`, `DEL-REQ-010`, `DEL-REQ-011` | V3 beta Hex dependencies replace the old sibling-path assumption. Version and package description still need release decisions. | Decision required | Review source policy, version matrix, and metadata. |
| `DEL-GAP-003` | `DEL-REQ-012`, `DEL-REQ-013`, `DEL-REQ-014`, `DEL-REQ-015`, `DEL-REQ-016`, `DEL-REQ-018` | Full code tests previously passed; documentation generation, packaging, security, load, and release rehearsal are separate gates. | Partially implemented | Keep a complete release evidence ledger. |
| `DEL-GAP-004` | `DEL-REQ-019`, `DEL-REQ-020`, `DEL-REQ-021`, `DEL-REQ-022`, `DEL-REQ-023`, `DEL-REQ-024` | Primary current examples and guides no longer generally lead with V2 Strategy authoring. | Superseded | Audit remaining stale references; do not use the old blanket claim. |
| `DEL-GAP-005` | `DEL-REQ-025`, `DEL-REQ-026`, `DEL-REQ-027`, `DEL-REQ-028` | The execution CLI is removed while DEL-REQ-025/026 and DEL-DEC-003 describe a CLI target. | Decision required | Retain the proposal for explicit disposition; do not restore a CLI from docs alone. |
| `DEL-GAP-006` | Performance/security/operations proposals; release gate DEL-REQ-030 | A complete approved performance/security/operational readiness package is not established by unit tests. | Proposed; not implemented | Retain budgets, threat checks, load tests, and rollback gates. |
| `DEL-GAP-007` | `DEL-REQ-008`, `DEL-REQ-013`, `DEL-REQ-018`, `DEL-REQ-031`, `DEL-REQ-032` | Local verification is not a clean multi-package release rehearsal. | Implemented; evidence incomplete | Keep dependency-order release verification and external package ownership explicit. |

## Open transformer migration gate

[EXE-DEC-005](../04_ai_execution/design.md#selected-direction-complete-the-runtime-split)
selects a common request-transform view and Profile input. Compatibility with
existing transformer callbacks remains open. Before implementation planning,
resolve that contract with seam 02 and identify affected examples and consumers.
Do not infer a compatibility adapter, breaking release, or removal of callback
support. Preserve standalone ReAct conversion and token behavior. This is a
record of an open gate, not approval of this document.

## Decisions and dependency gates

Reconcile old CLI and reduced-method release recommendations explicitly. Separate current tested functionality from an approved stable release surface.

- Prerequisites: [12 Observation and diagnostics](../12_observation_diagnostics/alignment.md).
- Dependents: None.
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
| `DEL-REQ-001` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: Every public V2 module, function, macro, option, Signal, CLI command, and checkpoint form shall have a Retain, Replace, Move, Defer, or Remove disposition before V3 release. |
| `DEL-REQ-002` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: Each retained or replaced V2 capability shall map to one approved V3 seam owner and one acceptance contract. |
| `DEL-REQ-003` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: The V3 package shall not ship compatibility shims for V2 options, Signals, state, checkpoints, workers, or Strategy behavior. |
| `DEL-REQ-004` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: Each removed public API shall state its V3 replacement or an explicit no-replacement reason. |
| `DEL-REQ-005` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: Each removed public API shall appear in the migration guide with a replacement or an explicit no-replacement reason. |
| `DEL-REQ-006` | Decision required | See current contract and gap register | Verify the target behavior: Experimental methods or capabilities shall be marked in module documentation, guides, and package release notes. |
| `DEL-REQ-007` | Decision required | See current contract and gap register | Verify the target behavior: The stable package shall declare a V3 package version and compatible released versions of direct dependencies. |
| `DEL-REQ-008` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: Release verification shall use a compatible V3 set of `jido_action`, `jido_signal`, `jido`, `jido_ai`, and applicable integration packages. |
| `DEL-REQ-009` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: A production V3 test shall not select a V2 sibling package. |
| `DEL-REQ-010` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: Local path dependencies used for integration shall be replaced with approved release requirements before publishing unless release policy explicitly permits another source. |
| `DEL-REQ-011` | Decision required | See current contract and gap register | Verify the target behavior: Package metadata shall describe Jido AI as the AI integration and behavior layer and shall not claim ownership of generic workflows or durable orchestration. |
| `DEL-REQ-012` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: Each approved requirement shall have Proven acceptance evidence or an explicit approved deferral before release. |
| `DEL-REQ-013` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: Package release checks shall run formatting, warnings-as-errors compilation, package tests, examples or acceptance tests, documentation generation, and package build. |
| `DEL-REQ-014` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: Release checks shall include boundary tests that reject private AgentServer access, direct Flow runtime access, custom Signal transport, and nonportable state. |
| `DEL-REQ-015` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: Release checks shall cover Turn and session parity, model and tool error paths, resource limits, cancellation races, structured output, Plugin conflicts, codec safety, checkpoint restore, and observation redaction. |
| `DEL-REQ-016` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: A known failing or non-compiling test shall block a stable release unless the related feature is explicitly removed and the test is replaced by approved evidence. |
| `DEL-REQ-017` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: Test helpers shall use public V3 contracts and shall not expose private runtime state as a supported testing technique. |
| `DEL-REQ-018` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: A release candidate shall pass the same required matrix as the stable release. |
| `DEL-REQ-019` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: The package overview shall describe the package boundary, V3 Agent and Flow model, request modes, effect timing, durability limits, and host responsibilities. |
| `DEL-REQ-020` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: Public guides shall use `Jido.AI.Agent` and its Spark DSL as the primary authoring form. Direct core Agents shall use `Jido.AI.DSL` explicitly. |
| `DEL-REQ-021` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: Examples shall include direct generation, Turn mode, session mode, streaming, tools, structured output, reasoning, retrieval, quota, skills, checkpoints, and observation. |
| `DEL-REQ-022` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: Each example shall state whether it uses a real provider, test provider, external service, in-memory store, or durable host resource. |
| `DEL-REQ-023` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: The migration guide shall show V2-to-V3 mappings for Agent macros, Strategy modules, tools, request calls, Plugins, Signals, skills, and checkpoints. |
| `DEL-REQ-024` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: Documentation shall not present old guides, old source, or migration notes as canonical V3 behavior. |
| `DEL-REQ-025` | Decision required | See current contract and gap register | Verify the target behavior: CLI adapters shall call public V3 Profile, request, stream, inspection, and cancellation APIs. |
| `DEL-REQ-026` | Decision required | See current contract and gap register | Verify the target behavior: CLI output shall use safe observation and result views and shall not print credentials, hidden reasoning, or raw provider responses by default. |
| `DEL-REQ-027` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: Consumer test helpers shall provide deterministic model, stream, tool, clock, and registry doubles through public dependency-injection points. |
| `DEL-REQ-028` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: A test helper shall not start an application store or runtime process implicitly unless its function name and documentation state that behavior. |
| `DEL-REQ-029` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: Release notes shall list stable, experimental, deferred, and removed surfaces. |
| `DEL-REQ-030` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: Before stable release, every seam shall have an approved design, complete alignment state, and no unresolved conflict. |
| `DEL-REQ-031` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: A publish rollback procedure shall identify how to yank or supersede a bad release without changing already published artifacts. |
| `DEL-REQ-032` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: A release shall not claim durable orchestration, exactly-once effects, or provider-independent behavior beyond the approved contracts. |

## Migration and compatibility

Reconcile old CLI and reduced-method release recommendations explicitly. Separate current tested functionality from an approved stable release surface.

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
