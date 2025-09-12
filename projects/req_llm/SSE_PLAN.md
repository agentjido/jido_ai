# SSE Streaming Implementation Plan

## Overview
Implement robust SSE (Server-Sent Events) streaming for the ReqLLM Anthropic provider using Req steps and the `server_sent_events` library. This plan separates transport-level concerns (handled by a generic Req step) from business-logic concerns (handled by the provider), while ensuring both streaming and non-streaming responses work seamlessly.

## Current State Analysis

### Issues with Current Implementation
1. **Hand-rolled SSE parsing**: Both in stream step AND provider with limitations:
   - No use of `server_sent_events` library despite being available
   - Custom parsing that doesn't handle UTF-8 boundary splits
   - Missing support for multi-line data, comments, retry fields
2. **Code duplication**: Two identical `convert_to_stream_chunk/1` functions (lines 414-444 and 447-477)
3. **Mixed responsibilities**: Provider still does SSE parsing as fallback
4. **Incorrect terminology**: Called a "plugin" but it's actually a Req step

### Desired Architecture
- **Stream Step** (`ReqLLM.Plugins.Stream`): Handles SSE parsing using `server_sent_events` library
- **Provider layer** (`ReqLLM.Providers.Anthropic`): Translates parsed SSE events to ReqLLM chunks, supports both streaming AND non-streaming

## Implementation Steps

### Step 1: Verify server_sent_events Dependency
**Assignable to: Sub-agent**
**Files to modify**: `mix.exs`

- Ensure `{:server_sent_events, "~> 0.5"}` is in dependencies
- Run `mix deps.get` to fetch if needed
- Verify the library documentation and API

### Step 2: Rewrite Stream Step with server_sent_events Library
**Assignable to: Sub-agent** 
**Files to modify**: `lib/req_llm/plugins/stream.ex`

Replace the hand-rolled SSE parsing with the `server_sent_events` library:
- Use `ServerSentEvents.decode_stream/1` for robust parsing
- Handle both `Stream` and binary responses 
- Only process `text/event-stream` content type
- Return parsed SSE events as structured maps
- Set appropriate timeouts for streaming connections

**Requirements**:
- Remove custom SSE parsing logic (`parse_sse_chunk/1`, `accumulate_chunks/2`, etc.)
- Use `ServerSentEvents.decode_stream/1` for stream processing
- Maintain the `attach/1` interface for Req step attachment
- Handle both streaming and non-streaming responses appropriately
- Preserve existing behavior for non-SSE responses

### Step 3: Refactor Provider to Handle Both Streaming and Non-Streaming
**Assignable to: Sub-agent**
**Files to modify**: `lib/req_llm/providers/anthropic.ex`

Clean up the Anthropic provider to handle both response types properly:
- Remove hand-rolled SSE parsing functions (`parse_sse_events/1`, `parse_sse_event/1`) 
- Consolidate duplicate `convert_to_stream_chunk/1` functions into single `to_stream_chunk/1`
- Update `parse_stream/2` to handle both pre-parsed SSE events AND raw binary fallback
- Ensure `parse_response/2` works for non-streaming JSON responses
- Keep `maybe_install_stream_steps/2` to conditionally attach stream step

**Requirements**:
- Handle both streaming (with parsed SSE events) and non-streaming (JSON) responses
- Remove duplicate `convert_to_stream_chunk/1` functions
- Single `to_stream_chunk/1` function with clean pattern matching
- Maintain backward compatibility with existing API

### Step 4: Improve Business Logic Event Handling
**Assignable to: Sub-agent**
**Files to modify**: `lib/req_llm/providers/anthropic.ex`

Enhance the event-to-chunk conversion:
- Use pattern matching instead of nested case statements
- Add module attributes for constants (`@finish_events`, etc.)
- Implement proper completion detection with `finish_reason`
- Handle thinking blocks and tool calls robustly
- Add structured logging for unknown event types

