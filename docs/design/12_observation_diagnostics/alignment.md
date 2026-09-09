# 12 — Observation And Diagnostics Alignment

> Seam alignment plan. This document and its design are pending approval.

## Status

- Design reviewed: 2026-09-09 for alignment only.
- Code reviewed: 17c97ca04d97b26a1c7017250c90053ad674f33f.
- Prerequisites: all runtime seams, especially 04, 06, 07, and 11.
- Alignment state: Blocked.
- Blockers: design approval, package compile failure, and unsafe default projections.

Proven means that current source and a direct executable test assertion exist. It does not mean that the current package test suite passes.

## Inputs And Evidence

- Target design: design.md.
- Runtime observation: lib/jido_ai/shared/observe.ex and lib/jido_ai/shared/observe_sanitize.ex.
- Runtime events: lib/jido_ai/shared/runtime_event.ex.
- Typed signals: lib/jido_ai/signals.
- Session inspection: lib/jido_ai/session/session.ex and lib/jido_ai/session/runtime.ex.
- Telemetry tests: test/jido_ai/observe_test.exs:159-330.
- Current tool result metadata behavior: test/jido_ai/observe_test.exs:121-135.
- Current thinking projections: examples/v3/test/examples/02_requests/02_07_response_metadata_test.exs:114-133.
- Trace retention evidence: examples/v3/test/examples/02_requests/02_22_request_inspection_test.exs.

## Retained Baseline

- Keep the jido.ai telemetry prefix and current request lifecycle events.
- Keep stable request, run, model call, tool call, and sequence identifiers.
- Keep duration, usage, limit, and terminal outcome measurements.
- Keep typed Signals and bounded Session inspection.
- Keep sanitization before telemetry, signal, log, checkpoint, and inspection output.
- Keep observability as projection only. It must not become an execution owner.

## Gap Register

| Gap | Requirement | Current evidence | Difference | Disposition |
| --- | --- | --- | --- | --- |
| OBS-GAP-001 | OBS-REQ-001, OBS-REQ-002 | Runtime.Event and Signal definitions | There is no single approved semantic event value with uniform profile and correlation fields. | Define one portable Event and project all telemetry, signals, logs, and inspection from it. |
| OBS-GAP-002 | OBS-REQ-003, OBS-REQ-004, OBS-REQ-011 | observe.ex and telemetry tests | Measurements and metadata exist, but not every event uses one complete stable schema and low-cardinality rule. | Add an event catalog and schema tests. |
| OBS-GAP-003 | OBS-REQ-006 | current resume behavior | Resume can reuse the old run ID, so resumed event lineage conflicts with the target identity rule. | Complete RES-GAP-003 first. |
| OBS-GAP-004 | OBS-REQ-008, OBS-REQ-022 | observe_test.exs:121-135 | Telemetry metadata can keep nested tool result content by default. | Replace content with bounded summaries or explicit opt-in projections. |
| OBS-GAP-005 | OBS-REQ-023, OBS-REQ-029 | 02_07_response_metadata_test.exs:114-133 | Thinking content is present in stored response metadata and typed Signals by default. | Exclude thinking from default public projections and require an explicit trusted policy. |
| OBS-GAP-006 | OBS-REQ-028, OBS-REQ-030, OBS-REQ-031 | current inspection and telemetry modules | Cardinality enforcement, schema compatibility, and end-to-end projection conformance are incomplete. | Add hard cardinality checks, event versions, and projection golden tests. |

## High-Level Work Sequence

This sequence defines outcomes and gates. Detailed implementation planning comes after design approval.

1. Approve the semantic Event, event catalog, versions, and projection policies.
2. Standardize IDs, sequence, attempt, duration, usage, limit, and terminal fields.
3. Remove full tool result and thinking content from default projections.
4. Add low-cardinality and size enforcement before emit.
5. Align resume lineage with the new run ID rule.
6. Run telemetry, signal, log, checkpoint, inspection, and secret-leak conformance tests.

## Acceptance Matrix

| Requirement | Current evidence | Required evidence | State |
| --- | --- | --- | --- |
| OBS-REQ-001 | Runtime.Event exists | One approved semantic Event | Partial |
| OBS-REQ-002 | main IDs exist | Uniform profile and correlation fields | Partial |
| OBS-REQ-003 | event names exist | Versioned event catalog tests | Partial |
| OBS-REQ-004 | measurements exist | Complete stable measurement schema | Partial |
| OBS-REQ-005 | sequence numbers exist | Passing monotonic sequence tests | Proven |
| OBS-REQ-006 | resume can reuse run ID | New-run lineage events | Conflict |
| OBS-REQ-007 | attempt data exists in parts | Passing attempt correlation tests | Proven |
| OBS-REQ-008 | tool result content can be emitted | Bounded summary by default | Conflict |
| OBS-REQ-009 | errors are sanitized | Passing secret-redaction tests | Proven |
| OBS-REQ-010 | usage is normalized | Complete usage event tests | Partial |
| OBS-REQ-011 | telemetry prefix is stable | Full approved event prefix matrix | Partial |
| OBS-REQ-012 | spans are tested | Passing start, stop, and exception tests | Proven |
| OBS-REQ-013 | duration is measured | Passing monotonic duration tests | Proven |
| OBS-REQ-014 | terminal outcome is emitted | Passing terminal event tests | Proven |
| OBS-REQ-015 | stream kinds are tagged | One approved tagged event union | Partial |
| OBS-REQ-016 | signals project runtime events | Passing projection tests | Proven |
| OBS-REQ-017 | logs use sanitization | Passing safe log tests | Proven |
| OBS-REQ-018 | checkpoint errors are safe | Passing checkpoint error tests | Proven |
| OBS-REQ-019 | inspection is bounded | Passing retention tests | Proven |
| OBS-REQ-020 | partial usage is retained | Passing failure usage tests | Proven |
| OBS-REQ-021 | limit reasons are available | Passing limit event tests | Proven |
| OBS-REQ-022 | some payloads remain too rich | Strict default payload summaries | Conflict |
| OBS-REQ-023 | thinking is public by default | Explicit trusted opt-in only | Conflict |
| OBS-REQ-024 | secret sanitization exists | Passing cross-projection secret tests | Proven |
| OBS-REQ-025 | provider values normalize | Passing provider-boundary tests | Proven |
| OBS-REQ-026 | one terminal stream event exists | Passing terminal uniqueness tests | Proven |
| OBS-REQ-027 | trace retention is capped | Passing cap and eviction tests | Proven |
| OBS-REQ-028 | tag use is informal | Enforced low-cardinality policy | Partial |
| OBS-REQ-029 | inspection exposes thinking | Safe inspection by default | Conflict |
| OBS-REQ-030 | no event compatibility suite | Versioned compatibility fixtures | Missing |
| OBS-REQ-031 | no full projection golden suite | End-to-end projection conformance tests | Missing |

## Migration And Compatibility

- Keep current telemetry event names through a versioned projection adapter where possible.
- Keep current Signal modules but build their data from the approved semantic Event.
- Make rich tool data and thinking content opt-in, trusted, and bounded.
- Decode older stored inspection events through an explicit legacy projection.

## Assumptions And Blockers

- Telemetry consumers need a documented compatibility period.
- Thinking content is sensitive even when it does not contain a known credential.
- Package compile failure blocks the complete event conformance run.

## Completion Criteria

- One semantic Event produces every telemetry, Signal, log, checkpoint, and inspection projection.
- Default projections contain no secret, full tool result, raw provider value, or thinking content.
- Event fields are versioned, bounded, low-cardinality, and correlation-complete.
- Golden projection and compatibility tests pass.
