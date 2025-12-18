# LangChain to ReqLLM Migration Plan

## Document Metadata

- **Feature**: Replace LangChain with ReqLLM-based actions
- **Status**: ✅ **COMPLETE** - All tests passing (567 tests, 0 failures)
- **Created**: 2025-10-21
- **Completed**: 2025-10-21
- **Last Updated**: 2025-10-21
- **Owner**: Pascal

---

## 1. Problem Statement

### Current Situation

The Jido AI Skill module (`lib/jido_ai/skill.ex`) currently defaults to LangChain-based actions for tool execution:
- Line 30: `tool_action: Jido.AI.Actions.Langchain.ToolResponse`
- Line 68: Used in mount function
- Line 103: Used in router definition

**Pain Points:**
1. **Limited Provider Support**: LangChain supports only 3-4 providers (OpenAI, Anthropic, OpenRouter, Google)
2. **Heavy Dependency**: LangChain is a comprehensive library with features we don't fully utilize
3. **Architectural Mismatch**: ReqLLM is the primary integration strategy across the codebase
4. **Provider Growth**: ReqLLM supports 57+ providers vs LangChain's 3-4
5. **Maintenance**: Two parallel systems require duplicate maintenance

### Why Replace Now?

The ReqLlmBridge infrastructure is **complete and production-ready**:
- **540+ tests passing** across 7 core modules
- Authentication system with multi-source key management
- Tool conversion and execution pipeline
- Conversation state management
- Comprehensive error handling
- Streaming support
- Response aggregation

This infrastructure is battle-tested and ready to replace LangChain.

---

## 2. Solution Overview

### High-Level Approach

Create new ReqLLM-based Actions that mirror LangChain functionality while using the proven ReqLlmBridge infrastructure:

1. **Create `Jido.AI.Actions.ReqLlm.ChatCompletion`**
   - Replaces `Jido.AI.Actions.Langchain` base action
   - Uses ReqLLM for all provider communication
   - Supports all 57+ ReqLLM providers

2. **Create `Jido.AI.Actions.ReqLlm.ToolResponse`**
   - Replaces `Jido.AI.Actions.Langchain.ToolResponse`
   - Uses ReqLlmBridge.ToolBuilder for tool conversion
   - Uses ReqLlmBridge.ToolExecutor for tool execution
   - Leverages ConversationManager for state

3. **Update `Jido.AI.Skill` Defaults**
   - Change default tool_action to ReqLlm.ToolResponse
   - Add deprecation warnings for LangChain
   - Maintain backward compatibility

### Key Design Principles

1. **Backward Compatibility**: Users can still opt into LangChain if needed
2. **Zero Breaking Changes**: Existing code continues to work
3. **Leveraging Proven Infrastructure**: Use ReqLlmBridge modules (540+ tests passing)
4. **Consistent API**: Mirror existing parameter schemas and response formats
5. **Comprehensive Testing**: Match or exceed existing test coverage

---

## 3. Technical Details

### 3.1 File Structure

**New Files to Create:**
```
lib/jido_ai/actions/req_llm/
├── chat_completion.ex      # Base chat completion action
└── tool_response.ex         # Tool/function calling action

test/jido_ai/actions/req_llm/
├── chat_completion_test.exs
└── tool_response_test.exs
```

**Files to Modify:**
```
lib/jido_ai/skill.ex         # Update default tool_action
```

**Files to Reference (NOT modify):**
```
lib/jido_ai/req_llm_bridge.ex                          # Main bridge
lib/jido_ai/req_llm_bridge/tool_builder.ex             # Tool conversion
lib/jido_ai/req_llm_bridge/tool_executor.ex            # Tool execution
lib/jido_ai/req_llm_bridge/conversation_manager.ex     # State management
lib/jido_ai/req_llm_bridge/response_aggregator.ex      # Response formatting
lib/jido_ai/req_llm_bridge/error_handler.ex            # Error handling
lib/jido_ai/req_llm_bridge/authentication.ex           # Auth
lib/jido_ai/req_llm_bridge/streaming_adapter.ex        # Streaming
```

