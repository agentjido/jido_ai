# 04 — AI Execution Alignment

> Seam alignment plan. This document and its design are pending approval.

## Status

- Design reviewed: 2026-09-09 for alignment only.
- Code reviewed: 17c97ca04d97b26a1c7017250c90053ad674f33f.
- Prerequisites: seams 00 through 03.
- Alignment state: Blocked.
- Blockers: design approval and the package compile failure.

Proven means that current source and a direct executable test assertion exist. It does not mean that the current package test suite passes.

## Inputs And Evidence

- Target design: design.md.
- Canonical Flow construction: lib/jido_ai/authoring/authoring.ex:231-243.
- Model, decision, tool, and final stages: lib/jido_ai/operations/runtime.ex:324-985.
- Standalone compatibility runner: lib/jido_ai/operations/react_runner.ex.
- Stream sequence and terminal kinds: lib/jido_ai/request/stream.ex:13-144.
- Session stream projection: lib/jido_ai/session/runtime.ex:830-864.
- V3 examples: 01_02_tool_flow_test.exs, 01_05_streaming_test.exs, 02_13_tool_limits_test.exs, 02_14_stream_activity_test.exs, 02_20_call_counts_test.exs, and 02_24_stream_usage_test.exs.
- Runtime correlation test: test/jido_ai/react/runtime_runner_test.exs:394-417.

## Retained Baseline

- Keep one shared AI Flow for model, decision, tool, and final stages.
- Keep Jido.Exec as the Action execution owner.
- Keep stable request, run, model call, and tool call IDs.
- Keep ordered request stream sequence numbers and one terminal event.
- Keep bounded model calls, tool rounds, tool calls, and structured repair.
- Keep partial usage on terminal failure.

## Gap Register

| Gap | Requirement | Current evidence | Difference | Disposition |
| --- | --- | --- | --- | --- |
| EXE-GAP-001 | EXE-REQ-005, EXE-REQ-006 | runtime.ex:324-985 | Stage inputs exist, but a full portable public ExecutionState contract is not proved. | Define the state value and validate every stage transition. |
| EXE-GAP-002 | EXE-REQ-009, EXE-REQ-012, EXE-REQ-013 | runtime events and stream projection | IDs exist, but full correlation and attempt metadata are not uniform for every event. | Use one event schema from execution through stream projection. |
| EXE-GAP-003 | EXE-REQ-015, EXE-REQ-017 | runtime.ex:733-846 | Repair and tool retry use internal loops, and tool retry sleeps inside the worker. | Lower retries to scheduler-visible Flow work. |
| EXE-GAP-004 | EXE-REQ-023, EXE-REQ-024 | session/runtime.ex and react_runner.ex | Cancellation stops a Task. There is no persisted public Jido.Exec cancellation handle contract. | Define cancellation ownership and prove no late settlement. |
| EXE-GAP-005 | EXE-REQ-025, EXE-REQ-029 | request_stream.ex and session/runtime.ex | Backpressure and caller-down behavior are present in parts, but not proved as one contract. | Add slow-consumer, caller-down, and mailbox-bound tests. |
| EXE-GAP-006 | EXE-REQ-014, EXE-REQ-016, EXE-REQ-022 | current runtime options | Limits exist, but finite hard maxima and limit provenance are not uniform. | Add approved maxima and record the effective source. |

## High-Level Work Sequence

This sequence defines outcomes and gates. Detailed implementation planning comes after design approval.

1. Approve ExecutionState, stage result, event, and terminal result contracts.
2. Make all stage transitions and effective limits explicit.
3. Lower repair and tool retry to scheduler-visible Flow steps.
4. Define the Jido.Exec cancellation handle and race rules.
5. Complete backpressure, caller-down, and terminal-settlement tests.
6. Run model, tool, streaming, limit, cancellation, and lifecycle acceptance tests.

## Acceptance Matrix

| Requirement | Current evidence | Required evidence | State |
| --- | --- | --- | --- |
| EXE-REQ-001 | shared Flow exists | Passing canonical Flow tests | Proven |
| EXE-REQ-002 | authoring uses Flow.Builder | Passing authoring lowering tests | Proven |
| EXE-REQ-003 | model Action uses Jido.Exec | Passing execution ownership tests | Proven |
| EXE-REQ-004 | tool Actions use Jido.Exec | Passing execution ownership tests | Proven |
| EXE-REQ-005 | runtime state maps exist | Approved portable ExecutionState | Partial |
| EXE-REQ-006 | stages return tagged forms | Full transition validation tests | Partial |
| EXE-REQ-007 | model stage has stable call ID | Passing call correlation tests | Proven |
| EXE-REQ-008 | decision stage classifies response | Passing decision-form tests | Proven |
| EXE-REQ-009 | tool IDs and order exist | Full event correlation proof | Partial |
| EXE-REQ-010 | final stage normalizes output | Passing terminal output tests | Proven |
| EXE-REQ-011 | sequence numbers are monotonic | Passing ordered stream tests | Proven |
| EXE-REQ-012 | event metadata exists | One complete approved schema | Partial |
| EXE-REQ-013 | attempts exist in parts | Attempt metadata on every retry event | Partial |
| EXE-REQ-014 | model and tool limits exist | Approved hard maxima and provenance | Partial |
| EXE-REQ-015 | repair and retry use loops | Flow-visible retry transitions | Conflict |
| EXE-REQ-016 | timeout values exist | Uniform finite timeout policy | Partial |
| EXE-REQ-017 | tool retry uses Process.sleep | No worker sleep or hidden scheduling | Conflict |
| EXE-REQ-018 | terminal settlement is guarded | Passing one-terminal-event tests | Proven |
| EXE-REQ-019 | partial usage is retained | Passing failure usage tests | Proven |
| EXE-REQ-020 | incomplete response support exists | Passing incomplete-response tests | Proven |
| EXE-REQ-021 | call counters exist | Passing limit and count tests | Proven |
| EXE-REQ-022 | several limits are enforced | All approved limits and reasons | Partial |
| EXE-REQ-023 | Task cancellation is used | Jido.Exec cancellation handle contract | Conflict |
| EXE-REQ-024 | settlement guards exist | Full cancellation race proof | Partial |
| EXE-REQ-025 | stream buffering exists | Slow-consumer and mailbox-bound proof | Partial |
| EXE-REQ-026 | stream events have sequence IDs | Passing ordering and correlation tests | Proven |
| EXE-REQ-027 | one terminal event is produced | Passing success and failure tests | Proven |
| EXE-REQ-028 | stream usage is aggregated | Passing stream usage tests | Proven |
| EXE-REQ-029 | caller lifecycle handling exists | Full caller-down contract tests | Partial |
| EXE-REQ-030 | worker lifecycle tests exist | Passing no-leak lifecycle tests | Proven |

## Migration And Compatibility

- Keep current request and result APIs while they delegate to the approved Flow.
- Keep existing event names through a projection adapter.
- Treat react_runner.ex as compatibility code and do not add new process ownership to it.
- Resume only from portable execution inputs, not a live Task or Jido.Exec state.

## Assumptions And Blockers

- Jido Flow supports the required retry and cancellation lowering.
- Session remains the durable request owner.
- Package compile failure blocks complete execution verification.

## Completion Criteria

- One Flow defines all execution stages and retries.
- Jido.Exec owns every model and tool Action execution and exposes an approved cancellation path.
- Events have stable IDs, sequence, attempt data, and exactly one terminal result.
- All finite limits, timeouts, backpressure rules, and race cases pass tests.
