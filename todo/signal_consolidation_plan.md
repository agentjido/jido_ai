# Signal Consolidation Plan

## Summary
- Consolidate the signal surface around the event types that are actually used in runtime paths.
- Keep current external behavior stable by preserving canonical signal names where they are routed today.
- Reduce duplication by standardizing on `*.result` for success and failure payloads, and by introducing shared schema helpers for common fields.

## Current State (Observed in Code)
- Signal modules defined in `lib/jido_ai/signals/`: 17.
- Signals actively emitted and/or routed in runtime paths:
  - `ai.llm.response`
  - `ai.llm.delta`
  - `ai.usage`
  - `ai.tool.result`
  - `ai.embed.result`
  - `ai.request.started`
  - `ai.request.completed`
  - `ai.request.failed`
  - `ai.request.error`
- Signals defined but not emitted by current runtime paths:
  - `ai.llm.request`
  - `ai.embed.request`
  - `ai.llm.cancelled`
  - `ai.tool.call`
  - `ai.llm.error`
  - `ai.embed.error`
  - `ai.tool.error`
  - `ai.react.step`

## Duplication and Drift
- Error schema duplication:
  - `LLMError`, `EmbedError`, and `ToolError` share nearly identical payload shapes.
  - `ToolError` adds only `tool_name`.
- Result-wrapper duplication:
  - `LLMResponse`, `EmbedResult`, and `ToolResult` all carry `call_id` plus a `result` tuple shape (`{:ok, ...} | {:error, ...}`), with domain-specific extras.
- Mixed failure semantics:
  - Tool/embed/llm runtime paths currently report failures through `*.result` error tuples.
  - Dedicated `*.error` signal modules exist but are not emitted in those paths.
- Lifecycle split is intentional but should be documented:
  - `ai.request.error` means early rejection.
  - `ai.request.failed` means in-flight request failed after start.

## Consolidation Goals
1. Minimize public contract surface while preserving routing compatibility.
2. Make error reporting semantics consistent across llm/tool/embed.
3. Eliminate schema duplication and reduce maintenance overhead.
4. Keep migration low risk and observable.

## Recommended Direction
1. Treat `*.result` as canonical completion signals for llm/tool/embed.
- Success and failure both flow through:
  - `ai.llm.response`
  - `ai.tool.result`
  - `ai.embed.result`

2. Keep request lifecycle quartet unchanged.
- Keep:
  - `ai.request.started`
  - `ai.request.completed`
  - `ai.request.failed`
  - `ai.request.error`
- Clarify semantics in docs (rejected vs started-and-failed).

3. Deprecate currently unused signal modules before removal.
- Candidate deprecations:
  - `LLMRequest`, `EmbedRequest`, `LLMCancelled`, `ToolCall`, `LLMError`, `EmbedError`, `ToolError`, `Step`
- Keep code compiling and behavior unchanged during deprecation window.

4. Add shared schema helpers for common fields.
- Introduce reusable schema fragments for:
  - correlation ids (`call_id`, `request_id`)
  - standard error envelope fields (`error_type`, `message`, `details`, `retry_after`)
  - result tuple wrapper patterns

## Phased Plan
1. Phase 1: Documentation and contract alignment.
- Update `guides/developer/signals_namespaces_contracts.md` with an explicit canonical list and semantics.
- Document the primary rule: llm/tool/embed errors are represented via `result` error tuples.
- Add a migration note for any downstream consumer still expecting `ai.*.error`.

2. Phase 2: Internal simplification with no external behavior change.
- Add schema helper module(s) for shared field definitions.
- Refactor signal modules to consume shared helpers while retaining existing `type` strings.
- Add tests that enforce field consistency across related signals.

3. Phase 3: Deprecation pass.
- Mark unused signal modules as deprecated in docs and moduledocs.
- Add repo checks to prevent new runtime emission paths from reintroducing deprecated signals.

4. Phase 4: Removal (next major or planned breaking release).
- Remove deprecated signal modules.
- Remove tests that only validate deprecated types.
- Keep a concise migration mapping in `README.md` and guides.

## Proposed Canonical Set After Consolidation
- Request lifecycle:
  - `ai.request.started`
  - `ai.request.completed`
  - `ai.request.failed`
  - `ai.request.error`
- LLM:
  - `ai.llm.response`
  - `ai.llm.delta`
- Tool:
  - `ai.tool.result`
- Embedding:
  - `ai.embed.result`
- Usage:
  - `ai.usage`

## Migration Mapping (If Deprecated Signals Are Removed)
- `ai.llm.error` -> `ai.llm.response` with `result: {:error, envelope}`
- `ai.tool.error` -> `ai.tool.result` with `result: {:error, envelope}`
- `ai.embed.error` -> `ai.embed.result` with `result: {:error, envelope}`
- `ai.llm.request` and `ai.embed.request` -> telemetry/observability events (not strategy routes)
- `ai.tool.call` -> internal directive/telemetry only
- `ai.react.step` -> explicit observability stream if needed, otherwise remove
- `ai.llm.cancelled` -> represent cancellation via request lifecycle and result error envelope

## Test Plan
1. Route compatibility tests.
- Ensure all strategy `signal_routes/1` still match emitted signal types.

2. Error semantics tests.
- Verify llm/tool/embed failures are always representable as `result: {:error, envelope}`.
- Verify envelope includes stable keys for classification and retryability.

3. Deprecation safety tests.
- Add tests or lint checks to ensure deprecated signal types are not emitted from directives/agents.

4. Regression suite.
- Run `mix test`.
- Run `mix q`.

## Risks and Mitigations
- Risk: Downstream consumers rely on deprecated error/request/call signals.
- Mitigation: ship migration mapping, deprecation window, and explicit release notes.

- Risk: Confusion between `ai.request.error` and `ai.request.failed`.
- Mitigation: document strict semantic boundary and enforce in tests.

- Risk: Accidental reintroduction of deprecated signals.
- Mitigation: add static checks in CI (`rg`-based guard or test assertions on emitted signal types).

## Acceptance Criteria
1. Canonical signal list is documented and consistent with runtime emitters.
2. No duplicate signal schemas remain without shared helper usage.
3. Deprecated signal modules are either removed or clearly marked with migration guidance.
4. Strategy routing and integration tests pass with no behavior regressions.