### 3.2 Module Dependencies

**ReqLLM Action Dependencies:**
```elixir
# Existing infrastructure (tested, working)
ReqLlmBridge                    # Main bridge, format conversions
ReqLlmBridge.ToolBuilder        # Action → tool descriptor
ReqLlmBridge.ToolExecutor       # Tool execution with error handling
ReqLlmBridge.ConversationManager # ETS-based state
ReqLlmBridge.ResponseAggregator # Response formatting
ReqLlmBridge.ErrorHandler       # Error sanitization
ReqLlmBridge.Authentication     # Multi-source key resolution
ReqLlmBridge.StreamingAdapter   # Streaming support

# External
ReqLLM                          # Provider communication (57+ providers)
Jido.Action                     # Action behavior
Jido.AI.Model                   # Model validation
Jido.AI.Prompt                  # Prompt management
```

### 3.3 Parameter Schema Design

Based on existing LangChain action patterns:

**ReqLlm.ChatCompletion Schema:**
```elixir
schema: [
  model: [
    type: {:custom, Jido.AI.Model, :validate_model_opts, []},
    required: true,
    doc: "The AI model to use"
  ],
  prompt: [
    type: {:custom, Jido.AI.Prompt, :validate_prompt_opts, []},
    required: true,
    doc: "The prompt to use for the response"
  ],
  tools: [
    type: {:list, :atom},
    required: false,
    doc: "List of Jido.Action modules for function calling"
  ],
  temperature: [type: :float, default: 0.7],
  max_tokens: [type: :integer, default: 1000],
  top_p: [type: :float],
  stop: [type: {:list, :string}],
  timeout: [type: :integer, default: 60_000],
  stream: [type: :boolean, default: false],
  verbose: [type: :boolean, default: false]
]
```

**ReqLlm.ToolResponse Schema:**
```elixir
schema: [
  model: [
    type: {:custom, Jido.AI.Model, :validate_model_opts, []},
    default: {:anthropic, [model: "claude-3-5-haiku-latest"]},
    doc: "The AI model to use"
  ],
  prompt: [
    type: {:custom, Jido.AI.Prompt, :validate_prompt_opts, []},
    required: true,
    doc: "The prompt to use for the response"
  ],
  tools: [
    type: {:list, :atom},
    default: [],
    doc: "List of Jido.Action modules to use as tools"
  ],
  temperature: [type: :float, default: 0.7],
  timeout: [type: :integer, default: 30_000],
  verbose: [type: :boolean, default: false]
]
```

### 3.4 Core Implementation Flow

#### ReqLlm.ChatCompletion.run/2

```elixir
def run(params, context) do
  # 1. Extract and validate model
  with {:ok, model} <- validate_model(params.model),

       # 2. Get API key using Authentication system
       {:ok, {api_key, headers}} <-
         ReqLlmBridge.get_provider_authentication(model.provider, params),

       # 3. Convert Jido.AI.Prompt to ReqLLM format
       messages <- ReqLlmBridge.convert_messages(
         Jido.AI.Prompt.render(params.prompt)
       ),

       # 4. Build ReqLLM options
       req_options <- ReqLlmBridge.build_req_llm_options(params),

       # 5. Convert tools if provided
       {:ok, tools} <- convert_tools_if_present(params.tools),

       # 6. Make ReqLLM request
       {:ok, response} <- call_reqllm(
         model.provider,
         messages,
         Map.merge(req_options, %{tools: tools})
       ),

       # 7. Convert response to Jido AI format
       result <- ReqLlmBridge.convert_response(response) do

    {:ok, result}
  else
    {:error, reason} -> ReqLlmBridge.map_error(reason)
  end
end
```

#### ReqLlm.ToolResponse.run/2

