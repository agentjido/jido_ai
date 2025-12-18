# ReqLLM Integration Testing Plan

**Date Created:** November 20, 2025
**Branch:** feature/cot
**Status:** Planning Complete - Ready for Implementation

---

## Overview

This plan ensures thorough testing of the ReqLLM library integration across all runners and the model system. The codebase has migrated from a bridge layer to direct ReqLLM integration, requiring comprehensive test coverage.

---

## Phase 1: Core ReqLLM Integration Tests

### 1.1 ChatCompletion Action Tests
**File:** `test/jido_ai/actions/req_llm/chat_completion_test.exs`

- Test `ReqLLM.generate_text()` integration with various providers
- Test streaming via `ReqLLM.stream_text()`
- Test tool calling functionality
- Test parameter passing (temperature, max_tokens, top_p, etc.)
- Test error handling and retries
- Test timeout behavior
- Mock ReqLLM calls using Mimic

### 1.2 ToolResponse Action Tests
**File:** `test/jido_ai/actions/req_llm/tool_response_test.exs`

- Test tool result aggregation
- Test multi-tool coordination
- Test error propagation from tool execution

---

## Phase 2: Model System Tests

### 2.1 Model.from/1 Conversion Tests
**File:** `test/jido_ai/model_from_test.exs` (update existing)

- Test conversion from `Jido.AI.Model` → `ReqLLM.Model`
- Test conversion from `{provider, opts}` tuples
- Test conversion from string specs (`"provider:model"`)
- Test pass-through of existing `ReqLLM.Model`
- Test error handling for invalid inputs
- Verify all fields are correctly mapped

### 2.2 Model Registry Tests
**File:** `test/jido_ai/model/registry_test.exs`

- Test `list_models/1` returns `ReqLLM.Model` structs
- Test provider filtering
- Test capability filtering
- Test caching behavior (disabled in test mode)
- Test fallback to legacy providers
- Test concurrent fetching with `batch_fetch/1`

### 2.3 Provider Adapter Tests
**File:** `test/jido_ai/providers/*_test.exs`

- Test each provider returns `ReqLLM.Model` structs
- Test model discovery functions
- Test provider-specific configurations

---

## Phase 3: Runner Integration Tests

### 3.1 Chain of Thought Runner
**File:** `test/jido_ai/runner/chain_of_thought_reqllm_test.exs`

- Test CoT generation with `ReqLLM.Model`
- Test zero-shot, few-shot, structured modes
- Test reasoning prompt generation
- Test outcome validation
- Test self-correction flows
- Test all three modes with mocked ReqLLM responses

### 3.2 ReAct Runner
**File:** `test/jido_ai/runner/react_reqllm_test.exs`

- Test thought-action-observation loop with ReqLLM
- Test action selector parsing
- Test observation processing
- Test tool registry integration
- Test iteration limits

### 3.3 Tree of Thoughts Runner
**File:** `test/jido_ai/runner/tree_of_thoughts_reqllm_test.exs`

- Test thought generation with `ReqLLM.Model`
- Test thought evaluation scoring
- Test tree exploration strategies (sampling, proposal, adaptive)
- Test beam width adaptation
- Test parallel branch evaluation

### 3.4 Self-Consistency Runner
**File:** `test/jido_ai/runner/self_consistency_reqllm_test.exs`

- Test diverse path generation with ReqLLM
- Test answer extraction
- Test voting mechanism
- Test path quality analysis
- Test consensus building

### 3.5 Program of Thought Runner
**File:** `test/jido_ai/runner/program_of_thought_reqllm_test.exs`

- Test problem classification with ReqLLM
- Test program generation
- Test program execution
- Test result integration

### 3.6 GEPA Runner
**File:** `test/jido_ai/runner/gepa_reqllm_test.exs`

- Test evaluation with `ReqLLM.Model`
- Test LLM-guided mutations
- Test reflection generation
- Test fitness scoring via LLM
- Use existing `gepa_test_helper.ex` patterns

---

## Phase 4: Authentication & Configuration Tests

### 4.1 Keyring Integration Tests
**File:** `test/jido_ai/keyring/reqllm_integration_test.exs`

- Test `get_with_reqllm/4` key resolution
- Test per-request API key overrides
- Test provider-specific authentication
- Test JidoKeys/ReqLLM integration
- Test fallback behavior when keys missing

### 4.2 Configuration Flow Tests
**File:** `test/jido_ai/config_flow_test.exs`

- Test configuration propagation to ReqLLM calls
- Test environment variable handling
- Test runtime configuration updates

---

## Phase 5: Integration Tests

### 5.1 End-to-End Model Flow
**File:** `test/jido_ai/integration/model_flow_test.exs`

- Test complete flow: Model creation → Registry lookup → ReqLLM call
- Test multi-provider scenarios
- Test model switching mid-conversation

### 5.2 Runner + Model Integration
**File:** `test/jido_ai/integration/runner_model_test.exs`

- Test each runner with real `ReqLLM.Model` structs
- Test runner fallback behaviors
- Test runner configuration with model options

### 5.3 Streaming Integration
**File:** `test/jido_ai/integration/streaming_test.exs`

- Test streaming responses through runners
- Test chunk aggregation
- Test stream cancellation

---

## Phase 6: Backward Compatibility Tests

### 6.1 Legacy Format Support
**File:** `test/jido_ai/backward_compatibility_test.exs`

- Test old `Jido.AI.Model` format still works
- Test deprecation warnings are emitted
- Test legacy provider adapters
- Test gradual migration path

---

## Test Infrastructure

### Test Helpers to Create
**File:** `test/support/reqllm_test_helper.ex`

