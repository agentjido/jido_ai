# ReAct Quality Execution Checklist

## Phase 0
- [x] Create `todo/` folder
- [x] Add `REACT_QUALITY_PLAN.md`
- [x] Add execution checklist
- [x] Add observability event spec

## Phase 1
- [x] Route `react.request.error` in ReAct strategy
- [x] Correlate start with `request_id`
- [x] Track active request in machine state
- [x] Fail rejected requests immediately in `ReActAgent`
- [x] Harden `Request.await` normalization

## Phase 2
- [x] Extend `Directive.ToolExec` schema with timeout/retry/request fields
- [x] Add bounded retry loop with fixed backoff
- [x] Add per-attempt timeout with supervised task shutdown
- [x] Normalize tool errors to production envelope
- [x] Guarantee single terminal tool result emission

## Phase 3
- [x] Add `react.cancel` signal/action path
- [x] Mark cancellation as request failure
- [x] Set machine termination reason to `:cancelled`
- [x] Ensure late callbacks do not alter terminal state

## Phase 4
- [x] Add ReAct request/llm/tool telemetry events
- [x] Add shared observability helper module
- [x] Add optional OpenTelemetry bridge
- [x] Expand CLI trace handlers for ReAct observability events

## Phase 5
- [x] Upgrade weather example as production canonical sample
- [x] Add user observability walkthrough guide
- [x] Add README production defaults section

## Phase 6
- [x] Fix docs extras/package file list for release
- [x] Resolve non-Hex dependency release strategy
- [x] Align README and usage docs with implemented APIs

## Validation
- [x] `mix test`
- [x] `mix quality`
- [x] `mix docs`
- [x] `mix hex.build`