```elixir
def run(params, context) do
  # 1. Prepare parameters
  model = params[:model] || default_model()
  prompt = params[:prompt]
  tools = params[:tools] || []

  # 2. Create conversation for tool state management
  {:ok, conv_id} <- ConversationManager.create_conversation()

  # 3. Convert tools using ToolBuilder
  {:ok, tool_descriptors} <-
    ReqLlmBridge.convert_tools(tools)

  # 4. Store tools in conversation
  :ok = ConversationManager.set_tools(conv_id, tool_descriptors)

  # 5. Add initial message to conversation
  :ok = ConversationManager.add_message(
    conv_id,
    convert_prompt_to_message(prompt)
  )

  # 6. Execute chat completion with tools
  completion_params = %{
    model: model,
    prompt: prompt,
    tools: tools,
    temperature: params[:temperature] || 0.7,
    verbose: params[:verbose] || false
  }

  case ReqLlm.ChatCompletion.run(completion_params, context) do
    {:ok, %{content: content, tool_calls: tool_calls}} ->
      # 7. Execute any tool calls using ToolExecutor
      tool_results = execute_tool_calls(tool_calls, tools, context)

      # 8. Add results to conversation
      :ok = ConversationManager.add_tool_results(conv_id, tool_results)

      # 9. Aggregate final response
      {:ok, final_response} =
        ResponseAggregator.aggregate_response(
          content,
          tool_results,
          ConversationManager.get_messages(conv_id)
        )

      {:ok, %{
        result: final_response.content,
        tool_results: final_response.tool_results
      }}

    {:error, reason} ->
      ErrorHandler.format_error(reason)
  end
end
```

### 3.5 Error Handling Strategy

Leverage existing ErrorHandler module:
- All errors go through `ErrorHandler.format_error/1`
- Consistent error structure across all ReqLLM actions
- Sanitized error messages (no sensitive data leakage)
- Error categorization: validation, authentication, execution, timeout, etc.

### 3.6 Backward Compatibility Plan

**Allow Users to Opt Into LangChain:**
```elixir
# Users can still use LangChain if they want
use Jido.Skill,
  ai: [
    model: model,
    tool_action: Jido.AI.Actions.Langchain.ToolResponse  # Explicit override
  ]
```

**Add Deprecation Warning:**
```elixir
# In Jido.AI.Skill.mount/2
def mount(agent, opts) do
  tool_action = Keyword.get(opts, :tool_action, Jido.AI.Actions.ReqLlm.ToolResponse)

  # Warn if using LangChain
  if tool_action == Jido.AI.Actions.Langchain.ToolResponse do
    Logger.warning("""
    LangChain actions are deprecated and will be removed in v0.6.0.
    Please migrate to Jido.AI.Actions.ReqLlm.ToolResponse for:
    - Support for 57+ providers (vs 3-4 with LangChain)
    - Better error handling
    - Lighter dependencies

    To migrate, update your Skill configuration:
      tool_action: Jido.AI.Actions.ReqLlm.ToolResponse

    Or remove the tool_action option to use the new default.
    """)
  end

  # Continue with normal mounting...
end
```

---

## 4. Success Criteria

### Must Have

- [ ] `Jido.AI.Actions.ReqLlm.ChatCompletion` implemented with full schema
- [ ] `Jido.AI.Actions.ReqLlm.ToolResponse` implemented with full schema
- [ ] All existing tests continue to pass (no regressions)
- [ ] New actions have comprehensive test coverage (match LangChain test patterns)
- [ ] `Jido.AI.Skill` defaults updated to use ReqLLM actions
- [ ] Deprecation warnings added for LangChain usage
- [ ] Backward compatibility maintained (users can still opt into LangChain)

### Should Have

- [ ] Performance benchmarks showing ReqLLM actions perform comparably to LangChain
- [ ] Documentation updated (guides, examples, migration notes)
- [ ] Integration tests with multiple providers (OpenAI, Anthropic, etc.)

### Nice to Have

- [ ] Migration guide with code examples
- [ ] Performance optimizations based on benchmarks
- [ ] Additional provider-specific features exposed through ReqLLM

