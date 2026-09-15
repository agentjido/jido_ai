> Seam alignment review. Pending approval.

# Authoring and portable definitions alignment

## Status

- Reviewed: 2026-09-15.
- Code: `v3-spike`, HEAD `c4e57c8d34d09ffc922c37fb41cccc2e1491123e`, plus the uncommitted Orchestration and canonical-value file reorganization.
- Prerequisite alignments used: [05 Reasoning and planning methods](../05_reasoning_planning/alignment.md), [08 Capabilities and policy](../08_capabilities_policy/alignment.md), [09 Skills and resources](../09_skills_resources/alignment.md).
- Alignment state: Draft. Current ownership is mapped; target decisions and full acceptance proof remain.
- Verification: source and test inspection in this documentation task. The preceding code-change run reported 2,809 passing tests and one existing exclusion, including authoring and MockLLM examples. That run is not proof of every target requirement; no Elixir tests were rerun here.

## Current architecture

Agent plus DSL plus Profile is the main authoring form. Profile uses Zoi and validated map fields; the illustrative nested target structs are not the actual schema. Portable codecs use trusted references. Tool-source declarations can round-trip without proving their runtime adapters. Generated helpers use current Request/Orchestration paths.

- Current owner: Agent, DSL, Profile, Authoring, Portable, Configuration, and trusted reference resolution.
- Cross-package ownership: core Jido owns Agent commit and topology; Flow/Exec and Signal internals remain in their respective packages.
- Overall placement: [architecture overview](../ARCHITECTURE.md).
- Full target: [design](design.md). Preserve complete module/direct/codec authoring parity, advanced source declarations, safe registries, explicit defaults, and one lowering path. Avoid a second Agent or Flow DSL.

## Inputs and evidence

### Canonical code

| Source | Evidence scope |
| --- | --- |
| [lib/jido_ai/profile.ex](../../../lib/jido_ai/profile.ex) | Canonical schema and validation |
| [lib/jido_ai/dsl.ex](../../../lib/jido_ai/dsl.ex) | Core AI extension |
| [lib/jido_ai/authoring.ex](../../../lib/jido_ai/authoring.ex) | Lowering |
| [lib/jido_ai/portable.ex](../../../lib/jido_ai/portable.ex) | Import/export/inspection |
| [lib/jido_ai/profile/references.ex](../../../lib/jido_ai/profile/references.ex) | Trusted reference boundary |
| [lib/jido_ai/agent/interface.ex](../../../lib/jido_ai/agent/interface.ex) | Generated request helpers |

### Examples and tests

- [Example briefing](../../../examples/01_authoring/01_01_authoring_formats/README.md): public behavior and documented limits.
- [Matching example tests](../../../test/examples/01_authoring/01_01_authoring_formats): deterministic example evidence.
- [test/jido_ai/authoring/portable_test.exs](../../../test/jido_ai/authoring/portable_test.exs): detailed boundary evidence.
- [test/authoring/agents/boundaries_test.exs](../../../test/authoring/agents/boundaries_test.exs): detailed boundary evidence.
- [test/authoring/agents/source_variations_test.exs](../../../test/authoring/agents/source_variations_test.exs): detailed boundary evidence.

These are evidence entry points, not blanket acceptance claims. The requirement
matrix below separates target decisions from implemented behavior whose full
proof is still incomplete. Inert declaration support is not runtime support.

## Retained baseline

Preserve complete module/direct/codec authoring parity, advanced source declarations, safe registries, explicit defaults, and one lowering path. Avoid a second Agent or Flow DSL.

Preserve current public behavior unless an approved decision includes a
migration. No runtime or example changes are authorized by this review.
Advanced requirements remain in the target even when they are not implemented.

## Gap register

Existing gap IDs remain stable. Superseded rows identify resolved historical
findings, not removed target requirements. Old acceptance labels and erroneous
requirement associations are not carried forward as proof.

| Gap | Requirement or proposal | Current evidence or difference | State | Required outcome and owner |
| --- | --- | --- | --- | --- |
| `AUT-GAP-001` | `AUT-REQ-010` | The V2 option-based authoring path is removed; the current Agent/DSL path and rejection tests remain. | Implemented and evidenced | Preserve the current single authoring form. |
| `AUT-GAP-002` | `AUT-REQ-013` | Inline Action authoring is supported; boundary tests exist. Full input/output/context permutations need explicit mapping. | Implemented; evidence incomplete | Retain complete inline authoring conformance. |
| `AUT-GAP-003` | `AUT-REQ-020`, `AUT-REQ-021` | Boundary tests cover duplicate routes, result fields, managed Plugins, initialized hosts, and trusted defaults. | Implemented; evidence incomplete | Complete the broader Plugin/directive collision matrix. |
| `AUT-GAP-004` | `AUT-REQ-026`, `AUT-REQ-027`, `AUT-REQ-028`, `AUT-REQ-029` | A generated API inventory and current map exist. They are not approval of every public contract. | Partially implemented | Use actual exported APIs and distinguish static sources from execution support. |
| `AUT-GAP-005` | Package compile and test gate | The preceding code run passed compile and the full authoring/example-inclusive suite. | Implemented and evidenced | Keep the same checks; this documentation task does not rerun them. |

