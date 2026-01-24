# Phase 4A.2: Chain-of-Thought Strategy

## Summary

Implement the Chain-of-Thought (CoT) strategy following the same architectural pattern as ReAct: pure Fsmx state machine + thin strategy adapter.

## Task Description

Implement section 4.2 of the Phase 4 strategies plan - Chain-of-Thought Strategy for step-by-step reasoning.

## Design Analysis

### Key Differences from ReAct

| Aspect | ReAct | Chain-of-Thought |
|--------|-------|------------------|
| Purpose | Tool-based reasoning | Pure step-by-step reasoning |
| States | idle → awaiting_llm → awaiting_tool → completed | idle → reasoning → completed |
| Directives | call_llm_stream, exec_tool | call_llm_stream only (no tools) |
| System Prompt | Focus on tool usage | "Let's think step by step..." |
| Output | Final answer after tool loops | Step-by-step reasoning + conclusion |

### Architecture

Following the ReAct pattern:
```
Strategy (thin adapter)     → Signal routing, config, directive lifting
    ↓
Machine (pure Fsmx FSM)     → State transitions, returns directives (no side effects)
    ↓
Directives                  → ReqLLMStream only (no tools in CoT)
```

## Implementation Plan

### 4.2.1 Machine Implementation ✅ COMPLETE
- [x] Create `lib/jido_ai/chain_of_thought/machine.ex` with Fsmx
- [x] Define states: `:idle`, `:reasoning`, `:completed`, `:error`
- [x] Define transitions following Fsmx pattern
- [x] Implement `update/3` for message handling
- [x] Return `{machine, directives}` tuple (pure, no side effects)

### 4.2.2 Message Types ✅ COMPLETE
- [x] `{:start, prompt, call_id}` - Start CoT reasoning
- [x] `{:llm_result, call_id, result}` - Handle LLM response
- [x] `{:llm_partial, call_id, delta, chunk_type}` - Handle streaming

### 4.2.3 Directive Types ✅ COMPLETE
- [x] `{:call_llm_stream, id, context}` - Request LLM call with CoT prompt
- [x] Build CoT system prompt ("Let's think step by step...")

### 4.2.4 Strategy Implementation ✅ COMPLETE
- [x] Create `lib/jido_ai/strategies/chain_of_thought.ex`
- [x] Use `Jido.Agent.Strategy` macro
- [x] Implement `init/2` to create machine and build config
- [x] Implement `cmd/3` to process instructions via machine
- [x] Implement `signal_routes/1` for signal → command routing
- [x] Implement `snapshot/2` for state inspection
- [x] Implement `lift_directives/2` to convert machine directives to SDK directives

### 4.2.5 Step Extraction ✅ COMPLETE
- [x] Parse numbered step format ("Step 1:", "Step 2:", etc.)
- [x] Parse bullet point format
- [x] Detect final conclusion/answer
- [x] Store steps in machine state

### 4.2.6 Unit Tests ✅ COMPLETE
- [x] Test machine state transitions
- [x] Test machine returns correct directives
- [x] Test strategy signal routing
- [x] Test step extraction from responses
- [x] Test CoT prompt generation
- [x] Test conclusion detection

## File Structure

```
lib/jido_ai/
├── chain_of_thought/
│   └── machine.ex           # Pure Fsmx state machine
└── strategies/
    └── chain_of_thought.ex  # Strategy adapter

test/jido_ai/
├── chain_of_thought/
│   └── machine_test.exs     # Machine unit tests
└── strategies/
    └── chain_of_thought_test.exs  # Strategy unit tests
```

## Status

**COMPLETE** - 2026-01-06

## Phase 4A Status

Phase 4A is fully complete:
- **4A.1 GEPA** - Complete (188 tests passing) - See `notes/features/phase4a-gepa.md`
- **4A.2 Chain-of-Thought** - Complete (49 tests passing) - This document

**Phase 4A Total: 237 tests, all passing**

## Test Results

All 49 tests passing:
- `test/jido_ai/chain_of_thought/machine_test.exs` - 18 tests
- `test/jido_ai/strategies/chain_of_thought_test.exs` - 31 tests

## Implementation Details

**Files created:**
- `lib/jido_ai/chain_of_thought/machine.ex` - Pure Fsmx state machine
- `lib/jido_ai/strategies/chain_of_thought.ex` - Strategy adapter
- `test/jido_ai/chain_of_thought/machine_test.exs` - Machine tests
- `test/jido_ai/strategies/chain_of_thought_test.exs` - Strategy tests

**Key features:**
- Step-by-step reasoning with step extraction
- Conclusion detection
- Streaming support
- Telemetry events
- Helper functions: `get_steps/1`, `get_conclusion/1`, `get_raw_response/1`

**Git commits:**
- `00e18704` - feat(cot): add Chain-of-Thought strategy for step-by-step reasoning
- `ef37ced5` - Feature/cot (#94) (PR merge)
