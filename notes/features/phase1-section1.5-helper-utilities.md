# Feature: Phase 1 Section 1.5 - Helper Utilities

## Problem Statement

Common patterns when working with ReqLLM are repeated across the codebase:
1. Building message contexts with system prompts
2. Adding tool results to contexts
3. Extracting text and tool calls from responses
4. Classifying response types (tool calls vs final answer)
5. Converting ReqLLM errors to Jido.AI.Error

**Impact**: Developers must write boilerplate code for common operations, leading to inconsistencies.

## Solution Overview

Create `lib/jido_ai/helpers.ex` with utility functions that wrap common ReqLLM patterns.

**Design Decisions**:
1. Use `ReqLLM.Context` functions where they exist (don't duplicate)
2. Provide thin wrappers for Jido.AI-specific patterns
3. Focus on error classification and conversion since that's Jido.AI-specific

**Note**: ReqLLM.Context already provides excellent message building functions:
- `ReqLLM.Context.user/1,2`, `system/1,2`, `assistant/1,2`
- `ReqLLM.Context.tool_result/2,3`, `tool_result_message/4`
- `ReqLLM.Context.normalize/2` for context building
- `ReqLLM.Context.append/2`, `prepend/2`

We should NOT duplicate these but instead provide Jido.AI-specific helpers.

## Technical Details

### Files to Create
- `lib/jido_ai/helpers.ex` - Helper utilities module
- `test/jido_ai/helpers_test.exs` - Unit tests

### Helper Functions

#### 1.5.1 Message Building (Wrappers)

```elixir
# Thin wrapper that delegates to ReqLLM.Context.normalize
build_messages(prompt, opts \\ [])
  - :system_prompt - System message to add
  - Returns {:ok, context} | {:error, reason}

# Delegates to ReqLLM.Context.prepend with system message
add_system_message(context, system_prompt)
  - Returns context with system message prepended

# Wrapper for ReqLLM.Context.tool_result_message/4
add_tool_result(context, tool_call_id, tool_name, result)
  - Encodes result to JSON if needed
  - Returns updated context
```

#### 1.5.2 Response Processing

```elixir
# Extract text from ReqLLM response
extract_text(response)
  - Handles string content
  - Handles list of ContentParts
  - Returns string

# Extract tool calls from response
extract_tool_calls(response)
  - Returns list of tool call maps
  - Already exists in Signal module, may re-export

# Check if response has tool calls
has_tool_calls?(response)
  - Returns boolean

# Classify response type
classify_response(response)
  - Returns :tool_calls | :final_answer | :error
```

#### 1.5.3 Error Handling

```elixir
# Convert ReqLLM error to Jido.AI.Error
wrap_error(error)
  - Maps ReqLLM.Error types to Jido.AI.Error
  - Classifies error type

# Classify error type
classify_error(error)
  - Returns :rate_limit | :auth | :timeout | :provider_error | :network | :validation | :unknown

# Extract retry-after from rate limit error
extract_retry_after(error)
  - Returns integer seconds or nil
```

## Success Criteria

1. `build_messages/2` creates valid ReqLLM.Context
2. `add_system_message/2` prepends system message correctly
3. `add_tool_result/4` formats tool results correctly
4. `extract_text/1` handles various response formats
5. `classify_response/1` correctly detects tool calls vs final answer
6. `wrap_error/1` converts errors with correct classification
7. All unit tests pass

## Implementation Plan

### Step 1: Message Building (1.5.1)
- [x] 1.5.1.1 Create `lib/jido_ai/helpers.ex` with module documentation
- [x] 1.5.1.2 Implement `build_messages/2` delegating to ReqLLM.Context.normalize
- [x] 1.5.1.3 Implement `add_system_message/2`
- [x] 1.5.1.4 Implement `add_tool_result/4` for tool result messages

### Step 2: Response Processing (1.5.2)
- [x] 1.5.2.1 Implement `extract_text/1` from ReqLLM response
- [x] 1.5.2.2 Implement `extract_tool_calls/1` from response
- [x] 1.5.2.3 Implement `has_tool_calls?/1` predicate
- [x] 1.5.2.4 Implement `classify_response/1`

### Step 3: Error Handling (1.5.3)
- [x] 1.5.3.1 Implement `wrap_error/1` to convert ReqLLM errors
- [x] 1.5.3.2 Implement `classify_error/1`
- [x] 1.5.3.3 Implement `extract_retry_after/1`

### Step 4: Unit Tests (1.5.4)
- [x] Test build_messages/2 creates valid context
- [x] Test add_system_message/2 prepends system
- [x] Test add_tool_result/4 formats correctly
- [x] Test extract_text/1 handles various response formats
- [x] Test classify_response/1 detection
- [x] Test wrap_error/1 error classification
- [x] Test extract_retry_after/1

## Current Status

**Status**: Complete
**What works**: All features implemented and tested (45 tests passing)
**How to run**: `mix test test/jido_ai/helpers_test.exs`

## Notes/Considerations

- ReqLLM.Context already provides excellent message building functions
- We should delegate to ReqLLM where possible, not duplicate
- Error classification is Jido.AI-specific and adds value
- Response processing helpers are thin wrappers for consistency