```elixir
defmodule JidoTest.ReqLLMTestHelper do
  @moduledoc """
  Helper functions for ReqLLM integration tests.

  Provides setup, mocking, and assertions for testing ReqLLM
  integration with mocked responses.
  """

  import Mimic
  import ExUnit.Assertions

  @doc """
  Sets up mocked ReqLLM.generate_text responses.
  """
  def mock_generate_text(response) do
    stub(ReqLLM, :generate_text, fn _model, _messages, _opts ->
      {:ok, response}
    end)
  end

  @doc """
  Sets up mocked ReqLLM.stream_text responses.
  """
  def mock_stream_text(chunks) do
    stub(ReqLLM, :stream_text, fn _model, _messages, _opts ->
      {:ok, Stream.map(chunks, & &1)}
    end)
  end

  @doc """
  Creates a test ReqLLM.Model for testing.
  """
  def create_test_model(provider, opts \\ []) do
    model_name = Keyword.get(opts, :model, "test-model")

    %ReqLLM.Model{
      provider: provider,
      model: model_name,
      max_tokens: Keyword.get(opts, :max_tokens, 1024),
      capabilities: Keyword.get(opts, :capabilities, %{tool_call: true}),
      modalities: Keyword.get(opts, :modalities, %{input: [:text], output: [:text]}),
      cost: Keyword.get(opts, :cost, %{input: 1.0, output: 2.0})
    }
  end

  @doc """
  Asserts that a value is a valid ReqLLM.Model struct.
  """
  def assert_reqllm_model(model) do
    assert is_struct(model, ReqLLM.Model), "Expected ReqLLM.Model, got: #{inspect(model)}"
    assert model.provider != nil, "Model provider is nil"
    assert model.model != nil, "Model name is nil"
    model
  end

  @doc """
  Creates a mock chat response.
  """
  def mock_chat_response(content, opts \\ []) do
    %{
      content: content,
      role: :assistant,
      finish_reason: Keyword.get(opts, :finish_reason, "stop"),
      usage: %{
        prompt_tokens: Keyword.get(opts, :prompt_tokens, 10),
        completion_tokens: Keyword.get(opts, :completion_tokens, 20),
        total_tokens: Keyword.get(opts, :total_tokens, 30)
      },
      tool_calls: Keyword.get(opts, :tool_calls, [])
    }
  end

  @doc """
  Creates mock streaming chunks.
  """
  def mock_stream_chunks(content_parts) do
    content_parts
    |> Enum.with_index()
    |> Enum.map(fn {content, index} ->
      %{
        content: content,
        finish_reason: if(index == length(content_parts) - 1, do: "stop", else: nil),
        index: index
      }
    end)
  end

  @doc """
  Asserts that a response has expected structure.
  """
  def assert_chat_response(response, expectations \\ %{}) do
    assert is_map(response), "Response must be a map"

    if content = expectations[:content] do
      assert response.content == content
    end

    if role = expectations[:role] do
      assert response.role == role
    end

    response
  end
end
```

### Test Tags
- `:reqllm_integration` - Tests that verify ReqLLM integration
- `:runner_integration` - Runner-specific integration tests
- `:requires_api_key` - Tests requiring real API keys
- `:mock_reqllm` - Tests using mocked ReqLLM

### Mix Aliases to Add
```elixir
"test.reqllm": "test --only reqllm_integration"
"test.runners": "test --only runner_integration"
```

---

## Test Count Estimates

| Phase | Test Files | Est. Tests |
|-------|------------|------------|
| Phase 1: Core ReqLLM | 2 | 25-30 |
| Phase 2: Model System | 4 | 35-40 |
| Phase 3: Runners | 6 | 60-80 |
| Phase 4: Auth/Config | 2 | 15-20 |
| Phase 5: Integration | 3 | 20-25 |
| Phase 6: Backward Compat | 1 | 10-15 |
| **Total** | **18** | **165-210** |

---

## Implementation Order

1. **Start with Phase 2.1** - Model.from tests (foundational)
2. **Then Phase 1** - Core ReqLLM action tests
3. **Then Phase 4** - Authentication (needed by runners)
4. **Then Phase 3** - Runner tests (largest phase)
5. **Then Phase 5** - Integration tests
6. **Finally Phase 6** - Backward compatibility

---

## Success Criteria

- All runners execute successfully with `ReqLLM.Model`
- Model conversion handles all input formats
- Authentication flows work correctly
- Streaming responses aggregate properly
- No regressions in existing functionality
- Tests run in < 3 minutes (unit), < 10 minutes (integration)
- Memory usage stays under 500MB in test mode

---

## Key Files Reference

### Core ReqLLM Integration
- `lib/jido_ai/actions/req_llm/chat_completion.ex`
- `lib/jido_ai/model.ex`
- `lib/jido_ai/model/registry.ex`
- `lib/jido_ai/keyring.ex`

### Runners
- `lib/jido_ai/runner/chain_of_thought.ex`
- `lib/jido_ai/runner/react/`
- `lib/jido_ai/runner/tree_of_thoughts/`
- `lib/jido_ai/runner/self_consistency.ex`
- `lib/jido_ai/runner/program_of_thought/`
- `lib/jido_ai/runner/gepa.ex`

### Existing Tests to Reference
- `test/jido_ai/provider/model_from_test.exs`
- `test/jido_ai/runner/chain_of_thought_integration_test.exs`
- `test/support/gepa_test_helper.ex`

---

## Notes

- The codebase has removed the old `req_llm_bridge` layer (~1,300 lines deleted)
- `Model.from/1` now returns `ReqLLM.Model` instead of `Jido.AI.Model`
- Test mode disables registry caching to prevent memory leaks
- Use Mimic for stubbing `Jido.Agent.Server.call` and ReqLLM functions
