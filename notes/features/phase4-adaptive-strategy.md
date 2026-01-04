# Phase 4.5 Adaptive Strategy

**Branch**: `feature/phase4-adaptive-strategy`
**Status**: Complete
**Created**: 2026-01-04

## Problem Statement

The project needs an Adaptive Strategy that automatically selects the most appropriate reasoning strategy (CoT, ReAct, ToT, GoT) based on task characteristics. This allows agents to dynamically adapt their reasoning approach without manual configuration for each task type.

## Solution Overview

Implement an Adaptive Strategy that:
1. Analyzes task complexity and type from the prompt
2. Selects the appropriate strategy (CoT for simple, ReAct for tool-use, ToT/GoT for complex)
3. Delegates all callbacks to the selected strategy
4. Supports manual override via configuration

### Design Decisions
- Follow existing Strategy pattern - Adaptive wraps other strategies
- Task analysis is heuristic-based (no LLM call required for selection)
- Strategy is selected on first command and persisted for the session
- Support manual override via `:strategy` option
- Configurable available strategies and selection thresholds

---

## Implementation Plan

### Phase 1: Strategy Implementation

- [x] 1.1 Create `lib/jido_ai/strategies/adaptive.ex`
- [x] 1.2 Use `Jido.Agent.Strategy` macro
- [x] 1.3 Configure available strategies in opts
- [x] 1.4 Store selected strategy in agent state

### Phase 2: Task Analysis

- [x] 2.1 Analyze prompt length and complexity
- [x] 2.2 Detect keywords suggesting task type:
  - Tool-use keywords → ReAct
  - Multi-step/complex keywords → ToT
  - Simple question keywords → CoT
- [x] 2.3 Calculate complexity score based on:
  - Prompt length
  - Question complexity
  - Number of constraints/requirements

### Phase 3: Strategy Selection

- [x] 3.1 Map complexity to strategy:
  - Simple (score < 0.3) → CoT
  - Moderate (0.3-0.7) → ReAct
  - Complex (> 0.7) → ToT
- [x] 3.2 Override based on task type detection:
  - Tool-use detected → ReAct
  - Exploration/search detected → ToT
- [x] 3.3 Support manual override via `:strategy` option
- [x] 3.4 Fallback to default strategy on error

### Phase 4: Strategy Delegation

- [x] 4.1 Initialize selected strategy on first command
- [x] 4.2 Delegate `cmd/3` to selected strategy
- [x] 4.3 Delegate `signal_routes/1` to selected strategy
- [x] 4.4 Delegate `snapshot/2` to selected strategy
- [x] 4.5 Delegate `action_spec/1` to selected strategy

### Phase 5: Testing

- [x] 5.1 Test task analysis classification
- [x] 5.2 Test strategy selection for different complexities
- [x] 5.3 Test delegation to selected strategy
- [x] 5.4 Test manual override
- [x] 5.5 Test fallback on selection failure

---

## Success Criteria

1. [x] Strategy follows Jido.Agent.Strategy pattern
2. [x] Task analysis correctly classifies complexity
3. [x] Strategy selection maps complexity to appropriate strategy
4. [x] Delegation works correctly for all callbacks
5. [x] Manual override works
6. [x] All tests pass (40 Adaptive tests, 837 total)
7. [x] Fallback handles errors gracefully

## Current Status

**What Works**: Full implementation complete
**What's Next**: Commit and merge to v2
**How to Run**: `mix test test/jido_ai/strategies/adaptive_test.exs`

---

## Changes Made

### New Files
- `lib/jido_ai/strategies/adaptive.ex` - Adaptive Strategy (~505 lines)
- `test/jido_ai/strategies/adaptive_test.exs` - Strategy tests (40 tests)

### Key Implementation Details

**Strategy Selection Algorithm:**
1. Check for manual override via `:strategy` option
2. Analyze prompt for task type keywords
3. Calculate complexity score from prompt characteristics
4. Select strategy based on task type or complexity score
5. Fall back to default strategy if needed

**Task Type Detection:**
- `:tool_use` - Keywords like "search", "find", "calculate", "execute"
- `:exploration` - Keywords like "analyze", "explore", "compare", "evaluate"
- `:simple_query` - Keywords like "what", "who", "when", "where", "define"
- `:general` - No specific keyword match

**Complexity Score Factors:**
- Prompt length (normalized)
- Sentence structure complexity
- Presence of complex reasoning keywords
- Number of questions and constraints

**Configuration Options:**
- `:model` - LLM model identifier (default: "anthropic:claude-haiku-4-5")
- `:default_strategy` - Default strategy if analysis is inconclusive (default: :react)
- `:strategy` - Manual override to force a specific strategy
- `:available_strategies` - List of available strategies (default: [:cot, :react, :tot])
- `:complexity_thresholds` - Map of thresholds for strategy selection
