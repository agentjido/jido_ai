> Seam alignment review. Pending approval.

# Skills and resources alignment

## Status

- Reviewed: 2026-09-15.
- Code baseline: `v3-spike`, HEAD `4ed6402f`, plus uncommitted runtime, test, example, and documentation refinement. Dependency pins are unchanged.
- Prerequisite alignments used: [03 Tools, sources, and effect policy](../03_tool_bridge/alignment.md), [06 Core runtime and Signal integration](../06_runtime_signal_integration/alignment.md), [07 Request orchestration and active input](../07_request_sessions/alignment.md).
- Alignment state: Draft. Current ownership is mapped; target decisions and full acceptance proof remain.
- Verification: the example-driven review below adds fresh MockLLM runs to the earlier source review. Earlier statements that no tests ran refer to that prior review, not this follow-up.

## Current architecture

Skill modules cover discovery, loading, activation, prompt/tool contributions, and resource policy. Orchestration prepares automatic skill catalogs. Skill.Registry still permits lazy global startup. Resource providers and policy are separate from canonical Session/Thread values.

- Current owner: Skill discovery, source, specification, activation, registry, runtime, resources, providers, and Actions.Skill.
- Cross-package ownership: core Jido owns Agent commit and topology; Flow/Exec and Signal internals remain in their respective packages.
- Overall placement: [architecture overview](../ARCHITECTURE.md).
- Full target: [design](design.md). Keep rich skill and resource functionality, deterministic dependencies/collisions, trust boundaries, bounded loading, and versioned restoration. Do not remove advanced resource work because the current implementation is narrower.

## Inputs and evidence

### Canonical code

| Source | Evidence scope |
| --- | --- |
| [lib/jido_ai/skill/source.ex](../../../lib/jido_ai/skill/source.ex) | Source preparation |
| [lib/jido_ai/skill/activation.ex](../../../lib/jido_ai/skill/activation.ex) | Activation |
| [lib/jido_ai/skill/registry.ex](../../../lib/jido_ai/skill/registry.ex) | Explicit and lazy startup |
| [lib/jido_ai/skill/resource_policy.ex](../../../lib/jido_ai/skill/resource_policy.ex) | Resource access policy |
| [lib/jido_ai/skill/resource_provider.ex](../../../lib/jido_ai/skill/resource_provider.ex) | Provider boundary |
| [lib/jido_ai/orchestration/coordinator.ex](../../../lib/jido_ai/orchestration/coordinator.ex) | Automatic catalog lifetime |

### Examples and tests

- [Example briefing](../../../examples/18_skills/18_02_skill_authoring/README.md): public behavior and documented limits.
- [Matching example tests](../../../test/examples/18_skills/18_02_skill_authoring): deterministic example evidence.
- [test/examples/18_skills/18_02_skill_authoring/18_02_skill_authoring_test.exs](../../../test/examples/18_skills/18_02_skill_authoring/18_02_skill_authoring_test.exs): detailed boundary evidence.
- [test/examples/18_skills/18_01_skill_runtime/18_01_skill_runtime_test.exs](../../../test/examples/18_skills/18_01_skill_runtime/18_01_skill_runtime_test.exs): detailed boundary evidence.

These are evidence entry points, not blanket acceptance claims. The requirement
matrix below separates target decisions from implemented behavior whose full
proof is still incomplete. Inert declaration support is not runtime support.

## Retained baseline

Keep rich skill and resource functionality, deterministic dependencies/collisions, trust boundaries, bounded loading, and versioned restoration. Do not remove advanced resource work because the current implementation is narrower.

Preserve current public behavior unless an approved decision includes a
migration. This follow-up changes examples and their tests, not runtime implementation.
Advanced requirements remain in the target even when they are not implemented.

## Gap register

Existing gap IDs remain stable. Superseded rows identify resolved historical
findings, not removed target requirements. Old acceptance labels and erroneous
requirement associations are not carried forward as proof.

