# Phase 4.2 Chain-of-Thought Strategy

**Branch**: `feature/phase4-chain-of-thought`
**Status**: Complete
**Created**: 2026-01-04

## Problem Statement

The project needs a Chain-of-Thought (CoT) strategy for step-by-step reasoning. CoT prompting encourages LLMs to break down complex problems into intermediate steps before providing a final answer, leading to better reasoning on multi-step problems.

## Solution Overview

Implement a CoT strategy following the existing ReAct pattern:
1. Pure Fsmx state machine for state transitions
2. Strategy adapter that emits directives (no direct LLM calls)
3. Step extraction to parse and store reasoning steps
4. Signal routing for LLM results

### Design Decisions
- Follow existing ReAct architecture: Machine + Strategy pattern
- Single LLM call with CoT system prompt (vs. multi-turn)
- Extract steps from response for transparency
- Simpler than ReAct (no tool calls, just reasoning)

---

## Implementation Plan

### Phase 1: Machine Implementation

- [x] 1.1 Create `lib/jido_ai/chain_of_thought/machine.ex` with Fsmx
- [x] 1.2 Define states: `:idle`, `:reasoning`, `:completed`, `:error`
- [x] 1.3 Define message types: `{:start, prompt, call_id}`, `{:llm_result, ...}`, `{:llm_partial, ...}`
- [x] 1.4 Implement `update/3` for message handling
- [x] 1.5 Add usage tracking and telemetry (like ReAct)

### Phase 2: Strategy Implementation

- [x] 2.1 Create `lib/jido_ai/strategies/chain_of_thought.ex`
- [x] 2.2 Implement `init/2` to create machine and config
- [x] 2.3 Implement `cmd/3` to process instructions
- [x] 2.4 Implement `signal_routes/1` for signal routing
- [x] 2.5 Implement `snapshot/2` for state inspection
- [x] 2.6 Implement `lift_directives/2` for directive conversion
- [x] 2.7 Build CoT system prompt

### Phase 3: Step Extraction

- [x] 3.1 Parse numbered step format ("Step 1:", "1.", etc.)
- [x] 3.2 Parse bullet point format
- [x] 3.3 Detect final conclusion/answer
- [x] 3.4 Store extracted steps in machine state

### Phase 4: Testing

- [x] 4.1 Machine unit tests (state transitions, directives)
- [x] 4.2 Strategy tests (signal routing, config)
- [x] 4.3 Step extraction tests (various formats)
- [x] 4.4 Integration tests

---

## Success Criteria

1. [x] Machine follows Fsmx pattern with pure state transitions
2. [x] Strategy emits ReqLLMStream directives (no direct calls)
3. [x] Step extraction parses common formats
4. [x] All tests pass (49 new tests)
5. [x] Usage and telemetry integration

## Current Status

**What Works**: Full implementation complete
**What's Next**: Commit and merge to v2
**How to Run**: `mix test test/jido_ai/chain_of_thought/ test/jido_ai/strategies/chain_of_thought_test.exs`

---

## Changes Made

### New Files
- `lib/jido_ai/chain_of_thought/machine.ex` - Pure state machine for CoT reasoning
- `lib/jido_ai/strategies/chain_of_thought.ex` - Strategy adapter
- `test/jido_ai/chain_of_thought/machine_test.exs` - 27 machine tests
- `test/jido_ai/strategies/chain_of_thought_test.exs` - 22 strategy tests

### Implementation Details

#### Machine (`lib/jido_ai/chain_of_thought/machine.ex`)
- States: `idle` -> `reasoning` -> `completed` | `error`
- Message types:
  - `{:start, prompt, call_id}` - Start CoT reasoning
  - `{:llm_result, call_id, result}` - Handle LLM response
  - `{:llm_partial, call_id, delta, chunk_type}` - Handle streaming chunks
- Directives: `{:call_llm_stream, id, context}`
- Features:
  - Usage metadata tracking and accumulation
  - Telemetry events (`:jido, :ai, :cot`)
  - Step extraction from numbered and bullet formats
  - Conclusion detection (Answer:, Conclusion:, Therefore:, etc.)
  - Streaming text accumulation

#### Strategy (`lib/jido_ai/strategies/chain_of_thought.ex`)
- Implements `Jido.Agent.Strategy` behavior
- Signal routes: `cot.query` -> `:cot_start`, `reqllm.result` -> `:cot_llm_result`
- Actions: `:cot_start`, `:cot_llm_result`, `:cot_llm_partial`
- Config options:
  - `:model` - Model alias or full spec (default: `anthropic:claude-haiku-4-5`)
  - `:system_prompt` - Custom system prompt for CoT reasoning
- Helper functions: `get_steps/1`, `get_conclusion/1`, `get_raw_response/1`

### Test Coverage
- Machine creation and initialization
- State transitions (idle -> reasoning -> completed/error)
- Step extraction (numbered: "Step 1:", "1.", bullet: "- ", "* ")
- Conclusion detection (multiple markers)
- Usage accumulation
- Streaming partial handling
- to_map/from_map serialization
- Strategy init, cmd, snapshot
- Signal routing configuration
