# Section 1.3.1 Chat/Completion Actions - Implementation Plan

## 1. Problem Statement

### Current State
The current implementation uses `OpenaiEx.Chat.Completions.create` for chat completion functionality in `/home/ducky/code/agentjido/jido_ai_integrate_req_llm/lib/jido_ai/actions/openaiex.ex`. This provider-specific approach limits flexibility and requires separate implementations for each LLM provider.

### Impact Analysis
- **Primary Action**: `Jido.AI.Actions.OpenaiEx` currently handles chat completions via OpenaiEx library
- **Critical Dependencies**:
  - `OpenaiEx.Chat.Completions.create` calls on lines 300 and 346
  - Provider-specific message building via `ChatMessage.user()`, `ChatMessage.assistant()`, etc.
  - Tool integration through `Jido.AI.Actions.OpenaiEx.ToolHelper`
- **Consumer Impact**: Multiple actions depend on this infrastructure:
  - `Jido.AI.Actions.Instructor.ChatResponse`
  - Various demo and example files
  - Tool calling functionality

### Migration Scope
Replace provider-specific implementations with ReqLLM's unified interface while maintaining full backward compatibility for all consumer contracts.

## 2. Solution Overview

### Design Decisions
1. **Gradual Migration**: Replace OpenaiEx calls with ReqLLM while preserving all external interfaces
2. **Response Shape Preservation**: Maintain exact response structures that downstream consumers expect
3. **Error Handling Continuity**: Preserve existing error patterns and logging behavior
4. **Tool Support**: Ensure tool calling functionality continues to work seamlessly

### Architecture Strategy
- Leverage existing `Jido.AI.ReqLLM` bridge module for format conversion
- Maintain `Jido.AI.Actions.OpenaiEx` as primary interface
- Use ReqLLM's `generate_text/3` function as underlying implementation
- Preserve all existing parameter validation and transformation logic

## 3. Technical Details

### Key Files to Modify
- **Primary**: `/home/ducky/code/agentjido/jido_ai_integrate_req_llm/lib/jido_ai/actions/openaiex.ex`
- **Bridge**: `/home/ducky/code/agentjido/jido_ai_integrate_req_llm/lib/jido_ai/req_llm.ex` (already exists)
- **Tool Helper**: `/home/ducky/code/agentjido/jido_ai_integrate_req_llm/lib/jido_ai/actions/openai_ex/tool_helper.ex` (response processing)

### Dependencies
- ReqLLM (already added in Section 1.1)
- Existing `Jido.AI.Model` with `reqllm_id` field (added in Section 1.2)
- `Jido.AI.ReqLLM` bridge module (created in Section 1.1)

## 4. Current Implementation Analysis

### OpenaiEx.Chat.Completions.create Usage Patterns

#### Standard Chat Completion (Line 300)
```elixir
Chat.Completions.create(client, chat_req)
```

#### Streaming Chat Completion (Line 346)
```elixir
Chat.Completions.create(client, chat_req)
```

### Message Format Analysis

#### Current Jido Format
```elixir
messages = [
  %{role: :user, content: "Hello"},
  %{role: :assistant, content: "Hi there!"},
  %{role: :system, content: "You are helpful"}
]
```

#### OpenaiEx Internal Format
```elixir
chat_messages = [
  ChatMessage.user("Hello"),
  ChatMessage.assistant("Hi there!"),
  ChatMessage.system("You are helpful")
]
```

#### ReqLLM Expected Format
ReqLLM accepts both string prompts and message lists directly:
```elixir
# Simple string format
"Hello world"

# Message format (compatible with Jido)
[
  %{role: :user, content: "Hello"},
  %{role: :assistant, content: "Hi there!"}
]
```

## 5. ReqLLM Integration Strategy

### Function Signature Analysis
```elixir
@spec ReqLLM.generate_text(
  String.t() | {atom(), keyword()} | struct(),  # model_spec
  String.t() | list(),                          # messages
  keyword()                                     # opts
) :: {:ok, Response.t()} | {:error, term()}
```

### Parameter Mapping Strategy
1. **Model**: Use `model.reqllm_id` from enhanced Model struct
2. **Messages**: Direct conversion via `Jido.AI.ReqLLM.convert_messages/1`
3. **Options**: Map via `Jido.AI.ReqLLM.build_req_llm_options/1`

### Tools Integration
- Convert Jido Actions to ReqLLM tools via `Jido.AI.ReqLLM.convert_tools/1`
- Maintain existing tool response processing patterns

