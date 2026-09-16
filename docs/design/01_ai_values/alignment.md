> Seam alignment review. Pending approval.

# Canonical interaction and AI values alignment

## Status

- Reviewed: 2026-09-15.
- Code for the example audit: `v3-spike`, HEAD `7bb011e98349af8bf580e7b93afa60990972beae`, plus uncommitted example, test, formatter, and documentation changes. No `lib/` or dependency changes.
- Prerequisite alignments used: [00 Package boundary and invariants](../00_boundary_invariants/alignment.md).
- Alignment state: Draft. Current ownership is mapped; target decisions and full acceptance proof remain.
- Verification: the example-driven review below adds fresh MockLLM runs to the earlier source review. Earlier statements that no tests ran refer to that prior review, not this follow-up.

## Current architecture

Jido.Session owns a Thread of Entry values. These values are process-free and have explicit codecs. Thread.Projection adapts them for AI use; Orchestration.Transcript connects them to a selected Agent field. Turn no longer executes tools. Error uses Splode classes and a runtime envelope with type, message, details, and retryable? rather than the proposed single category/code struct.

- Current owner: Jido.Session, Jido.Thread, Jido.Thread.Entry, Query, Turn, Output, Usage, Error, and Thread.Projection.
- Cross-package ownership: core Jido owns Agent commit and topology; Flow/Exec and Signal internals remain in their respective packages.
- Overall placement: [architecture overview](../ARCHITECTURE.md).
- Full target: [design](design.md). Use canonical Session/Thread values for conversation data. Preserve multimodal content, correlation, output validation, safe errors, and explicit portable encodings. Broader constructor uniformity and strict provider-neutral content remain decisions.

## Inputs and evidence

### Canonical code

| Source | Evidence scope |
| --- | --- |
| [lib/jido_session.ex](../../../lib/jido_session.ex) | Session value and codec |
| [lib/jido_thread.ex](../../../lib/jido_thread.ex) | Append-only Thread value |
| [lib/jido_thread/entry.ex](../../../lib/jido_thread/entry.ex) | Entry schema |
| [lib/jido_ai/thread/projection.ex](../../../lib/jido_ai/thread/projection.ex) | AI projection |
| [lib/jido_ai/turn.ex](../../../lib/jido_ai/turn.ex) | Response value only |
| [lib/jido_ai/error.ex](../../../lib/jido_ai/error.ex) | Splode and runtime envelope |

### Examples and tests

- [Example briefing](../../../examples/02_requests/02_27_thread_session_values/README.md): public behavior and documented limits.
- [Matching example tests](../../../test/examples/02_requests/02_27_thread_session_values): deterministic example evidence.
- [test/jido_ai/thread_value_test.exs](../../../test/jido_ai/thread_value_test.exs): detailed boundary evidence.
- [test/jido_ai/tools/executor_boundary_test.exs](../../../test/jido_ai/tools/executor_boundary_test.exs): detailed boundary evidence.

These are evidence entry points, not blanket acceptance claims. The requirement
matrix below separates target decisions from implemented behavior whose full
proof is still incomplete. Inert declaration support is not runtime support.

## Retained baseline

Use canonical Session/Thread values for conversation data. Preserve multimodal content, correlation, output validation, safe errors, and explicit portable encodings. Broader constructor uniformity and strict provider-neutral content remain decisions.

Preserve current public behavior unless an approved decision includes a
migration. The initial audit changed examples and tests. The implementation follow-up also changes the runtime; see the current evidence below.
Advanced requirements remain in the target even when they are not implemented.

## Gap register

Existing gap IDs remain stable. Superseded rows identify resolved historical
findings, not removed target requirements. Old acceptance labels and erroneous
requirement associations are not carried forward as proof.

| Gap | Requirement or proposal | Current evidence or difference | State | Required outcome and owner |
| --- | --- | --- | --- | --- |
| `VAL-GAP-001` | `VAL-REQ-001`, `VAL-REQ-002` | Constructors have established return contracts; Session.new returns a value. The universal tagged-error proposal would be a migration. | Decision required | Specify constructor families rather than silently changing them. |
| `VAL-GAP-002` | `VAL-REQ-008`, `VAL-REQ-009`, `VAL-REQ-021`, `VAL-REQ-022` | Session/Thread codecs and projection replace Context. The former gap cited output requirements as context requirements. | Partially implemented | Use VAL-REQ-008/009/021/022 for ordering, projection, and encoding evidence. |
| `VAL-GAP-003` | Resolved execution ownership; not VAL-REQ-012 | Tools.Executor owns execution; the old Turn execution helper is removed. | Superseded | Preserve the executor-boundary regression test. VAL-REQ-012 concerns content separation, not tool execution. |
| `VAL-GAP-004` | `VAL-REQ-019` | Current errors use Splode and type/message/details/retryable? envelopes, not one category/code value. | Decision required | Decide taxonomy and compatibility in the target. |
| `VAL-GAP-005` | `VAL-REQ-020` | Error and observation sanitizers exist; an old leak claim is not carried forward as a current defect without reproduction. | Implemented; evidence incomplete | Audit all projections and match tests to VAL-REQ-020. |
| `VAL-GAP-006` | `VAL-REQ-021`, `VAL-REQ-022` | Canonical conversation codecs are versioned. A universal encoding contract for every public value is broader. | Partially implemented | Define which values are encoded and which remain runtime-only. |