---

## 5. Implementation Plan

### Phase 1: Create ReqLlm.ChatCompletion Action

**Files:**
- `lib/jido_ai/actions/req_llm/chat_completion.ex`
- `test/jido_ai/actions/req_llm/chat_completion_test.exs`

**Tasks:**
1. Create module structure with Jido.Action behavior
2. Define schema (mirror LangChain schema)
3. Implement `on_before_validate_params/1` for model/prompt validation
4. Implement `run/2` using ReqLlmBridge infrastructure:
   - Model validation
   - Authentication via `ReqLlmBridge.get_provider_authentication/2`
   - Message conversion via `ReqLlmBridge.convert_messages/1`
   - Tool conversion via `ReqLlmBridge.convert_tools/1`
   - ReqLLM API call
   - Response conversion via `ReqLlmBridge.convert_response/1`
   - Error mapping via `ReqLlmBridge.map_error/1`
5. Implement streaming support using `StreamingAdapter`
6. Write comprehensive tests:
   - Schema validation tests
   - Basic chat completion tests
   - Tool calling tests (if tools provided)
   - Error handling tests
   - Streaming tests
   - Multi-provider tests (OpenAI, Anthropic, etc.)

**Estimated Time:** 4-6 hours

### Phase 2: Create ReqLlm.ToolResponse Action

**Files:**
- `lib/jido_ai/actions/req_llm/tool_response.ex`
- `test/jido_ai/actions/req_llm/tool_response_test.exs`

**Tasks:**
1. Create module structure with Jido.Action behavior
2. Define schema (mirror Langchain.ToolResponse schema)
3. Implement `run/2` using full ReqLlmBridge stack:
   - Create conversation via `ConversationManager`
   - Convert tools via `ToolBuilder.batch_convert/1`
   - Store tools in conversation state
   - Execute chat completion via `ReqLlm.ChatCompletion`
   - Execute tool calls via `ToolExecutor.execute_tool/4`
   - Aggregate response via `ResponseAggregator`
   - Format final result
4. Write comprehensive tests:
   - Schema validation tests
   - Basic tool response tests (mocking LLM calls)
   - Tool execution tests (using real Jido.Actions)
   - Error handling tests
   - Conversation state tests
   - Multi-turn conversation tests
   - Tool execution timeout tests

**Estimated Time:** 4-6 hours

### Phase 3: Update Skill Defaults and Add Deprecation Warnings

**Files:**
- `lib/jido_ai/skill.ex`

**Tasks:**
1. Change default tool_action from `Langchain.ToolResponse` to `ReqLlm.ToolResponse`:
   - Line 30: schema default
   - Line 68: mount function
   - Line 103: router definition
2. Add deprecation warning in `mount/2` when LangChain is explicitly used
3. Update router to use new default while maintaining backward compatibility
4. Run full test suite to ensure no regressions

**Estimated Time:** 1-2 hours

### Phase 4: Integration Testing

**Tasks:**
1. Run complete test suite: `mix test`
2. Run integration tests: `mix test.integration`
3. Test with multiple providers manually:
   - OpenAI
   - Anthropic
   - OpenRouter
   - Google (if available)
4. Verify tool execution works end-to-end
5. Verify conversation state management
6. Test error scenarios (auth failures, timeouts, invalid params)

**Estimated Time:** 2-3 hours

### Phase 5: Documentation Updates

**Files to Update:**
- `guides/actions.md` - Add ReqLLM actions section
- `guides/migration/from-legacy-providers.md` - Add LangChain migration guide
- `README.md` - Update examples to use ReqLLM actions

**Tasks:**
1. Document new ReqLLM actions with examples
2. Create migration guide from LangChain to ReqLLM
3. Update getting started guide with new defaults
4. Add provider support matrix showing 57+ providers

**Estimated Time:** 2-3 hours

---

## 6. Testing Strategy

### 6.1 Unit Tests