| Gap | Requirement or proposal | Current evidence or difference | State | Required outcome and owner |
| --- | --- | --- | --- | --- |
| `SKL-GAP-001` | `SKL-REQ-004`, `SKL-REQ-005`, `SKL-REQ-009`, `SKL-REQ-014`, `SKL-REQ-015` | Skill identity, validation, and activation exist; complete dependency/collision guarantees need a contribution matrix. | Implemented; evidence incomplete | Retain deterministic ordering and conflict cases. |
| `SKL-GAP-002` | `SKL-REQ-010`, `SKL-REQ-018`, `SKL-REQ-019`, `SKL-REQ-020`, `SKL-REQ-021`, `SKL-REQ-022` | Resource policy/provider boundaries exist, but the complete portable content contract needs review. | Partially implemented | Retain content type, normalization, and bounds work. |
| `SKL-GAP-003` | `SKL-REQ-015` | Action/tool contributions and runtime composition exist. General Plugin contribution collision policy is not established. | Partially implemented | Resolve with 06/08 rather than adding another composition engine. |
| `SKL-GAP-004` | `SKL-REQ-016`, `SKL-REQ-024` | Registry.ensure_started still permits lazy global startup. | Decision required | Decide host/runtime ownership and migration for lookup behavior. |
| `SKL-GAP-005` | `SKL-REQ-025` | Skill source and activation data exist; a complete versioned resource-restoration contract needs 11. | Partially implemented | Retain identity, version, and binding reference requirements. |
| `SKL-GAP-006` | `SKL-REQ-026` | The old alignment requested legacy decoding while other seams reject V2 checkpoint formats. | Decision required | Define the exact supported skill versions; do not silently add a V2 importer. |

## Reference trust review gap

[Transcript](../../../lib/jido_ai/orchestration/transcript.ex) calls
[Skill.Execution.untrusted_refs](../../../lib/jido_ai/skill/runtime.ex) for common
reference sanitization. It removes durable and skill_name fields and a forged
skill_activation kind. This creates a common context dependency on skills.

