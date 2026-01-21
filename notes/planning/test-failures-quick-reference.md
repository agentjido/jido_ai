# Test Failures Quick Reference
**Created:** 2025-10-22
**Status:** Ready for Implementation

## TL;DR

- **52 test failures** out of 1905 tests (97.3% passing)
- **51 failures**: GEPA tests trying to make real API calls → need mocks
- **1 failure**: ProgramOfThought using undefined function → API changed
- **Estimated fix time:** 4-7 hours
- **Risk level:** Low (test-only changes)

## The Problem in One Sentence

GEPA evaluator tests are calling the real OpenAI API instead of using test mocks, causing authentication failures.

## The Fix in One Sentence

Create a ReqLLM mock module to intercept API calls in tests and return test data.

## Quick Commands

### Run failing tests
```bash
# All failures
mix test --failed

# GEPA evaluator tests
mix test test/jido/runner/gepa/evaluator_test.exs

# GEPA integration tests
mix test test/jido/runner/gepa/evaluation_system_integration_test.exs

# Program of Thought tests
mix test test/jido/runner/program_of_thought_test.exs

# Full suite
mix test
```

### Create fix branch
```bash
git checkout feature/cot
git checkout -b fix/test-failures-post-reqllm-merge
```

## Test Failure Locations

### GEPA Evaluator (9 failures)
File: `test/jido/runner/gepa/evaluator_test.exs`

- Line 286: timeout enforcement
- Line 347: concurrent execution failures
- Line 182: result structure fields
- Line 318: concurrent parallel execution
- Various configuration tests

### GEPA Integration (42 failures)
File: `test/jido/runner/gepa/evaluation_system_integration_test.exs`

- Lines 219, 250, 270: Trajectory collection
- Line 399+: Metrics aggregation
- Line 526+: Concurrent evaluation
- Line 791+: Result synchronization
- Line 871+: Complete workflow

### Program of Thought (1 failure)
File: `test/jido/runner/program_of_thought_test.exs`

- Lines 481, 500: Undefined `new!/1` function

## Error Signatures

### GEPA Authentication Error
```
[error] Chat completion failed: "Authentication failed: \"Authentication error: API key not found: OPENAI_API_KEY\""
[error] Action Jido.AI.Actions.Internal.ChatResponse failed: %{reason: "req_llm_error", ...}
** (EXIT from #PID<...>) shutdown
```

### PoT Undefined Function
```
warning: Jido.Actions.CoT.ProgramOfThought.new!/1 is undefined or private
```

## Fix Checklist

- [ ] Create `test/support/req_llm_mock.ex`
- [ ] Update GEPA evaluator test setup
- [ ] Update GEPA integration test setup
- [ ] Fix ProgramOfThought API usage
- [ ] Run full test suite (should be 0 failures)
- [ ] Create fix summary document
- [ ] Commit changes

## Key Files

### To Modify
- `test/jido/runner/gepa/evaluator_test.exs`
- `test/jido/runner/gepa/evaluation_system_integration_test.exs`
- `test/jido/runner/program_of_thought_test.exs`

### To Create
- `test/support/req_llm_mock.ex`

### To Reference
- `lib/jido_ai/actions/internal/chat_response.ex`
- `lib/jido/runner/gepa/evaluator.ex`
- `lib/jido/runner/program_of_thought.ex`

## Test Mock Pattern

```elixir
# test/support/req_llm_mock.ex
defmodule JidoTest.Support.ReqLlmMock do
  def mock_chat_completion(_prompt, opts \\ []) do
    {:ok, %{
      content: opts[:response] || "Test response",
      model: opts[:model] || "gpt-4",
      usage: %{
        prompt_tokens: 10,
        completion_tokens: 20,
        total_tokens: 30
      }
    }}
  end
end

# In test file
setup do
  mock_model = create_mock_model()
  {:ok, model: mock_model}
end

test "uses mock", %{model: model} do
  result = Evaluator.evaluate_prompt("test", model: model)
  assert {:ok, _} = result
end
```

## Success Criteria

**Must Have:**
- All 52 tests passing
- No new failures
- Zero failures in full suite

**Should Have:**
- Mock infrastructure documented
- Summary document created

## Timeline

1. Setup (10 min)
2. Create mock infrastructure (1 hour)
3. Fix GEPA tests (2-3 hours)
4. Fix PoT tests (30-60 min)
5. Verify & document (1 hour)

**Total: 4-7 hours**

## Documentation

### Planning Document
`/home/ducky/code/agentjido/cot/notes/features/fix-all-test-failures.md`

Comprehensive planning with detailed analysis, strategy, and implementation steps.

### Analysis Summary
`/home/ducky/code/agentjido/cot/notes/summaries/test-failure-analysis-2025-10-22.md`

Executive summary with key findings and recommendations.

### This Document
`/home/ducky/code/agentjido/cot/notes/planning/test-failures-quick-reference.md`

Quick reference for implementation.

## What's Working

- TrajectoryAnalyzer: 40/40 tests passing
- Chain of Thought: All variants passing
- ReqLLM Bridge: All tests passing
- Jido.AI Prompt/Provider: All tests passing
- Integration tests: Stage 1 and CoT patterns passing
- **97.3% of all tests passing**

## Common Questions

**Q: Why are these tests failing now?**
A: After migrating to ReqLLM, tests that create real agent instances are now trying to make actual API calls instead of using mocks.

**Q: Is this a critical issue?**
A: No. The code is sound (97.3% tests passing). This is test infrastructure cleanup after migration.

**Q: Can we just add API keys?**
A: Not recommended. Tests should be fast, deterministic, and not depend on external services.

**Q: How long will this take?**
A: 4-7 hours for a complete fix with documentation.

**Q: What's the risk?**
A: Low. All changes are in test code, not production code.

---

**Ready to start implementation when approved**