**ReqLlm.ChatCompletion Tests:**
```elixir
describe "schema" do
  test "required fields are present"
  test "default values set correctly"
  test "validates model options"
  test "validates prompt options"
end

describe "run/2" do
  test "successfully makes basic chat completion"
  test "handles model validation errors"
  test "handles authentication errors"
  test "handles API errors"
  test "converts messages correctly"
  test "builds options correctly"
  test "formats response correctly"
end

describe "streaming" do
  test "enables streaming when stream: true"
  test "formats streaming chunks correctly"
  test "handles streaming errors"
end

describe "tool calling" do
  test "converts tools when provided"
  test "includes tools in request"
  test "formats tool results"
end
```

**ReqLlm.ToolResponse Tests:**
```elixir
describe "schema" do
  test "required fields are present"
  test "default values set correctly"
end

describe "run/2" do
  test "successfully processes request with tools"
  test "creates conversation for state management"
  test "converts and stores tools"
  test "executes tool calls"
  test "aggregates final response"
  test "handles errors from chat completion"
  test "handles tool execution errors"
  test "handles conversation state errors"
end

describe "tool execution" do
  test "executes single tool call"
  test "executes multiple tool calls"
  test "handles tool execution timeout"
  test "formats tool results correctly"
end
```

### 6.2 Integration Tests

**End-to-End Workflow:**
```elixir
describe "complete workflow" do
  test "user message → tool call → tool execution → final response"
  test "multi-turn conversation with tools"
  test "tool execution with real Jido.Actions"
  test "error recovery and retry"
end
```

### 6.3 Provider Validation Tests

Test with real providers (using environment keys):
- OpenAI: GPT-4, GPT-3.5
- Anthropic: Claude 3.5 Sonnet, Claude 3 Haiku
- OpenRouter: Multiple models
- Google: Gemini (if available)

### 6.4 Backward Compatibility Tests

```elixir
describe "backward compatibility" do
  test "Skill still works with explicit LangChain tool_action"
  test "deprecation warning shown when using LangChain"
  test "existing LangChain tests still pass"
end
```

---

## 7. Risk Mitigation

### Risk: Breaking Existing Users

**Mitigation:**
- Maintain full backward compatibility
- LangChain actions remain available
- Default change only affects new installations
- Deprecation warnings guide migration

### Risk: Missing Provider Features

**Mitigation:**
- ReqLLM already supports 57+ providers
- Feature parity verified through testing
- Can fall back to LangChain if needed

### Risk: Performance Regression

**Mitigation:**
- Benchmark before and after
- ReqLlmBridge infrastructure already tested (540+ tests)
- Can optimize based on benchmarks

### Risk: Test Coverage Gaps

**Mitigation:**
- Match or exceed LangChain test coverage
- Comprehensive unit tests for each action
- Integration tests for end-to-end workflows
- Provider validation tests with real APIs

---

## 8. Future Enhancements

### Post-Migration Opportunities

1. **Deprecate LangChain Dependency**
   - After 1-2 releases with warnings
   - Remove from mix.exs dependencies
   - Lighter application footprint

2. **Expose Additional Provider Features**
   - Provider-specific parameters
   - Advanced tool configurations
   - Multimodal capabilities

3. **Performance Optimizations**
   - Connection pooling
   - Request batching
   - Caching strategies

4. **Enhanced Tool System**
   - Tool composition
   - Tool validation improvements
   - Automatic tool discovery

---

## 9. Notes and Considerations

### Edge Cases to Handle

1. **Tool Execution Timeouts**
   - Use ToolExecutor's timeout mechanism (default 5s)
   - Configurable per-action timeout
   - Graceful degradation

2. **Large Tool Results**
   - JSON serialization limits
   - Response size limits
   - Pagination or truncation strategies

3. **Conversation State Cleanup**
   - ETS table memory management
   - Conversation TTL
   - Cleanup on completion

4. **Provider-Specific Quirks**
   - Different tool format requirements
   - Rate limiting
   - Token counting variations

### Dependencies to Monitor