The [proposed ownership](design.md#proposed-reference-trust-boundary) moves the
shared concept to the AI Thread reference layer, not activation authority.
Resolve seam 01 trust data first. Future evidence covers forged fields,
ordinary references, and valid trusted activation. No sanitizer was moved.

## Decisions and dependency gates

Resolve explicit versus lazy registry ownership and atomic re-resolution. Define skill compatibility policy with checkpoint and authoring seams.

- Prerequisites: [03 Tools, sources, and effect policy](../03_tool_bridge/alignment.md), [06 Core runtime and Signal integration](../06_runtime_signal_integration/alignment.md), [07 Request orchestration and active input](../07_request_sessions/alignment.md).
- Dependents: 10, 11.
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

## Example-driven review

This follow-up uses the later selected decisions when older wording conflicts.
The [audit summary](../README.md#example-driven-design-audit) separates target
failures, related scenarios, API gates, and non-example release checks. All
requirements in this seam appear in the acceptance matrix below.

The new target checks extend existing example lessons. They use public APIs and
the local MockLLM transport. No target failure is skipped or changed to accept
the current behavior. Tests blocked by an unspecified public contract are
marked as a gate; no invented API is presented as an executable example.

## Acceptance matrix

Requirement IDs and target wording come from `design.md`. The evidence column
now names related example scenarios. **Related evidence is partial**, not full
requirement acceptance. A passing target check proves only its stated case.
`To be implemented — reproduced` identifies a failed target assertion, not a
failure inferred from a missing example. Source/release checks and public API
gates are separate. No row grants document approval.

| Requirement | Evidence state | Current evidence | Required acceptance outcome |
| --- | --- | --- | --- |
| `SKL-REQ-001` | Implemented; evidence incomplete | Related example evidence (partial): [the skills block adds the index loading tools and native module actions](../../../test/examples/18_skills/18_02_skill_authoring/18_02_skill_authoring_test.exs). | Verify the target behavior: A skill spec shall have a valid lowercase hyphenated name, nonempty bounded description, optional license and compatibility text, string metadata, an allowed-tool list, body reference, version, and tags. |
| `SKL-REQ-002` | Implemented; evidence incomplete | Related example evidence (partial): [the skills block adds the index loading tools and native module actions](../../../test/examples/18_skills/18_02_skill_authoring/18_02_skill_authoring_test.exs). | Verify the target behavior: Module skills and runtime specs shall produce the same validated semantic Skill Spec. |
| `SKL-REQ-003` | Implemented; evidence incomplete | Related example evidence (partial): [invalid source shapes fail without invoking a provider or reading paths](../../../test/examples/18_skills/18_02_skill_authoring/18_02_skill_authoring_test.exs); [declared sources own their catalogue provider and resource policy](../../../test/examples/18_skills/18_02_skill_authoring/18_02_skill_authoring_test.exs). | Verify the target behavior: A runtime-supplied spec shall use an inline body or an approved portable resource reference and shall not claim a local source path. |
| `SKL-REQ-004` | Implemented; evidence incomplete | Related example evidence (partial): [invalid source shapes fail without invoking a provider or reading paths](../../../test/examples/18_skills/18_02_skill_authoring/18_02_skill_authoring_test.exs); [declared sources own their catalogue provider and resource policy](../../../test/examples/18_skills/18_02_skill_authoring/18_02_skill_authoring_test.exs). | Verify the target behavior: A Skill Source shall validate paths, trust policy, specs, modules, resource policy, provider reference, and discovery bounds without reading files or invoking host callbacks. |
| `SKL-REQ-005` | Implemented; evidence incomplete | Related example evidence (partial): [invalid source shapes fail without invoking a provider or reading paths](../../../test/examples/18_skills/18_02_skill_authoring/18_02_skill_authoring_test.exs); [declared sources own their catalogue provider and resource policy](../../../test/examples/18_skills/18_02_skill_authoring/18_02_skill_authoring_test.exs). | Verify the target behavior: Untrusted or encoded input shall not contain anonymous trust functions, arbitrary module atoms, or executable callbacks. |
| `SKL-REQ-006` | Implemented; evidence incomplete | Related example evidence (partial): [trust and discovery limits fail at live startup before any model call](../../../test/examples/18_skills/18_02_skill_authoring/18_02_skill_authoring_test.exs). | Verify the target behavior: Filesystem discovery shall inspect only approved roots and shall enforce maximum depth, directory count, skill count, and excluded-directory rules. |
| `SKL-REQ-007` | Implemented; evidence incomplete | Related example evidence (partial): [trusted filesystem discovery stays lazy and resource paths stay within its root](../../../test/examples/18_skills/18_01_skill_runtime/18_01_skill_runtime_test.exs). | Verify the target behavior: Discovery shall not follow a path outside an approved root after symlink and canonical-path resolution. |
| `SKL-REQ-008` | Implemented; evidence incomplete | Related example evidence (partial): [trust and discovery limits fail at live startup before any model call](../../../test/examples/18_skills/18_02_skill_authoring/18_02_skill_authoring_test.exs). | Verify the target behavior: A discovered skill shall not enter the active catalog until its source trust policy and manifest validation succeed. |
| `SKL-REQ-009` | Implemented; evidence incomplete | Related example evidence (partial): [runtime specs win over module and filesystem sources with visible diagnostics](../../../test/examples/18_skills/18_02_skill_authoring/18_02_skill_authoring_test.exs). | Verify the target behavior: Duplicate skill names shall be an error unless an explicit source-precedence rule selects one and reports the shadowed source. |
| `SKL-REQ-010` | Implemented; evidence incomplete | Related example evidence (partial): [runtime specs win over module and filesystem sources with visible diagnostics](../../../test/examples/18_skills/18_02_skill_authoring/18_02_skill_authoring_test.exs). | Verify the target behavior: Discovery diagnostics shall identify rejected, shadowed, incompatible, truncated, and invalid skills without exposing file content or secrets. |
| `SKL-REQ-011` | Decision required | Reconcile older request-scoped wording with later SKL-REQ-027 through 030: activation is scoped to canonical Session identity. The later selected decision is the target; preserve exact skill identity/version requirements. | Verify the target behavior: Skill activation shall be request-scoped and shall return the exact selected skill names and versions. |
| `SKL-REQ-012` | Implemented; evidence incomplete | Related example evidence (partial): [a real activation survives compaction and reaches the next HTTP request](../../../test/examples/18_skills/18_01_skill_runtime/18_01_skill_runtime_test.exs). | Verify the target behavior: A skill body and skill index shall enter model context in deterministic order and within configured byte limits. |
| `SKL-REQ-013` | Implemented; evidence incomplete | Related example evidence (partial): [request tool selection applies after the automatic tools are added](../../../test/examples/18_skills/18_02_skill_authoring/18_02_skill_authoring_test.exs). | Verify the target behavior: A skill's `allowed_tools` field shall not approve a tool by itself; the host and profile tool policies shall make the final allow decision. |
| `SKL-REQ-014` | Implemented; evidence incomplete | Related example evidence (partial): [the skills block adds the index loading tools and native module actions](../../../test/examples/18_skills/18_02_skill_authoring/18_02_skill_authoring_test.exs). | Verify the target behavior: Skill Actions shall enter the effective `Jido.AI.ToolCatalog` and shall pass all tool validation and conflict rules. |
| `SKL-REQ-015` | Implemented; evidence incomplete | Related example evidence (partial): [the skills block adds the index loading tools and native module actions](../../../test/examples/18_skills/18_02_skill_authoring/18_02_skill_authoring_test.exs). | Verify the target behavior: Skill Plugins shall enter normal core Plugin composition and shall pass duplicate module, state-key, Directive, and option validation. |
| `SKL-REQ-016` | Decision required | Related example evidence (partial): [invalid source shapes fail without invoking a provider or reading paths](../../../test/examples/18_skills/18_02_skill_authoring/18_02_skill_authoring_test.exs). | Verify the target behavior: A skill shall not start a process or execute an Action during discovery or activation. |
| `SKL-REQ-017` | Implemented; evidence incomplete | Related example evidence (partial): [automatic skills reject pure Orchestration admission without a live owner](../../../test/examples/18_skills/18_02_skill_authoring/18_02_skill_authoring_test.exs). | Verify the target behavior: If a skill requires a live resource that is not available in Turn mode, profile validation or request admission shall return an explicit unsupported-mode error. |
| `SKL-REQ-018` | Implemented; evidence incomplete | Related example evidence (partial): [unlisted resource IDs fail before the provider is called](../../../test/examples/18_skills/18_01_skill_runtime/18_01_skill_runtime_test.exs); [trusted filesystem discovery stays lazy and resource paths stay within its root](../../../test/examples/18_skills/18_01_skill_runtime/18_01_skill_runtime_test.exs). | Verify the target behavior: All skill resource listing and loading shall use the configured resource provider and resource policy. |
| `SKL-REQ-019` | Implemented; evidence incomplete | Related example evidence (partial): [unlisted resource IDs fail before the provider is called](../../../test/examples/18_skills/18_01_skill_runtime/18_01_skill_runtime_test.exs); [trusted filesystem discovery stays lazy and resource paths stay within its root](../../../test/examples/18_skills/18_01_skill_runtime/18_01_skill_runtime_test.exs). | Verify the target behavior: Resource policy shall enforce maximum resources, traversal depth, directory count, listing bytes, file bytes, text bytes, and binary handling. |
| `SKL-REQ-020` | Implemented; evidence incomplete | Related example evidence (partial): [the default policy rejects a binary resource before it reaches the model](../../../test/examples/18_skills/18_01_skill_runtime/18_01_skill_runtime_test.exs). | Verify the target behavior: Text APIs shall reject binary resource content. |
| `SKL-REQ-021` | Implemented; evidence incomplete | Related example evidence (partial): [the default policy rejects a binary resource before it reaches the model](../../../test/examples/18_skills/18_01_skill_runtime/18_01_skill_runtime_test.exs). | Verify the target behavior: Binary resource content shall be rejected by default and shall enter a query only through an explicitly allowed seam 01 content-part contract. |
| `SKL-REQ-022` | Implemented; evidence incomplete | Related example evidence (partial): [trusted filesystem discovery stays lazy and resource paths stay within its root](../../../test/examples/18_skills/18_01_skill_runtime/18_01_skill_runtime_test.exs). | Verify the target behavior: Resource data sent to a model shall be bounded and shall include a safe source reference for audit. |
| `SKL-REQ-023` | Implemented; evidence incomplete | Related example evidence (partial): [trusted filesystem discovery stays lazy and resource paths stay within its root](../../../test/examples/18_skills/18_01_skill_runtime/18_01_skill_runtime_test.exs). | Verify the target behavior: A resource provider shall not expose a host filesystem path to an untrusted caller unless policy explicitly allows that path view. |
| `SKL-REQ-024` | Decision required | Related example evidence (partial): [two Agents isolate same-name activations and owner loss clears only its sessions](../../../test/examples/18_skills/18_01_skill_runtime/18_01_skill_runtime_test.exs). | Verify the target behavior: A live skill catalog shall be owned by the session Plugin runtime or an explicit host service and shall not be stored in Agent state. |
| `SKL-REQ-025` | Implemented; evidence incomplete | Related example evidence (partial): [saved instructions survive restore but resource access requires a fresh activation](../../../test/examples/18_skills/18_01_skill_runtime/18_01_skill_runtime_test.exs). | Verify the target behavior: A checkpoint shall record only selected skill identity, version, portable activation data, and resource references required for validation. |
| `SKL-REQ-026` | Decision required | Related example evidence (partial): [saved instructions survive restore but resource access requires a fresh activation](../../../test/examples/18_skills/18_01_skill_runtime/18_01_skill_runtime_test.exs). | Verify the target behavior: Resume shall re-resolve skill code and resources through approved registries and shall reject an incompatible version unless migration policy allows it. |
| `SKL-REQ-027` | Decision required | Related example evidence (partial): [different Flow workers share activation and fresh resource loads across requests](../../../test/examples/18_skills/18_01_skill_runtime/18_01_skill_runtime_test.exs); [two Agents isolate same-name activations and owner loss clears only its sessions](../../../test/examples/18_skills/18_01_skill_runtime/18_01_skill_runtime_test.exs). Current examples show sharing across requests and isolation across Agents, not canonical Session.id isolation within one Agent. | Verify the target behavior: The AgentServer AI resource owner shall index skill activations by canonical Jido.Session.id. |
| `SKL-REQ-028` | Decision required | Related example evidence (partial): [different Flow workers share activation and fresh resource loads across requests](../../../test/examples/18_skills/18_01_skill_runtime/18_01_skill_runtime_test.exs); [two Agents isolate same-name activations and owner loss clears only its sessions](../../../test/examples/18_skills/18_01_skill_runtime/18_01_skill_runtime_test.exs). Current examples show sharing across requests and isolation across Agents, not canonical Session.id isolation within one Agent. | Verify the target behavior: The AgentServer AI resource owner shall share activations between requests in the same Session and isolate activations between different Sessions. |
| `SKL-REQ-029` | Decision required | Related example evidence (partial): [a model failure retains activation in the same live Agent](../../../test/examples/18_skills/18_01_skill_runtime/18_01_skill_runtime_test.exs). | Verify the target behavior: When a request completes, is cancelled, or loses its worker, the AI resource owner shall retain that Session's activations. |
| `SKL-REQ-030` | Decision required | Related example evidence (partial): [explicit activation cleanup requires reload but preserves the committed instructions](../../../test/examples/18_skills/18_01_skill_runtime/18_01_skill_runtime_test.exs). Explicit skill cleanup is tested; closing a canonical Session is not the same operation. | Verify the target behavior: When a Session is explicitly closed, the AI resource owner shall clear that Session's activations. |
| `SKL-REQ-031` | Decision required | To be implemented: delegated peer resolves permitted resource IDs against its own Session bindings, without transferred activation authority. | Verify the target behavior: When delegated work crosses unrelated processes, the target shall resolve permitted resource IDs through its own bindings and target Session activation scope without treating transfer as activation authority. |

## Migration and compatibility

Resolve explicit versus lazy registry ownership and atomic re-resolution. Define skill compatibility policy with checkpoint and authoring seams.

Keep existing request, data, Signal, and provider contracts until a change is
approved. A documentation rename does not authorize a wire-format change.
Retained advanced proposals need their own migration and operational review.
Source paths above replace old `operations/`, `shared/`, live Session, and
`examples/v3/` references as evidence; historical paths are not current owners.

## Selected resource ownership: gaps and acceptance

Skill.Registry still supports lazy global startup; Coordinator currently
prepares skill catalogs. This is not yet the selected per-AgentServer resource
owner with Session-indexed activation lifetime. SKL-GAP-004's ownership choice
is now selected; migration and restart behavior remain open.

The [acceptance matrix](#acceptance-matrix) now contains the evidence and
remaining work for `SKL-REQ-027`, `SKL-REQ-028`, `SKL-REQ-029`, `SKL-REQ-030`, `SKL-REQ-031`.

Additional evidence: one resource owner per AgentServer, explicit worker
bindings, no default global startup, and structured missing-binding errors.
Restart cases remain blocked on a user decision; do not assume that request
cancellation clears activations or that a checkpoint guarantees restoration.
Review 06 ownership before 11 recovery. No tests ran here.

## Completion criteria

- [ ] All approved requirements have direct implementation and acceptance evidence.
- [ ] All material decisions have an explicit owner and resolution.
- [ ] Examples state what they prove and do not claim unsupported target features.
- [ ] Migrations and dependent seam reviews are complete.
- [ ] No previous test result is used as proof of an untested target requirement.