**Requirements**:
- Single `to_stream_chunk/1` function with pattern matching
- Emit `ReqLLM.StreamChunk.meta(%{finish_reason: reason})` for completion
- Forward unknown events as `ReqLLM.StreamChunk.meta(%{raw_event: event})`
- Use `with` statements for readable JSON parsing

### Step 5: Error Handling and Edge Cases
**Assignable to: Sub-agent**  
**Files to modify**: Multiple

Implement comprehensive error handling:
- Transport-level errors (connection closed, timeout, TLS issues)
- Parser-level errors (invalid UTF-8, malformed SSE)
- Business-level errors (unexpected event types, malformed JSON)
- Proper error types using `ReqLLM.Error.*` hierarchy

**Requirements**:
- Define appropriate error types in error module
- Convert transport errors to structured exceptions
- Log unknown business events with `Logger.debug/2`
- Ensure streams close cleanly on errors

### Step 6: Update Demo Scripts  
**Assignable to: Sub-agent**
**Files to modify**: `demo_anthropic_streaming.exs`

Simplify the streaming demo to use the new architecture:
- Remove manual SSE parsing from demo
- Use the provider's streaming interface cleanly  
- Add examples of error handling
- Demonstrate different streaming consumption patterns

**Requirements**:
- Clean, readable demo code
- Show real-time streaming output
- Demonstrate error scenarios
- Include usage statistics extraction

### Step 7: Comprehensive Testing
**Assignable to: Sub-agent**
**Files to create**: `test/req_llm/plugins/stream_test.exs`, update provider tests

Create comprehensive test suite:
- Plugin tests for SSE parsing edge cases
- Provider tests for event-to-chunk conversion  
- Integration tests for end-to-end streaming
- Error handling tests for various failure modes

**Test scenarios**:
- Single-event body (non-chunked response)
- Multi-chunk SSE with UTF-8 boundary splits
- Comment/ping frames in SSE stream
- Malformed JSON in event data
- Network interruptions and timeouts
- Unknown event types
- Completion detection

### Step 8: Documentation Updates
**Assignable to: Sub-agent**
**Files to modify**: Provider moduledoc, README sections

Update documentation to reflect new architecture:
- Document the plugin/provider separation
- Add streaming examples to moduledoc
- Update README with streaming usage
- Document error handling patterns

**Requirements**:
- Clear examples of streaming usage
- Explain plugin vs provider responsibilities  
- Document error types and handling
- Include performance considerations

## Success Criteria

### Functional Requirements
- [ ] SSE streams parse correctly with `server_sent_events` library
- [ ] All Anthropic event types convert to appropriate `ReqLLM.StreamChunk` types  
- [ ] Proper completion detection with `finish_reason`
- [ ] Robust error handling for all failure modes
- [ ] Clean separation between plugin and provider responsibilities

### Code Quality Requirements  
- [ ] No duplicate code or functions
- [ ] Comprehensive typespecs on all public functions
- [ ] Pattern matching preferred over nested case statements
- [ ] Proper error types using ReqLLM error hierarchy
- [ ] Idiomatic Elixir code following project conventions

### Testing Requirements
- [ ] Unit tests for all SSE parsing edge cases
- [ ] Integration tests for end-to-end streaming
- [ ] Error handling tests for network and parsing failures
- [ ] Performance tests for long-running streams
- [ ] Demo scripts work reliably

## Dependencies Between Steps

```
Step 1 (Dependencies) 
├─→ Step 2 (Stream Plugin)
├─→ Step 3 (Provider Refactor) 
│   └─→ Step 4 (Event Handling)
│       └─→ Step 5 (Error Handling)
│           ├─→ Step 6 (Demo Updates)
│           ├─→ Step 7 (Testing) 
│           └─→ Step 8 (Documentation)
```

## Notes for Sub-agents

- Follow the existing code style and patterns in the ReqLLM project
- Use the `ReqLLM.Error.*` hierarchy for all error types  
- Maintain backward compatibility where possible
- Add comprehensive typespecs and documentation
- Test edge cases thoroughly, especially UTF-8 boundary conditions
- Reference the `server_sent_events` library documentation for proper usage patterns