- **ReqLLM Version**: Currently `~> 1.0.0-rc`
  - Watch for 1.0.0 stable release
  - May introduce breaking changes

- **Jido Version**: Currently `~> 1.2.0`
  - Action behavior changes
  - Schema validation updates

### Documentation Gaps to Fill

- Migration guide from LangChain
- Provider support matrix
- Tool system architecture
- Troubleshooting guide

---

## 10. Approval and Sign-off

### Before Implementation

- [ ] Pascal reviews and approves plan
- [ ] Technical approach validated
- [ ] Timeline approved
- [ ] Success criteria agreed upon

### After Implementation

- [ ] All tests passing
- [ ] Code review completed
- [ ] Documentation updated
- [ ] Ready for merge

---

## Appendix A: Code Examples

### Example: Using New ReqLlm.ToolResponse

```elixir
# Define your tools as Jido Actions
defmodule MyApp.Actions.Calculator do
  use Jido.Action,
    name: "calculator",
    description: "Performs arithmetic operations",
    schema: [
      operation: [type: :string, required: true],
      a: [type: :float, required: true],
      b: [type: :float, required: true]
    ]

  def run(%{operation: "add", a: a, b: b}, _context), do: {:ok, a + b}
  def run(%{operation: "subtract", a: a, b: b}, _context), do: {:ok, a - b}
  def run(%{operation: "multiply", a: a, b: b}, _context), do: {:ok, a * b}
  def run(%{operation: "divide", a: a, b: b}, _context), do: {:ok, a / b}
end

# Use ReqLLM action
alias Jido.AI.Actions.ReqLlm.ToolResponse
alias Jido.AI.{Model, Prompt}

{:ok, model} = Model.from({:anthropic, [model: "claude-3-5-sonnet-latest"]})
prompt = Prompt.new(:user, "What is 25 * 4 + 10?")

{:ok, result} = ToolResponse.run(%{
  model: model,
  prompt: prompt,
  tools: [MyApp.Actions.Calculator]
}, %{})

IO.puts(result.result)
# => "The answer is 110"

IO.inspect(result.tool_results)
# => [
#   %{name: "calculator", arguments: %{operation: "multiply", a: 25, b: 4}, result: 100},
#   %{name: "calculator", arguments: %{operation: "add", a: 100, b: 10}, result: 110}
# ]
```

### Example: Migration from LangChain

**Before (LangChain):**
```elixir
alias Jido.AI.Actions.Langchain.ToolResponse

{:ok, result} = ToolResponse.run(%{
  model: model,
  prompt: prompt,
  tools: [MyAction]
}, %{})
```

**After (ReqLLM):**
```elixir
alias Jido.AI.Actions.ReqLlm.ToolResponse

{:ok, result} = ToolResponse.run(%{
  model: model,
  prompt: prompt,
  tools: [MyAction]
}, %{})
```

**That's it!** The API is identical.

---

## Appendix B: Test Coverage Matrix

| Module | Unit Tests | Integration Tests | Provider Tests |
|--------|-----------|-------------------|----------------|
| ReqLlm.ChatCompletion | ✓ Schema, run/2, streaming, errors | ✓ End-to-end | ✓ OpenAI, Anthropic |
| ReqLlm.ToolResponse | ✓ Schema, run/2, tool execution | ✓ Multi-turn | ✓ OpenAI, Anthropic |
| Skill (updated) | ✓ Defaults, warnings | ✓ Mount, router | N/A |

**Target Coverage:** >90% for new modules

---

## Appendix C: Performance Benchmarks

**Benchmarking Plan:**
- Measure latency: LangChain vs ReqLLM actions
- Measure memory usage
- Measure throughput (requests/second)
- Test with different providers
- Test with/without tools

**Success Criteria:**
- ReqLLM latency within 10% of LangChain
- Memory usage comparable or better
- No significant throughput degradation

---

## Document History

| Date | Author | Changes |
|------|--------|---------|
| 2025-10-21 | Pascal | Initial plan created |
