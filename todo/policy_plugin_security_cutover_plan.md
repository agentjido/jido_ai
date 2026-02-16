# Policy-Plugin Refactor With Security Hard Cutover

## Summary
- Move AI policy enforcement to a default-on `Jido.Plugin` middleware layer that filters and rewrites AI signals before routing.
- Split non-signal validation concerns out of `Jido.AI.Security` into focused modules, then remove `Jido.AI.Security` entirely.
- Keep request lifecycle safety by rewriting blocked start signals to `ai.request.error` (not plugin `{:error, ...}`), so `await/2` never hangs.

## Feasibility Findings (Validated Against Latest Jido Main)
- `handle_signal/2` can rewrite or override signals on both `call` and `cast` paths, and supports signal pattern filtering; this is enough for inbound and internal AI signal policy.
- `transform_result/3` is call-path-only and cannot enforce async/runtime policy.
- Outbound `%Directive.Emit{}` dispatch is not directly hookable by plugin middleware in current Jido runtime, so policy scope should be inbound/internal only for this phase.

## Public API / Interface Changes
- New default plugin: `Jido.AI.Plugins.Policy` (enabled by default in AI agent macros).
- New macro option on AI agent macros: `:policy`.
- `Jido.AI.Security` removed (hard cutover, breaking change).
- New replacement modules:
  - `Jido.AI.Validation`
  - `Jido.AI.Error.Sanitize`
  - `Jido.AI.Streaming.ID`
- Migration mapping:
  - `Jido.AI.Security.validate_string/2` -> `Jido.AI.Validation.validate_string/2`
  - `Jido.AI.Security.validate_custom_prompt/2` -> `Jido.AI.Validation.validate_custom_prompt/2`
  - `Jido.AI.Security.validate_max_turns/1` -> `Jido.AI.Validation.validate_max_turns/1`
  - `Jido.AI.Security.max_prompt_length/0` -> `Jido.AI.Validation.max_prompt_length/0`
  - `Jido.AI.Security.max_input_length/0` -> `Jido.AI.Validation.max_input_length/0`
  - `Jido.AI.Security.sanitize_error_message/2` -> `Jido.AI.Error.Sanitize.message/2`
  - `Jido.AI.Security.sanitize_error_for_display/1` -> `Jido.AI.Error.Sanitize.for_display/1`
  - `Jido.AI.Security.generate_stream_id/0` -> `Jido.AI.Streaming.ID.generate/0`
  - `Jido.AI.Security.validate_stream_id/1` -> `Jido.AI.Streaming.ID.validate/1`

## Implementation Plan
1. Baseline on latest Jido runtime.
- Update `/Users/mhostetler/Source/Jido/jido_ai/mix.exs` to use `jido` from `main` branch and refresh `/Users/mhostetler/Source/Jido/jido_ai/mix.lock`.
- Confirm plugin middleware semantics in this repo with focused tests before refactor.

2. Implement policy middleware stack.
- Add `/Users/mhostetler/Source/Jido/jido_ai/lib/jido_ai/plugins/policy.ex`.
- Add `/Users/mhostetler/Source/Jido/jido_ai/lib/jido_ai/policy/engine.ex`.
- Add `/Users/mhostetler/Source/Jido/jido_ai/lib/jido_ai/policy/rules/input_signal.ex`.
- Add `/Users/mhostetler/Source/Jido/jido_ai/lib/jido_ai/policy/rules/llm_signal.ex`.
- Add `/Users/mhostetler/Source/Jido/jido_ai/lib/jido_ai/policy/rules/tool_signal.ex`.
- Policy config defaults (decision-locked):
  - `mode: :enforce`
  - `query_max_length: 100_000`
  - `delta_max_length: 4_096`
  - `result_max_length: 50_000`
  - `block_injection_patterns: true`
  - `strip_control_chars: true`
  - `redact_violation_details: true`
- Signal handling rules (decision-locked):
  - Strategy start signals (`ai.*.query`): validate `query || prompt`; on violation rewrite to `ai.request.error` with `reason: :policy_violation`.
  - `ai.llm.delta`: sanitize/truncate `delta`; if empty after sanitization, override to `Jido.Actions.Control.Noop`.
  - `ai.llm.response`: on invalid payload, rewrite `result` to `{:error, %{type: :policy_violation, message: "...", details: ...}}`.
  - `ai.tool.result`: on invalid payload, rewrite `result` to same policy error envelope.
  - Never rewrite `ai.request.error` again (loop guard).

3. Wire default-on policy plugin in all AI macros.
- Add shared plugin-stack helper `/Users/mhostetler/Source/Jido/jido_ai/lib/jido_ai/plugin_stack.ex` to merge defaults and user plugins without duplicate modules.
- Update `/Users/mhostetler/Source/Jido/jido_ai/lib/jido_ai/agent.ex`.
- Update `/Users/mhostetler/Source/Jido/jido_ai/lib/jido_ai/agents/strategies/cot_agent.ex`.
- Update `/Users/mhostetler/Source/Jido/jido_ai/lib/jido_ai/agents/strategies/tot_agent.ex`.
- Update `/Users/mhostetler/Source/Jido/jido_ai/lib/jido_ai/agents/strategies/got_agent.ex`.
- Update `/Users/mhostetler/Source/Jido/jido_ai/lib/jido_ai/agents/strategies/trm_agent.ex`.
- Update `/Users/mhostetler/Source/Jido/jido_ai/lib/jido_ai/agents/strategies/adaptive_agent.ex`.
- Add macro option behavior (decision-locked):
  - `policy: false` disables default policy plugin.
  - `policy: [..config..]` overrides policy plugin config.
  - User-supplied explicit policy plugin config wins over defaults.

