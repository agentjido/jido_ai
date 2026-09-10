# 07 — Request Sessions Alignment

> Seam alignment plan. This document and its design are pending approval.

## Status

- Design reviewed: 2026-09-09 for alignment only.
- Code reviewed: 17c97ca04d97b26a1c7017250c90053ad674f33f.
- Prerequisites: seams 00 through 06.
- Alignment state: Blocked.
- Blockers: design approval and the package compile failure.

Proven means that current source and a direct executable test assertion exist. It does not mean that the current package test suite passes.

## Inputs And Evidence

- Target design: design.md.
- Public request and handle API: lib/jido_ai/request.ex.
- Portable request records and state Actions: lib/jido_ai/session/actions.ex.
- Admission and retention: lib/jido_ai/session/plugin.ex:20-180.
- Live runtime resources and settlement: lib/jido_ai/session/runtime.ex.
- Public Session API and snapshots: lib/jido_ai/session/session.ex:29-54 and 182-360.
- Lifecycle tests: examples/v3/test/examples/02_requests/02_01_session_test.exs:38-266.
- Inspection tests: examples/v3/test/examples/02_requests/02_22_request_inspection_test.exs.

## Retained Baseline

- Keep the Task-like Handle API for await, cancel, and await_many.
- Keep admission before work starts.
- Keep portable request records in Agent state and live Task, stream, and caller values outside it.
- Keep duplicate, busy, cancel, timeout, crash, and retention behavior.
- Keep one terminal settlement and interruption on runtime loss.
- Keep standalone requests on the same Agent and Session path.

## Gap Register

| Gap | Requirement | Current evidence | Difference | Disposition |
| --- | --- | --- | --- | --- |
| SES-GAP-001 | SES-REQ-022 | request.ex:337-339 | await_many uses Task.async_stream as a helper. Its resource and ordering contract needs direct proof. | Add ordering, timeout, and cleanup tests or replace with a simpler bounded wait path. |
| SES-GAP-002 | SES-REQ-026 | actions.ex and plugin.ex | Start and settle transitions are guarded, but rollback behavior is not one explicit documented contract. | Define rollback for every rejected or failed state transition. |
| SES-GAP-003 | SES-REQ-028 | steering support in session.ex | Steering exists, but the approved portable control field set and source references are not fully proved. | Define the control value and add malformed and stale control tests. |
| SES-GAP-004 | SES-REQ-030 | session/runtime.ex | Caller monitoring exists, but full caller-down behavior for each request mode needs an acceptance matrix. | Add caller-down tests for await, stream, and detached modes. |
| SES-GAP-005 | Blocker: package compile failure | package compile output | Direct lifecycle tests cannot run until context_operations.ex aligns with the sibling Jido API. | Fix the dependency seam first, then rerun all lifecycle tests. |

## High-Level Work Sequence

This sequence defines outcomes and gates. Detailed implementation planning comes after design approval.

1. Approve request record, handle, control, and terminal settlement contracts.
2. Document and test start, reject, settle, cancel, timeout, crash, and rollback transitions.
3. Prove live-resource separation and snapshot portability.
4. Complete steering and caller-down behavior.
5. Prove retention, duplicate, and concurrent await_many behavior.
6. Run the full lifecycle and inspection test set after the compile blocker is removed.

## Acceptance Matrix

| Requirement | Current evidence | Required evidence | State |
| --- | --- | --- | --- |
| SES-REQ-001 | Session submit exists | Passing submit tests | Proven |
| SES-REQ-002 | admission runs before start | Passing rejection-before-work tests | Proven |
| SES-REQ-003 | request IDs are stable | Passing identity tests | Proven |
| SES-REQ-004 | run IDs are stored | Passing run correlation tests | Proven |
| SES-REQ-005 | portable record struct exists | Passing portability tests | Proven |
| SES-REQ-006 | live resources are separate | Passing snapshot checks | Proven |
| SES-REQ-007 | busy policy exists | Passing busy tests | Proven |
| SES-REQ-008 | duplicate policy exists | Passing duplicate tests | Proven |
| SES-REQ-009 | retention is bounded | Passing retention tests | Proven |
| SES-REQ-010 | Handle is returned | Passing handle API tests | Proven |
| SES-REQ-011 | await exists | Passing await result tests | Proven |
| SES-REQ-012 | await timeout does not cancel | Passing timeout test | Proven |
| SES-REQ-013 | cancel exists | Passing cancel tests | Proven |
| SES-REQ-014 | cancel is idempotent | Passing repeated cancel tests | Proven |
| SES-REQ-015 | settlement is guarded | Passing one-settlement tests | Proven |
| SES-REQ-016 | cancel race is tested | Passing race tests | Proven |
| SES-REQ-017 | runtime crash interrupts | Passing crash recovery test | Proven |
| SES-REQ-018 | terminal records persist | Passing inspection tests | Proven |
| SES-REQ-019 | stream resources stay live-only | Passing snapshot tests | Proven |
| SES-REQ-020 | stream sequence is ordered | Passing stream tests | Proven |
| SES-REQ-021 | one terminal event exists | Passing terminal stream tests | Proven |
| SES-REQ-022 | await_many is bounded | Full order, timeout, and cleanup proof | Partial |
| SES-REQ-023 | multiple waiters are supported | Passing waiter tests | Proven |
| SES-REQ-024 | lookup and inspection exist | Passing inspection tests | Proven |
| SES-REQ-025 | terminal data is sanitized | Passing safe projection tests | Proven |
| SES-REQ-026 | transition guards exist | Explicit rollback contract tests | Partial |
| SES-REQ-027 | steering exists | Passing accepted steering tests | Proven |
| SES-REQ-028 | control data is partly defined | Approved portable control value tests | Partial |
| SES-REQ-029 | stale control is rejected | Passing request reference tests | Proven |
| SES-REQ-030 | caller monitoring exists | Complete caller-down mode matrix | Partial |
| SES-REQ-031 | standalone uses Agent and Session | Passing parity tests | Proven |
| SES-REQ-032 | no durable alternate runner | Passing ownership tests | Proven |
| SES-REQ-033 | request actions use Agent state | Passing state transition tests | Proven |
| SES-REQ-034 | request signals are emitted | Passing lifecycle signal tests | Proven |

## Migration And Compatibility

- Keep current Session and Handle function names.
- Keep current request records readable while new fields use defaults.
- Treat any Task, PID, monitor, stream recipient, or provider value as live-only.
- Convert old terminal records through a versioned compatibility path.

## Assumptions And Blockers

- Session is the durable request owner. A standalone request is only a convenience wrapper.
- Core Agent and Plugin behavior remains the state transition authority.
- Package compile failure blocks the final lifecycle gate.

## Completion Criteria

- Every request transition has one defined result and rollback rule.
- Portable state contains no live runtime value.
- Cancellation, timeout, crash, duplicate, busy, waiter, steering, and caller-down races pass tests.
- Standalone and hosted requests use the same durable Session path.
