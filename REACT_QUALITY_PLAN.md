# ReAct 5/5 Production Quality Plan

## Summary
This plan upgrades ReAct to a production-grade, decision-complete lifecycle with strong correctness guarantees, explicit failure semantics, and first-class observability (Telemetry + OpenTelemetry), while preserving backward compatibility and resolving release blockers needed to confidently showcase and publish the package.

## Deliverables
1. Create `/Users/mhostetler/Source/Jido/jido_ai/REACT_QUALITY_PLAN.md` with this plan and acceptance criteria.
2. Create `/Users/mhostetler/Source/Jido/jido_ai/todo/` for implementation tracking.
3. Add `/Users/mhostetler/Source/Jido/jido_ai/todo/react_quality_execution_checklist.md`.
4. Add `/Users/mhostetler/Source/Jido/jido_ai/todo/react_observability_event_spec.md`.
5. Ship code, tests, docs, and release hardening updates in this plan.

## Scope
1. In scope: ReAct lifecycle correctness, tool lifecycle hardening, observability framework, canonical ReAct example hardening, release blockers required for production showcase.
2. Out of scope: broad parity refactors for all non-ReAct strategies in this same pass.

## Public API and Interface Changes
1. `Jido.AI.ReActAgent` options (additive):
   - `request_policy: :reject`
   - `tool_timeout_ms: 15_000`
   - `tool_max_retries: 1`
   - `tool_retry_backoff_ms: 200`
   - `observability: %{emit_telemetry?: true, emit_lifecycle_signals?: true, redact_tool_args?: true, emit_llm_deltas?: true}`
2. `Jido.AI.Directive.ToolExec` fields (additive):
   - `timeout_ms`, `max_retries`, `retry_backoff_ms`, `request_id`, `iteration`
3. `Jido.AI.Signal` additions:
   - `RequestStarted` (`react.request.started`)
   - `RequestCompleted` (`react.request.completed`)
   - `RequestFailed` (`react.request.failed`)
4. `Jido.AI.Request` await normalization hardening for deterministic error returns.
5. New observability helper modules:
   - `lib/jido_ai/observability.ex`
   - `lib/jido_ai/observability/otel.ex`

## Phased Implementation
### Phase 0: Tracking and Plan Artifacts
- Create `todo/` and plan/checklist/spec files.

### Phase 1: Correlation and Request Lifecycle Closure
- Use `request_id` as lifecycle root.
- Route and handle `react.request.error` deterministically.
- Ensure rejected requests cannot remain pending indefinitely.
- Harden `Request.await/2` normalization for failed and cancellation shapes.

### Phase 2: Full Production Tool Lifecycle
- Pass tool execution policy from strategy into `Directive.ToolExec`.
- Add bounded retry + fixed backoff + per-attempt timeout.
- Emit one terminal `react.tool.result` per tool call.
- Standardize tool error envelope:
  `%{type, message, retryable?, details}`.

### Phase 3: Cancellation and Late-Result Safety
- Add `react.cancel` action/signal path.
- Mark request as failed with `{:cancelled, reason}`.
- Set machine `termination_reason: :cancelled`.
- Ignore late callbacks after terminal state via status + correlation gating.

### Phase 4: Observability (Telemetry First, OTel Bridge)
- Add standardized ReAct request/llm/tool telemetry events.
- Provide stable metadata/measurement schemas.
- Add optional OTel bridge with safe no-op behavior when unavailable.
- Improve CLI `--trace` output with request/tool/llm details.

### Phase 5: Canonical ReAct Example Upgrade
- Promote weather agent example to production defaults + lifecycle notes.
- Add user guide walkthrough.
- Link production defaults from README.

### Phase 6: Release Hardening for Production Showcase
- Fix `mix docs` extras and package files list.
- Resolve non-Hex dependency strategy for `jido_browser`.
- Align README and usage docs with actual public APIs.

## Test Plan
### Unit
1. Busy rejection maps to request ID and fails immediately.
2. `await/2` handles all failed payload shapes deterministically.
3. Tool timeout emits timeout-classified terminal result.
4. Tool retry respects retry/backoff policy.
5. Cancellation marks request as failed and prevents overwrite.
6. Late callbacks are ignored after terminal state.

### Integration
1. Multi-tool ReAct happy path.
2. Timeout + retry + success path.
3. Unknown tool graceful failure path.
4. Concurrent busy rejection path.
5. Cancellation during `awaiting_llm`.
6. Cancellation during `awaiting_tool`.
7. Observability event sequence correctness.
8. OTel bridge span/event shape checks (when available).

### Regression
1. Existing ReAct tests keep passing.
2. CLI adapter result/usage behavior stays stable.
3. No orphaned tool/LLM tasks after completion/failure.
4. Request map eviction behavior remains intact.

## 5/5 Acceptance Criteria
1. No silent drops in request lifecycle.
2. No tool deadlocks under unknown tool, crash, timeout, or signal failure.
3. Deterministic sync behavior for success/failure/rejection/cancellation/timeout.
4. Full request/llm/tool telemetry with stable schemas.
5. Optional OTel integration remains safe and coherent.
6. Canonical weather ReAct example demonstrates production defaults.
7. `mix test`, `mix quality`, `mix docs`, and `mix hex.build` pass.

## Assumptions and Defaults
1. Backward compatibility is required; all API changes are additive.
2. Request concurrency policy remains single-flight reject-by-default in this pass.
3. Observability is telemetry-first with optional OTel bridge.