## 6. Message Format Conversion Design

### Conversion Requirements
The bridge module already provides conversion functions:

#### From Jido to ReqLLM
```elixir
# Simple case - single user message becomes string
Jido.AI.ReqLLM.convert_messages([%{role: :user, content: "Hello"}])
#=> "Hello"

# Complex case - multiple messages preserved as list
Jido.AI.ReqLLM.convert_messages([
  %{role: :system, content: "System prompt"},
  %{role: :user, content: "User message"}
])
#=> [%{role: :system, content: "System prompt"}, %{role: :user, content: "User message"}]
```

#### Parameter Conversion
```elixir
Jido.AI.ReqLLM.build_req_llm_options(%{
  temperature: 0.7,
  max_tokens: 1000,
  tools: [SomeAction]
})
#=> %{temperature: 0.7, max_tokens: 1000, tools: [converted_tools]}
```

## 7. Response Preservation Strategy

### Current Response Structure
The current implementation returns:
```elixir
{:ok, %{content: content, tool_results: results}}
```

### ReqLLM Response Format
ReqLLM returns `{:ok, %ReqLLM.Response{}}` with structured metadata.

### Conversion Strategy
Use `Jido.AI.ReqLLM.convert_response/1` to transform:
```elixir
{:ok, req_llm_response} = ReqLLM.generate_text(model_spec, messages, opts)
converted = Jido.AI.ReqLLM.convert_response(req_llm_response)
#=> %{content: "...", usage: %{...}, tool_calls: [...], finish_reason: "..."}
```

### Tool Response Processing
Maintain existing `ToolHelper.process_response/2` pattern but adapt for ReqLLM response format.

## 8. Success Criteria

### Functional Requirements
1. **API Compatibility**: All existing `Jido.AI.Actions.OpenaiEx.run/2` calls continue to work without modification
2. **Response Shape**: Responses maintain exact structure expected by consumers
3. **Error Handling**: Error patterns and structures remain unchanged
4. **Tool Support**: Tool calling functionality operates identically to current implementation
5. **Streaming**: Streaming responses (if supported) maintain chunk format compatibility

### Performance Requirements
1. **Response Time**: No significant degradation in response times
2. **Memory Usage**: Similar or improved memory footprint
3. **Error Rates**: No increase in error rates due to format conversion

### Quality Requirements
1. **Test Coverage**: All existing tests continue to pass
2. **Backward Compatibility**: Zero breaking changes for existing consumers
3. **Provider Support**: Support for all currently supported providers through ReqLLM

## 9. Implementation Plan

### Stage 1: Core Function Replacement
**Duration**: 1-2 hours
**Scope**: Replace OpenaiEx calls with ReqLLM in non-streaming scenarios

#### Tasks:
1. **Update `make_request/2` function**
   - Replace `Chat.Completions.create(client, chat_req)` with ReqLLM call
   - Use `model.reqllm_id` as model specification
   - Convert messages via bridge module
   - Transform parameters for ReqLLM compatibility

2. **Response transformation**
   - Adapt response handling to work with ReqLLM.Response format
   - Ensure tool response processing continues to work
   - Maintain error mapping patterns

#### Implementation Details:
```elixir
defp make_request(model, chat_req) do
  # Convert OpenaiEx request to ReqLLM format
  messages = convert_chat_messages_to_jido_format(chat_req.messages)
  opts = build_req_llm_options_from_chat_req(chat_req)

  case ReqLLM.generate_text(model.reqllm_id, messages, opts) do
    {:ok, response} ->
      # Convert ReqLLM response to expected OpenaiEx format
      {:ok, convert_to_openai_response_format(response)}

    {:error, error} ->
      # Map ReqLLM errors to existing error patterns
      Jido.AI.ReqLLM.map_error({:error, error})
  end
end
```

### Stage 2: Streaming Support
**Duration**: 1-2 hours
**Scope**: Replace streaming functionality with ReqLLM streaming

#### Tasks:
1. **Update `make_streaming_request/2` function**
   - Research ReqLLM streaming API
   - Replace OpenaiEx streaming with ReqLLM equivalent
   - Maintain chunk format compatibility

#### Implementation Details:
```elixir
defp make_streaming_request(model, chat_req) do
  messages = convert_chat_messages_to_jido_format(chat_req.messages)
  opts = build_req_llm_options_from_chat_req(chat_req) |> Keyword.put(:stream, true)

  # Note: Need to verify ReqLLM streaming API
  ReqLLM.stream_text(model.reqllm_id, messages, opts)
end
```

