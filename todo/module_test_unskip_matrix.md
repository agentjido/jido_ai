# Skipped Test Replacement Matrix

## Streaming
- `test/jido_ai/skills/streaming/actions/start_stream_test.exs`
  - Replace skipped runtime tests with deterministic stream-registry-backed tests.

## Planning
- `test/jido_ai/skills/planning/actions/plan_action_test.exs`
- `test/jido_ai/skills/planning/actions/decompose_action_test.exs`
- `test/jido_ai/skills/planning/actions/prioritize_action_test.exs`
  - Replace skipped runtime tests with deterministic LLM client doubles.

## Tool calling
- `test/jido_ai/skills/tool_calling/actions/call_with_tools_test.exs`
  - Replace skipped runtime tests with deterministic multi-turn LLM client stubs.

## Acceptance
- `rg -n "@tag :skip" test` returns zero.