4. Hard-cut `security.ex` into scoped modules and migrate all call sites.
- Add `/Users/mhostetler/Source/Jido/jido_ai/lib/jido_ai/validation.ex`.
- Add `/Users/mhostetler/Source/Jido/jido_ai/lib/jido_ai/error/sanitize.ex`.
- Add `/Users/mhostetler/Source/Jido/jido_ai/lib/jido_ai/streaming/id.ex`.
- Migrate security aliases/usages in:
  - `/Users/mhostetler/Source/Jido/jido_ai/lib/jido_ai/actions/helpers.ex`
  - `/Users/mhostetler/Source/Jido/jido_ai/lib/jido_ai/actions/llm/chat.ex`
  - `/Users/mhostetler/Source/Jido/jido_ai/lib/jido_ai/actions/llm/complete.ex`
  - `/Users/mhostetler/Source/Jido/jido_ai/lib/jido_ai/actions/llm/embed.ex`
  - `/Users/mhostetler/Source/Jido/jido_ai/lib/jido_ai/actions/llm/generate_object.ex`
  - `/Users/mhostetler/Source/Jido/jido_ai/lib/jido_ai/actions/reasoning/analyze.ex`
  - `/Users/mhostetler/Source/Jido/jido_ai/lib/jido_ai/actions/reasoning/explain.ex`
  - `/Users/mhostetler/Source/Jido/jido_ai/lib/jido_ai/actions/reasoning/infer.ex`
  - `/Users/mhostetler/Source/Jido/jido_ai/lib/jido_ai/actions/streaming/start_stream.ex`
  - `/Users/mhostetler/Source/Jido/jido_ai/lib/jido_ai/actions/tool_calling/call_with_tools.ex`
  - `/Users/mhostetler/Source/Jido/jido_ai/lib/jido_ai/actions/tool_calling/list_tools.ex`
- Remove `/Users/mhostetler/Source/Jido/jido_ai/lib/jido_ai/security.ex`.
- Delete or replace `/Users/mhostetler/Source/Jido/jido_ai/test/jido_ai/security_test.exs` with targeted tests for new modules.
- Enforce repo-wide no-reference check: `rg "Jido\\.AI\\.Security"` must return zero hits.

5. Update docs and migration notes for the new boundary.
- Update `/Users/mhostetler/Source/Jido/jido_ai/guides/developer/security_and_validation.md`.
- Update `/Users/mhostetler/Source/Jido/jido_ai/guides/developer/plugins_and_actions_composition.md`.
- Update `/Users/mhostetler/Source/Jido/jido_ai/guides/developer/error_model_and_recovery.md`.
- Update `/Users/mhostetler/Source/Jido/jido_ai/README.md`.
- Add explicit breaking-change migration section for `Jido.AI.Security` removal.

## Test Cases and Scenarios
1. Policy plugin unit tests.
- Start signal with injection pattern rewrites to `ai.request.error` and preserves correlation id.
- Start signal with valid prompt passes unchanged.
- `ai.llm.delta` oversized payload is truncated; empty post-sanitize becomes no-op override.
- `ai.llm.response` malformed payload rewrites to policy error envelope.
- `ai.tool.result` malformed payload rewrites to policy error envelope.
- `mode: :report_only` emits telemetry but does not rewrite.

2. Request lifecycle integration tests.
- Blocked request never causes `Request.await/2` timeout; returns rejected error promptly.
- Concurrent request behavior (`busy` path) remains unchanged.
- Request tracking fields remain consistent for both rewritten and normal flows.

3. Macro/plugin stack tests.
- Every AI macro includes policy plugin by default.
- `policy: false` removes policy plugin.
- User-provided policy plugin config overrides defaults and does not duplicate plugin module entries.

4. Validation module parity tests.
- `Jido.AI.Validation` reproduces accepted/rejected behavior for existing action inputs.
- `Jido.AI.Error.Sanitize` parity for known errors and generic fallbacks.
- `Jido.AI.Streaming.ID` UUID generation/validation parity.

5. Full regression suite and smoke.
- Run `mix test`.
- Run `mix q` (or at least compile + credo + dialyzer path used in CI).
- Run weather example smoke via CLI task using `/Users/mhostetler/Source/Jido/jido_ai/lib/jido_ai/agents/examples/weather_agent.ex` to confirm end-to-end behavior.

## Assumptions and Defaults
- Default behavior is enforcement, not observe-only.
- Policy plugin is default-on across all AI agent macros.
- `Jido.AI.Security` is removed in one release (no compatibility shim).
- Policy scope is inbound/internal AI signals only; outbound `%Directive.Emit{}` interception is deferred until Jido exposes a hook.
- Direct `Jido.Exec.run/3` action calls still require action-level validation; plugin middleware only governs AgentServer signal flows.
