> Seam alignment review. Pending approval.

# Canonical interaction and AI values alignment

## Status

- Reviewed: 2026-09-15.
- Code: `v3-spike`, HEAD `c4e57c8d34d09ffc922c37fb41cccc2e1491123e`, plus the uncommitted Orchestration and canonical-value file reorganization.
- Prerequisite alignments used: [00 Package boundary and invariants](../00_boundary_invariants/alignment.md).
- Alignment state: Draft. Current ownership is mapped; target decisions and full acceptance proof remain.
- Verification: source and test inspection in this documentation task. The preceding code-change run reported 2,809 passing tests and one existing exclusion, including authoring and MockLLM examples. That run is not proof of every target requirement; no Elixir tests were rerun here.

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
migration. No runtime or example changes are authorized by this review.
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

| Requirement | Evidence state | Acceptance outcome |
| --- | --- | --- |
| VAL-REQ-023 | Proposed; not implemented | Successful work advances default context; failed/cancelled work does not |
| VAL-REQ-024 | Proposed; not implemented | Unresolved tool exchanges are excluded without fabricated results |

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

## Acceptance matrix

This table is rebuilt from the actual requirement IDs in `design.md`; earlier
tables sometimes mapped evidence to the wrong requirement. “Implemented;
evidence incomplete” means the subsystem has relevant code, not that every
clause is met. No row below grants approval or claims a fresh test run.

| Requirement | Evidence state | Current evidence | Required acceptance outcome |
| --- | --- | --- | --- |
| `VAL-REQ-001` | Decision required | See current contract and gap register | Verify the target behavior: When a caller constructs a public AI value, the owning module shall validate it with a Zoi schema and return `{:ok, value}` or `{:error, %Jido.AI.Error{}}`. |
| `VAL-REQ-002` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: Each public AI value shall reject unknown fields by default at an encoded or untrusted boundary. |
| `VAL-REQ-003` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: Each portable AI value shall contain only data accepted by the package portability rule. |
| `VAL-REQ-004` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: When a string-keyed map enters a public schema, the owning module shall normalize only known keys and shall not create atoms from untrusted input. |
| `VAL-REQ-005` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: A query shall be nonempty text or a nonempty ordered list of supported content parts. |
| `VAL-REQ-006` | Decision required | See current contract and gap register | Verify the target behavior: When a caller adds a file reference, the query contract shall preserve the file identifier, media type, filename, and safe metadata without requiring a provider struct. |
| `VAL-REQ-007` | Decision required | See current contract and gap register | Verify the target behavior: When Jido AI summarizes multimodal content for logs or events, it shall not expose binary content, file bytes, credentials, or hidden thinking text. |
| `VAL-REQ-008` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: A context shall preserve semantic message order, roles, tool-call correlation, reasoning details when allowed, and caller references. |
| `VAL-REQ-009` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: Projection to a provider request shall be an adapter operation and shall not change the stored context. |
| `VAL-REQ-010` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: A normalized turn shall identify exactly one response class: `:final_answer` or `:tool_calls`. |
| `VAL-REQ-011` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: A turn with tool calls shall preserve provider order and stable call identifiers. |
| `VAL-REQ-012` | Decision required | See current contract and gap register | Verify the target behavior: A turn shall preserve ordered visible content separately from private thinking or provider reasoning details. |
| `VAL-REQ-013` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: An output contract shall accept an object-shaped Zoi schema or object-shaped JSON Schema and shall reject a non-object root. |
| `VAL-REQ-014` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: When output validation fails, the output contract shall apply the configured `:error` or bounded `:repair` policy. |
| `VAL-REQ-015` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: A repair attempt shall never exceed the configured retry limit and shall return the last validation error when the limit is reached. |
| `VAL-REQ-016` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: An output contract shall have a deterministic fingerprint based on its portable semantic fields. |
| `VAL-REQ-017` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: Usage normalization shall provide nonnegative `input_tokens`, `output_tokens`, and `total_tokens` when provider data contains those counts. |
| `VAL-REQ-018` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: Usage merge shall sum known numeric counters and preserve bounded provider metadata without replacing canonical counters. |
| `VAL-REQ-019` | Decision required | See current contract and gap register | Verify the target behavior: Every public AI error shall include a stable category and code, a safe message, bounded details, and an optional cause. |
| `VAL-REQ-020` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: Error inspection and telemetry conversion shall redact credentials, request bodies, raw file content, and configured sensitive keys. |
| `VAL-REQ-021` | Decision required | See current contract and gap register | Verify the target behavior: Every value that can enter a Signal, profile, Agent state, or checkpoint shall have a versioned portable encoding contract. |
| `VAL-REQ-022` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: A decoder shall reject an unsupported future version and shall identify the supported version range. |

## Migration and compatibility

Resolve tagged constructor uniformity, provider-native content acceptance, and the proposed error taxonomy without reintroducing Context or History stores.

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