### Stage 3: Parameter Handling
**Duration**: 1 hour
**Scope**: Ensure all OpenaiEx parameters map correctly to ReqLLM

#### Tasks:
1. **Parameter mapping verification**
   - Verify all `chat_req` fields map to ReqLLM options
   - Handle provider-specific parameters
   - Ensure tool choice and tool parameters work correctly

### Stage 4: Error Handling Migration
**Duration**: 30 minutes
**Scope**: Ensure all error patterns are preserved

#### Tasks:
1. **Error mapping validation**
   - Test existing error handling patterns
   - Ensure ReqLLM errors map to expected formats
   - Verify logging preservation

### Stage 5: Google Provider Special Handling
**Duration**: 1 hour
**Scope**: Migrate Google-specific request handling

#### Tasks:
1. **Google provider migration**
   - Replace `make_google_request/3` with ReqLLM equivalent
   - Ensure Google-specific formatting is handled by ReqLLM
   - Test Google provider functionality

### Stage 6: Testing and Validation
**Duration**: 1-2 hours
**Scope**: Comprehensive testing of migration

#### Tasks:
1. **Unit test updates**
   - Update tests to work with ReqLLM responses
   - Add new tests for conversion functions
   - Ensure all existing tests pass

2. **Integration testing**
   - Test with real provider APIs
   - Verify tool calling functionality
   - Test streaming if implemented

## 10. Testing Strategy

### Unit Tests
1. **Message Conversion Tests**
   - Test conversion from OpenaiEx ChatMessage format to Jido format
   - Test Jido to ReqLLM message conversion
   - Test edge cases and malformed messages

2. **Response Conversion Tests**
   - Test ReqLLM response to OpenaiEx format conversion
   - Test tool response handling
   - Test error response mapping

3. **Parameter Mapping Tests**
   - Test all OpenaiEx parameters map correctly to ReqLLM
   - Test provider-specific parameter handling
   - Test default value preservation

### Integration Tests
1. **End-to-End Tests**
   - Test full request/response cycle with real models
   - Test tool calling functionality
   - Test streaming functionality (if implemented)

2. **Provider Tests**
   - Test multiple providers (OpenAI, Anthropic, etc.)
   - Test provider-specific features
   - Test error scenarios

### Backward Compatibility Tests
1. **Consumer Tests**
   - Ensure all consuming actions continue to work
   - Test instructor integration
   - Test example/demo functionality

2. **API Contract Tests**
   - Verify response shapes remain identical
   - Test error format preservation
   - Test parameter validation continuity

## 11. Risk Mitigation

### Technical Risks
1. **Response Format Changes**: Mitigation through comprehensive conversion layer
2. **Tool Calling Incompatibility**: Mitigation through bridge module tool conversion
3. **Provider Differences**: Mitigation through ReqLLM's provider abstraction
4. **Performance Degradation**: Mitigation through performance testing

### Implementation Risks
1. **Breaking Changes**: Mitigation through extensive backward compatibility testing
2. **Feature Gaps**: Mitigation through feature parity verification
3. **Error Handling**: Mitigation through comprehensive error mapping

## 12. Rollback Plan

### Preparation
1. **Version Control**: Ensure all changes are in feature branch
2. **Backup**: Maintain original implementation as reference
3. **Testing**: Comprehensive test suite to validate rollback

### Rollback Triggers
1. **Test Failures**: Any existing test failures
2. **Performance Issues**: Significant performance degradation
3. **Consumer Breakage**: Any breaking changes for existing consumers

### Rollback Process
1. **Immediate**: Revert to previous OpenaiEx implementation
2. **Verification**: Run full test suite to confirm restoration
3. **Analysis**: Investigate and resolve issues before retry

## 13. Monitoring and Validation

### Success Metrics
1. **Test Pass Rate**: 100% of existing tests continue to pass
2. **Response Time**: No more than 10% increase in average response time
3. **Error Rate**: No increase in error rates
4. **Memory Usage**: No significant increase in memory consumption

### Validation Process
1. **Automated Testing**: Run full test suite
2. **Manual Testing**: Test key use cases manually
3. **Performance Testing**: Benchmark before and after migration
4. **Integration Testing**: Test with dependent modules

This plan provides a systematic approach to migrating from OpenaiEx to ReqLLM while maintaining full backward compatibility and preserving all existing functionality.