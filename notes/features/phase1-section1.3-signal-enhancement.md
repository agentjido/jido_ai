# Feature: Phase 1 Section 1.3 - Signal Enhancement

## Problem Statement

The current signal module has basic signal types but lacks:
1. Structured error signaling (errors are embedded in result tuples)
2. Usage/token tracking for cost monitoring
3. Enhanced metadata in ReqLLMResult (model used, duration, thinking content)
4. Helper functions for signal manipulation

**Impact**: No centralized error handling, no usage tracking for billing/monitoring, and developers must manually extract information from signals.

## Solution Overview

1. **New Signal Types**:
   - `ReqLLMError` - Structured error signal with error classification
   - `UsageReport` - Token usage and cost tracking signal

2. **Enhanced Metadata** in ReqLLMResult:
   - `usage` - Input/output token counts
   - `model` - Actual model used
   - `duration_ms` - Request duration
   - `thinking_content` - Extended thinking content (for reasoning models)

3. **Signal Helpers** in `Jido.AI.Signal`:
   - `from_reqllm_response/2` - Create signals from ReqLLM responses
   - `extract_tool_calls/1` - Extract tool calls from result signal
   - `is_tool_call?/1` - Check if signal contains tool calls

## Technical Details

### Already Implemented (from Section 1.2)
- `EmbedResult` signal - Already created in section 1.2

### Files to Modify
- `lib/jido_ai/signal.ex` - Add ReqLLMError, UsageReport, helper functions, enhance ReqLLMResult
- `test/jido_ai/signal_test.exs` - Unit tests for new signals and helpers

### Signal Schema Designs

**ReqLLMError**:
```elixir
schema: [
  call_id: [type: :string, required: true],
  error_type: [type: :atom, required: true],  # :rate_limit, :auth, :timeout, :provider_error, :validation
  message: [type: :string, required: true],
  details: [type: :map, default: %{}],
  retry_after: [type: :integer]  # optional, for rate limits
]
```

**UsageReport**:
```elixir
schema: [
  call_id: [type: :string, required: true],
  model: [type: :string, required: true],
  input_tokens: [type: :integer, required: true],
  output_tokens: [type: :integer, required: true],
  total_tokens: [type: :integer],
  duration_ms: [type: :integer],
  metadata: [type: :map, default: %{}]
]
```

**Enhanced ReqLLMResult** (additional optional fields):
```elixir
schema: [
  # existing fields...
  usage: [type: :map],           # %{input_tokens: N, output_tokens: M}
  model: [type: :string],        # actual model used
  duration_ms: [type: :integer], # request duration
  thinking_content: [type: :string]  # extended thinking output
]
```

## Success Criteria

1. ReqLLMError signal can be created with error classification
2. UsageReport signal tracks token usage
3. ReqLLMResult accepts optional usage, model, duration_ms, thinking_content
4. Helper functions work correctly for signal manipulation
5. All unit tests pass

## Implementation Plan

### Step 1: Add ReqLLMError Signal (1.3.1.2)
- [x] 1.3.1.2 Create `Jido.AI.Signal.ReqLLMError` module
- [x] Define schema with error_type, message, details, retry_after

### Step 2: Add UsageReport Signal (1.3.1.3)
- [x] 1.3.1.3 Create `Jido.AI.Signal.UsageReport` module
- [x] Define schema with model, input_tokens, output_tokens, duration_ms

### Step 3: Enhance ReqLLMResult Metadata (1.3.2)
- [x] 1.3.2.1 Add `usage` field to ReqLLMResult
- [x] 1.3.2.2 Add `model` field to ReqLLMResult
- [x] 1.3.2.3 Add `duration_ms` field to ReqLLMResult
- [x] 1.3.2.4 Add `thinking_content` field to ReqLLMResult

### Step 4: Signal Helpers (1.3.3)
- [x] 1.3.3.1 Implement `from_reqllm_response/2`
- [x] 1.3.3.2 Implement `extract_tool_calls/1`
- [x] 1.3.3.3 Implement `is_tool_call?/1`

### Step 5: Unit Tests (1.3.4)
- [x] Test ReqLLMError signal creation
- [x] Test UsageReport signal creation
- [x] Test enhanced metadata in ReqLLMResult
- [x] Test from_reqllm_response/2 conversion
- [x] Test extract_tool_calls/1 helper
- [x] Test is_tool_call?/1 predicate

## Current Status

**Status**: Complete
**What works**: All signals implemented, helper functions working, 34 signal tests passing
**What's next**: Commit and merge to v2 branch
**How to run**: `mix test test/jido_ai/signal_test.exs`

## Notes/Considerations

- EmbedResult was already implemented in section 1.2, so 1.3.1.1 is complete
- ReqLLMResult enhancement requires backward compatibility (all new fields optional)
- Helper functions should be defined in the parent `Jido.AI.Signal` module
- from_reqllm_response/2 should handle both streaming and non-streaming responses
