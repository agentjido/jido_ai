# Phase 4B.6 Adaptive Integration - Feature Plan

**Branch**: `feature/phase4b-adaptive-integration`
**Started**: 2026-01-04
**Status**: COMPLETED

## Problem Statement

The TRM strategy has been implemented but is not yet integrated into the Adaptive strategy for automatic selection. The Adaptive strategy needs to:
- Include TRM in its available strategies
- Detect puzzle-solving and iterative reasoning tasks
- Route these tasks to TRM automatically

## Solution Overview

Update `Jido.AI.Strategies.Adaptive` to:
1. Add TRM to the strategy module mapping and types
2. Add puzzle/iterative reasoning keyword detection
3. Add task type routing for iterative reasoning tasks to TRM
4. Add action mapping functions for TRM

## Implementation Plan

### 4B.6.1 Strategy Registration
**Status**: COMPLETED

- [x] Update `@strategy_modules` map to include `:trm => Jido.AI.Strategies.TRM`
- [x] Update `@type strategy_type` to include `:trm`
- [x] Update default `available_strategies` to include `:trm`
- [x] Add alias for TRM strategy module

### 4B.6.2 Puzzle/Reasoning Keyword Detection
**Status**: COMPLETED

- [x] Define `@puzzle_keywords ~w(puzzle iterate improve refine recursive riddle)`
- [x] Implement `has_puzzle_keywords?/1` helper
- [x] Add `:iterative_reasoning` to `detect_task_type/1` result types

### 4B.6.3 TRM-Specific Task Type Routing
**Status**: COMPLETED

- [x] Update `select_by_task_type/2` to handle `:iterative_reasoning` → `:trm`
- [x] Update `detect_task_type/1` to check for puzzle keywords first
- [x] Add action mapping functions: `start_action_for(:trm)`, `llm_result_action_for(:trm)`, `llm_partial_action_for(:trm)`
- [x] Add `map_params_for_strategy/3` to map `:prompt` to `:question` for TRM

### 4B.6.4 Unit Tests
**Status**: COMPLETED

- [x] Test `:trm` is in `@strategy_modules`
- [x] Test `has_puzzle_keywords?/1` detects puzzle-solving prompts
- [x] Test `detect_task_type/1` returns `:iterative_reasoning` for puzzle prompts
- [x] Test `select_by_task_type(:iterative_reasoning, _)` returns `:trm`
- [x] Test Adaptive delegates to TRM for iterative reasoning tasks
- [x] Test action mapping returns correct TRM actions
- [x] Test fallback to ToT when TRM not available
- [x] Test override to TRM works

## Test Results

- Adaptive strategy tests: 51 tests, 0 failures
- Full test suite: 1093 tests, 0 failures

## Files Modified

| File | Change |
|------|--------|
| `lib/jido_ai/strategies/adaptive.ex` | Added TRM integration (~30 lines) |
| `test/jido_ai/strategies/adaptive_test.exs` | Added TRM tests (~60 lines) |

## Notes

- TRM uses `:trm_start`, `:trm_llm_result`, `:trm_llm_partial` action atoms
- Puzzle keywords: puzzle, iterate, improve, refine, recursive, riddle
- Removed "solve" and "step-by-step" from keywords as they caused false positives
- TRM expects `:question` parameter instead of `:prompt`, handled by `map_params_for_strategy/3`
- TRM is best for tasks requiring iterative improvement through reasoning cycles
- Falls back to ToT for iterative reasoning when TRM is not available