## Data-boundary review gap

[Proposed batch values](design.md#proposed-entry-batch-and-receipt-values) are
not current APIs. Runtime history_delta holds message maps.
[Projection](../../../lib/jido_ai/thread/projection.ex) converts them to entries
at append time; IDs are assigned then. [Thread](../../../lib/jido_thread.ex)
assigns sequence and validates contiguous sequence, revision, and count, but
does not reject duplicate entry IDs. Native payload preservation and
open-tool-call validation already exist and remain foundations.

Before implementation, specify stable-ID creation, expected-revision checks,
duplicate policy, and receipt validity. Future evidence includes repeated
batches, stale revisions, native tool-call/result linkage, and payload
round trips. Prerequisite: seam 00 data direction; consumers: 04, 07, 09, 11.
No new tests ran in this review.

## Success-only projection gap

[Thread.Projection](../../../lib/jido_ai/thread/projection.ex) selects messages
by context operations and lanes, without the selected successful-settlement
boundary. It cannot yet separate retained failed-work evidence from the next
default model context as required by VAL-REQ-023/024.

The [acceptance matrix](#acceptance-matrix) now contains the evidence and
remaining work for `VAL-REQ-023`, `VAL-REQ-024`.

See the [scenario plan](../07_request_sessions/alignment.md#selected-conversation-policy-gaps-and-acceptance).
Promotion metadata and deferred replacement depend on seam 07 settlement.
No new tests ran in this review.

## Decisions and dependency gates

Resolve tagged constructor uniformity, provider-native content acceptance, and the proposed error taxonomy without reintroducing Context or History stores.

- Prerequisites: [00 Package boundary and invariants](../00_boundary_invariants/alignment.md).
- Dependents: 02, 03, 06.
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
| `VAL-REQ-001` | Decision required | Related example evidence (partial): [versioned documents round-trip and reject runtime data](../../../test/examples/02_requests/02_27_thread_session_values/02_27_thread_session_values_test.exs). | Verify the target behavior: When a caller constructs a public AI value, the owning module shall validate it with a Zoi schema and return `{:ok, value}` or `{:error, %Jido.AI.Error{}}`. |
| `VAL-REQ-002` | Implemented; evidence incomplete | Target scenario passed: [VAL-REQ-002 target check](../../../test/examples/02_requests/02_27_thread_session_values/design_requirements_test.exs). Session rejects an unknown encoded key without creating an atom and rejects a future version. Other values and supported-version-range reporting remain unproved. Related example evidence (partial): [versioned documents round-trip and reject runtime data](../../../test/examples/02_requests/02_27_thread_session_values/02_27_thread_session_values_test.exs). | Verify the target behavior: Each public AI value shall reject unknown fields by default at an encoded or untrusted boundary. |
| `VAL-REQ-003` | Implemented; evidence incomplete | Related example evidence (partial): [versioned documents round-trip and reject runtime data](../../../test/examples/02_requests/02_27_thread_session_values/02_27_thread_session_values_test.exs). | Verify the target behavior: Each portable AI value shall contain only data accepted by the package portability rule. |
| `VAL-REQ-004` | Implemented; evidence incomplete | Target scenario passed: [VAL-REQ-004 target check](../../../test/examples/02_requests/02_27_thread_session_values/design_requirements_test.exs). Session rejects an unknown encoded key without creating an atom and rejects a future version. Other values and supported-version-range reporting remain unproved. Related example evidence (partial): [versioned documents round-trip and reject runtime data](../../../test/examples/02_requests/02_27_thread_session_values/02_27_thread_session_values_test.exs). | Verify the target behavior: When a string-keyed map enters a public schema, the owning module shall normalize only known keys and shall not create atoms from untrusted input. |
| `VAL-REQ-005` | Implemented; evidence incomplete | Related example evidence (partial): [media query, model options, refs and real tool output reach the provider](../../../test/examples/02_requests/02_01_session/02_01_session_test.exs). | Verify the target behavior: A query shall be nonempty text or a nonempty ordered list of supported content parts. |
| `VAL-REQ-006` | Decision required | Related example evidence (partial): [media query, model options, refs and real tool output reach the provider](../../../test/examples/02_requests/02_01_session/02_01_session_test.exs). | Verify the target behavior: When a caller adds a file reference, the query contract shall preserve the file identifier, media type, filename, and safe metadata without requiring a provider struct. |
| `VAL-REQ-007` | Implemented; evidence incomplete | Target scenario repaired: [VAL-REQ-007 target check](../../../test/examples/02_requests/02_27_thread_session_values/design_requirements_test.exs). Query summaries omit unsupported and hidden-thinking parts instead of inspecting their payloads. Full-clause and provider-matrix proof remains separate. | Verify the target behavior: When Jido AI summarizes multimodal content for logs or events, it shall not expose binary content, file bytes, credentials, or hidden thinking text. |
| `VAL-REQ-008` | Implemented; evidence incomplete | Related example evidence (partial): [three dependent tool rounds precede the committed answer](../../../test/examples/01_authoring/01_02_tool_flow/multi_round_test.exs). | Verify the target behavior: A context shall preserve semantic message order, roles, tool-call correlation, reasoning details when allowed, and caller references. |
| `VAL-REQ-009` | Implemented; evidence incomplete | Target scenario passed: [VAL-REQ-009 target check](../../../test/examples/02_requests/02_27_thread_session_values/design_requirements_test.exs). Projection leaves the encoded Thread unchanged. This does not prove every projection policy. Related example evidence (partial): [three dependent tool rounds precede the committed answer](../../../test/examples/01_authoring/01_02_tool_flow/multi_round_test.exs). | Verify the target behavior: Projection to a provider request shall be an adapter operation and shall not change the stored context. |
| `VAL-REQ-010` | Implemented; evidence incomplete | Related example evidence (partial): [complete content parts and reasoning stay intact through Signal and Turn conversion](../../../test/examples/02_requests/02_16_typed_signals/02_16_typed_signals_test.exs). | Verify the target behavior: A normalized turn shall identify exactly one response class: `:final_answer` or `:tool_calls`. |
| `VAL-REQ-011` | Implemented; evidence incomplete | Related example evidence (partial): [three dependent tool rounds precede the committed answer](../../../test/examples/01_authoring/01_02_tool_flow/multi_round_test.exs). | Verify the target behavior: A turn with tool calls shall preserve provider order and stable call identifiers. |
| `VAL-REQ-012` | Decision required | Related example evidence (partial): [complete content parts and reasoning stay intact through Signal and Turn conversion](../../../test/examples/02_requests/02_16_typed_signals/02_16_typed_signals_test.exs). | Verify the target behavior: A turn shall preserve ordered visible content separately from private thinking or provider reasoning details. |
| `VAL-REQ-013` | Implemented; evidence incomplete | Related example evidence (partial): [schema feedback reaches one repair before a valid object commits](../../../test/examples/01_authoring/01_03_structured_output/01_03_structured_output_test.exs); [repair exhaustion preserves complete prior state and a later request succeeds](../../../test/examples/01_authoring/01_03_structured_output/01_03_structured_output_test.exs). | Verify the target behavior: An output contract shall accept an object-shaped Zoi schema or object-shaped JSON Schema and shall reject a non-object root. |
| `VAL-REQ-014` | Implemented; evidence incomplete | Related example evidence (partial): [schema feedback reaches one repair before a valid object commits](../../../test/examples/01_authoring/01_03_structured_output/01_03_structured_output_test.exs); [repair exhaustion preserves complete prior state and a later request succeeds](../../../test/examples/01_authoring/01_03_structured_output/01_03_structured_output_test.exs). | Verify the target behavior: When output validation fails, the output contract shall apply the configured `:error` or bounded `:repair` policy. |
| `VAL-REQ-015` | Implemented; evidence incomplete | Related example evidence (partial): [schema feedback reaches one repair before a valid object commits](../../../test/examples/01_authoring/01_03_structured_output/01_03_structured_output_test.exs); [repair exhaustion preserves complete prior state and a later request succeeds](../../../test/examples/01_authoring/01_03_structured_output/01_03_structured_output_test.exs). | Verify the target behavior: A repair attempt shall never exceed the configured retry limit and shall return the last validation error when the limit is reached. |
| `VAL-REQ-016` | Implemented; evidence incomplete | Public-contract gate: Output.fingerprint/1 exists as an undocumented internal function. Select a supported public identity observation before adding an output-identity example; do not expose an internal helper just for the test. | Verify the target behavior: An output contract shall have a deterministic fingerprint based on its portable semantic fields. |
| `VAL-REQ-017` | Implemented; evidence incomplete | Related example evidence (partial): [failed provider invocations retain unknown usage and consume a request slot](../../../test/examples/13_policy/13_01_quota/13_01_quota_test.exs). | Verify the target behavior: Usage normalization shall provide nonnegative `input_tokens`, `output_tokens`, and `total_tokens` when provider data contains those counts. |
| `VAL-REQ-018` | Implemented; evidence incomplete | Related example evidence (partial): [failed provider invocations retain unknown usage and consume a request slot](../../../test/examples/13_policy/13_01_quota/13_01_quota_test.exs). | Verify the target behavior: Usage merge shall sum known numeric counters and preserve bounded provider metadata without replacing canonical counters. |
| `VAL-REQ-019` | Decision required | Related example evidence (partial): [provider errors keep the native ReqLLM tagged result](../../../test/examples/01_authoring/01_08_model_helpers/01_08_model_helpers_test.exs). | Verify the target behavior: Every public AI error shall include a stable category and code, a safe message, bounded details, and an optional cause. |
| `VAL-REQ-020` | Implemented; evidence incomplete | Related example evidence (partial): [provider errors keep the native ReqLLM tagged result](../../../test/examples/01_authoring/01_08_model_helpers/01_08_model_helpers_test.exs). | Verify the target behavior: Error inspection and telemetry conversion shall redact credentials, request bodies, raw file content, and configured sensitive keys. |
| `VAL-REQ-021` | Decision required | Related example evidence (partial): [versioned documents round-trip and reject runtime data](../../../test/examples/02_requests/02_27_thread_session_values/02_27_thread_session_values_test.exs). | Verify the target behavior: Every value that can enter a Signal, profile, Agent state, or checkpoint shall have a versioned portable encoding contract. |
| `VAL-REQ-022` | Implemented; evidence incomplete | Target scenario passed: [VAL-REQ-022 target check](../../../test/examples/02_requests/02_27_thread_session_values/design_requirements_test.exs). Session rejects an unknown encoded key without creating an atom and rejects a future version. Other values and supported-version-range reporting remain unproved. Related example evidence (partial): [versioned documents round-trip and reject runtime data](../../../test/examples/02_requests/02_27_thread_session_values/02_27_thread_session_values_test.exs). | Verify the target behavior: A decoder shall reject an unsupported future version and shall identify the supported version range. |
| `VAL-REQ-023` | Implemented; evidence incomplete | Target scenario repaired: [VAL-REQ-023 target check](../../../test/examples/02_requests/02_02_steering/design_requirements_test.exs). Pending request messages remain evidence until a matching successful-settlement entry promotes them. Full-clause and provider-matrix proof remains separate. | Verify the target behavior: The default Thread model projection shall include request work only after successful settlement promotes it into the completed conversation. |
| `VAL-REQ-024` | Implemented; evidence incomplete | Target scenario repaired: [VAL-REQ-024 target check](../../../test/examples/02_requests/02_27_thread_session_values/design_requirements_test.exs). Default projection omits incomplete or mismatched tool exchanges without inventing results. Full-clause and provider-matrix proof remains separate. | Verify the target behavior: The default Thread model projection shall exclude unresolved tool exchanges without inventing tool results. |

## Migration and compatibility

Resolve tagged constructor uniformity, provider-native content acceptance, and the proposed error taxonomy without reintroducing Context or History stores.

Keep existing request, data, Signal, and provider contracts until a change is
approved. A documentation rename does not authorize a wire-format change.
Retained advanced proposals need their own migration and operational review.
Source paths above replace old `operations/`, `shared/`, live Session, and
`examples/v3/` references as evidence; historical paths are not current owners.

## Runtime repair follow-up

The current worktree adds runtime repairs over the audit baseline. Dependencies
are unchanged. The [audit summary](../README.md#example-driven-design-audit)
separates the repaired scenarios from the remaining advanced API gates. A passing
scenario is not complete requirement conformance.

## Completion criteria

- [ ] All approved requirements have direct implementation and acceptance evidence.
- [ ] All material decisions have an explicit owner and resolution.
- [ ] Examples state what they prove and do not claim unsupported target features.
- [ ] Migrations and dependent seam reviews are complete.
- [ ] No previous test result is used as proof of an untested target requirement.