## Decisions and dependency gates

Reconcile target type names with the real Profile schema. Distinguish static declaration support, safe preflight, and executable behavior in every authoring form.

- Prerequisites: [05 Reasoning and planning methods](../05_reasoning_planning/alignment.md), [08 Capabilities and policy](../08_capabilities_policy/alignment.md), [09 Skills and resources](../09_skills_resources/alignment.md).
- Dependents: 12.
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
| `AUT-REQ-001` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: Every AI authoring form shall produce one validated `Jido.AI.Profile` value before Agent lowering. |
| `AUT-REQ-002` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: A Profile shall have a stable ID and shall reject unknown fields. |
| `AUT-REQ-003` | Decision required | See current contract and gap register | Verify the target behavior: Profile construction shall be inert and shall not call a model, tool, store, registry callback that performs I/O, or process supervisor. |
| `AUT-REQ-004` | Decision required | See current contract and gap register | Verify the target behavior: Profile validation shall enforce portable static data for every field that can enter Agent definitions, routes, Plugin options, or Flow data. |
| `AUT-REQ-005` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: Profile validation shall reject an unknown model role, method, control, tool, skill source, output field, history field, or request mode before lowering completes. |
| `AUT-REQ-006` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: Model aliases shall remain portable and shall resolve at request start through seam 02. |
| `AUT-REQ-007` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: The core Agent DSL, direct Profile data, and codec form shall have semantic parity for every supported Profile field. |
| `AUT-REQ-008` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: The same semantic Profile shall lower to the same Agent schema, routes, Plugin declarations, Flow semantics, and public inspection data independent of source form. |
| `AUT-REQ-009` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: A source-form-only convenience shall expand to canonical Profile data and shall not create source-form-only runtime behavior. |
| `AUT-REQ-010` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: `Jido.AI.Agent` shall accept only the V3 Spark DSL and shall reject unsupported top-level AI options. |
| `AUT-REQ-011` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: The AI DSL shall extend the core `agent do` block through the public `Jido.Agent.Extension` contract. |
| `AUT-REQ-012` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: An `ai` declaration shall define one Profile and shall make its ID available to core route targets. |
| `AUT-REQ-013` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: Inline instructions and Action tools shall compile to ordinary named Action modules with core input, output, and context validation. |
| `AUT-REQ-014` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: The DSL shall reject function calls or other unsafe evaluated forms in fields that require static literal data. |
| `AUT-REQ-015` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: The DSL shall report source location for compile-time validation errors without storing source metadata in the canonical Profile. |
| `AUT-REQ-016` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: Jido AI shall not define a second Flow declaration language; custom execution graphs shall use the standard `Jido.Flow` DSL. |
| `AUT-REQ-017` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: Lowering shall accept only a neutral Agent definition without instance ID or state. |
| `AUT-REQ-018` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: Lowering shall generate one canonical AI Flow or session admission target for each Profile. |
| `AUT-REQ-019` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: Lowering shall add only the Plugins, state fields, and internal routes required by the selected Profile features. |
| `AUT-REQ-020` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: Lowering shall reject duplicate Profile IDs, route conflicts, Plugin conflicts, output fields absent from the Agent schema, and history fields that conflict with result fields. |
| `AUT-REQ-021` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: Lowering shall pass the complete definition through core Agent validation and shall return the core validation error without hiding its cause. |
| `AUT-REQ-022` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: Lowering the same canonical input with the same registries shall be deterministic. |
| `AUT-REQ-023` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: A profile codec document shall have a type, version, complete Profile data, and stable registry references for executable or schema values. |
| `AUT-REQ-024` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: A decoder shall not create atoms, load arbitrary code, evaluate source text, or accept an executable target that is absent from the trusted registry. |
| `AUT-REQ-025` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: A decoder shall call the same canonical Profile validation and Agent lowering path as direct authoring. |
| `AUT-REQ-026` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: Portable export shall redact credentials, provider options marked sensitive, approval callbacks, tool context marked private, and other runtime-only fields. |
| `AUT-REQ-027` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: Public inspection shall distinguish declared Profile data, effective safe request data, generated Flow identity, and redacted runtime bindings. |
| `AUT-REQ-028` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: An authored AI Agent shall expose Profile inspection and the request functions supported by its request mode. |
| `AUT-REQ-029` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: Generated request functions shall be thin calls to seam 07 and shall not contain a second admission or execution path. |
| `AUT-REQ-030` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: Default values that affect behavior shall be explicit in the canonical Profile and in portable inspection. |

## Migration and compatibility

Reconcile target type names with the real Profile schema. Distinguish static declaration support, safe preflight, and executable behavior in every authoring form.

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
