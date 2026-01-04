# Phase 4B.2 TRM Strategy - Feature Plan

**Branch**: `feature/phase4b-trm-strategy`
**Started**: 2026-01-04
**Status**: COMPLETED

## Problem Statement

Phase 4B.1 implemented the TRM (Tiny-Recursive-Model) Machine - a pure state machine for recursive reasoning. Now we need to create the TRM Strategy, which acts as a thin adapter that:
- Routes signals to strategy commands
- Manages configuration
- Converts machine directives to SDK-specific directive structs
- Provides public API for accessing TRM state

## Solution Overview

Follow the established Strategy + Machine + Directives pattern used by GoT, ToT, and other strategies:

```
Strategy (thin adapter)     → Signal routing, config, directive lifting
    ↓
Machine (pure Fsmx FSM)     → State transitions, returns directives (no side effects)
    ↓
Directives                  → ReqLLMStream (executed by runtime)
```

## Implementation Plan

### 4B.2.1 Strategy Module Setup
**Status**: COMPLETED

- [x] Create `Jido.AI.Strategies.TRM` module at `lib/jido_ai/strategies/trm.ex`
- [x] Add `use Jido.Agent.Strategy`
- [x] Define `@type config` with model, max_supervision_steps, act_threshold, etc.
- [x] Define `@default_model "anthropic:claude-haiku-4-5"`

### 4B.2.2 Action Atoms
**Status**: COMPLETED

- [x] Define `@start :trm_start`, `@llm_result :trm_llm_result`, `@llm_partial :trm_llm_partial`
- [x] Implement accessor functions: `start_action/0`, `llm_result_action/0`, `llm_partial_action/0`
- [x] Define `@action_specs` map with Zoi schemas

### 4B.2.3 Signal Routing
**Status**: COMPLETED

- [x] Implement `signal_routes/1` callback with routes for `trm.reason`, `reqllm.result`, `reqllm.partial`

### 4B.2.4 Strategy Callbacks
**Status**: COMPLETED

- [x] Implement `action_spec/1`
- [x] Implement `init/2` building config and creating machine
- [x] Implement `cmd/3` processing instructions through machine
- [x] Implement `snapshot/2` returning `%Snapshot{}`
- [x] Implement `build_config/2`

### 4B.2.5 Directive Lifting
**Status**: COMPLETED

- [x] Implement `lift_directives/2` with pattern matching on directive types
- [x] Handle `{:reason, id, context}` → `Directive.ReqLLMStream`
- [x] Handle `{:supervise, id, context}` → `Directive.ReqLLMStream`
- [x] Handle `{:improve, id, context}` → `Directive.ReqLLMStream`
- [x] Implement `to_machine_msg/2` converting action/params to machine messages

### 4B.2.6 Public API
**Status**: COMPLETED

- [x] Implement `get_answer_history/1`
- [x] Implement `get_current_answer/1`
- [x] Implement `get_confidence/1`
- [x] Implement `get_supervision_step/1`
- [x] Implement `get_best_answer/1`
- [x] Implement `get_best_score/1`

### 4B.2.7 Unit Tests
**Status**: COMPLETED

- [x] Test `init/2` creates machine and sets config
- [x] Test `signal_routes/1` returns correct routing
- [x] Test `cmd/3` with start instruction creates reasoning directive
- [x] Test `cmd/3` with llm_result processes through phases
- [x] Test `snapshot/2` returns correct status
- [x] Test `lift_directives/2` creates correct directive types
- [x] Test public API functions

## TRM Machine Directives

The TRM Machine emits these directives:
- `{:reason, call_id, context}` - Request reasoning LLM call
- `{:supervise, call_id, context}` - Request supervision LLM call
- `{:improve, call_id, context}` - Request improvement LLM call

Each needs to be lifted to a `Directive.ReqLLMStream` with appropriate prompts.

## Test Results

- TRM Machine tests: 43 tests, 0 failures
- TRM Strategy tests: 43 tests, 0 failures
- Full test suite: 406 tests, 0 failures

## Files Created/Modified

1. `lib/jido_ai/strategies/trm.ex` - New TRM Strategy module (568 lines)
2. `test/jido_ai/strategies/trm_test.exs` - Comprehensive tests (43 tests)

## Notes

- Follow the GoT strategy pattern closely
- Each TRM phase needs its own system prompt for reasoning, supervision, and improvement
- The strategy should track the recursive improvement cycle through machine state
- Default prompts are provided for all phases (reasoning, supervision, improvement)
- Custom prompts can be passed via strategy options
