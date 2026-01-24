# Phase 4B.1 TRM Machine Feature

**Branch**: `feature/phase4b-trm-machine`
**Started**: 2026-01-04
**Completed**: 2026-01-04
**Status**: COMPLETED

## Problem Statement

Phase 4B (TRM Strategy) requires a pure state machine to manage the recursive reasoning loop. The TRM Machine is the foundation for the TRM (Tiny-Recursive-Model) strategy which iteratively improves answers through a reason-supervise-improve cycle.

## Solution Overview

Implement `Jido.AI.TRM.Machine` following the established Fsmx-based machine pattern from ReAct and CoT. The machine manages:
1. Recursive loop states: idle → reasoning → supervising → improving → (loop or completed)
2. Latent state tracking across recursion steps
3. Answer history accumulation
4. ACT (Adaptive Computational Time) early stopping
5. Deep supervision step tracking

## Technical Details

### Module Location
- `lib/jido_ai/trm/machine.ex`

### Dependencies
- `Fsmx.Struct` - State machine management
- `Jido.Util.generate_id/0` - ID generation

### State Machine Transitions
```
idle → reasoning → supervising → improving → reasoning (loop)
                                           → completed (terminate)
```

### Struct Fields
- `status` - Current state (idle, reasoning, supervising, improving, completed, error)
- `question` - Original question/prompt
- `current_answer` - Current answer being refined
- `answer_history` - List of all answers for progression tracking
- `latent_state` - Accumulated reasoning context
- `supervision_step` - Current supervision iteration (1-based)
- `max_supervision_steps` - Maximum iterations before forced termination
- `act_threshold` - Confidence threshold for early stopping
- `act_triggered` - Whether ACT triggered early termination
- `best_answer` - Best answer seen so far
- `best_score` - Best quality score seen
- `current_call_id` - Current LLM request ID
- `termination_reason` - Why the machine completed
- `streaming_text` - Accumulated streaming text
- `usage` - Token usage accumulator
- `started_at` - Timestamp for duration calculation

### Message Types
- `{:start, question, call_id}` - Start reasoning with a question
- `{:reasoning_result, call_id, result}` - LLM reasoning response
- `{:supervision_result, call_id, result}` - LLM supervision feedback
- `{:improvement_result, call_id, result}` - LLM improved answer
- `{:llm_partial, call_id, delta, chunk_type}` - Streaming chunk

### Directive Types
- `{:reason, id, context}` - Request reasoning LLM call
- `{:supervise, id, context}` - Request supervision LLM call
- `{:improve, id, context}` - Request improvement LLM call

## Implementation Plan

### Step 1: Create Module Structure
- [x] Create `lib/jido_ai/trm/machine.ex`
- [x] Add `use Fsmx.Struct` with transition map
- [x] Define telemetry prefix
- [x] Define types and struct

### Step 2: Implement State Transitions
- [x] Implement `new/0` and `new/1`
- [x] Implement `update/3` dispatcher
- [x] Implement `:start` handler (idle → reasoning)
- [x] Implement `:reasoning_result` handler (reasoning → supervising)
- [x] Implement `:supervision_result` handler (supervising → improving)
- [x] Implement `:improvement_result` handler (improving → reasoning or completed)
- [x] Implement `:llm_partial` handler

### Step 3: Implement Latent State Management
- [x] Implement `initialize_latent_state/2`
- [x] Implement `update_latent_state/3`
- [x] Implement `extract_confidence/1`
- [x] Implement `merge_reasoning_trace/2`

### Step 4: Implement Termination Conditions
- [x] Implement `should_terminate?/1`
- [x] Implement `check_act_condition/1`
- [x] Implement `complete_with_best/1`
- [x] Add telemetry events

### Step 5: Implement Serialization
- [x] Implement `to_map/1`
- [x] Implement `from_map/1`
- [x] Implement `generate_call_id/0`

### Step 6: Write Unit Tests
- [x] Test `new/0` creates idle machine
- [x] Test `new/1` accepts options
- [x] Test `:start` transition
- [x] Test `:reasoning_result` transition
- [x] Test `:supervision_result` transition
- [x] Test `:improvement_result` loop
- [x] Test `:improvement_result` completion
- [x] Test ACT early stopping
- [x] Test max_supervision_steps termination
- [x] Test answer_history accumulation
- [x] Test `to_map/from_map` round-trip

## Current Status

**What works**: All 43 unit tests pass. 912 total tests in suite pass.
**How to run**: `mix test test/jido_ai/trm/machine_test.exs`

## Notes

- Follow patterns from `Jido.AI.ChainOfThought.Machine` and `Jido.AI.ReAct.Machine`
- Keep machine pure - no side effects, only return directives
- Latent state stores reasoning trace for context across iterations
- ACT threshold defaults to 0.9 (90% confidence)
- Default max_supervision_steps is 5
