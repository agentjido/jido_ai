# Phase 4.5 Adaptive Strategy - Summary

**Branch**: `feature/phase4-adaptive-strategy`
**Completed**: 2026-01-04

## Overview

Implemented Adaptive Strategy that automatically selects the most appropriate reasoning strategy (CoT, ReAct, ToT, GoT) based on task characteristics. The strategy analyzes prompt complexity and task type to choose the best approach without requiring manual configuration.

## Files Created

| File | Purpose | Tests |
|------|---------|-------|
| `lib/jido_ai/strategies/adaptive.ex` | Adaptive Strategy implementation | 45 |
| `test/jido_ai/strategies/adaptive_test.exs` | Strategy tests | - |

**Total**: 45 new tests, 842 tests passing overall

## Architecture

```
Adaptive Strategy
       │
       ├── init/2 → sets up config, available strategies
       ├── cmd/3 → analyzes prompt, selects strategy, delegates
       ├── snapshot/2 → delegates to selected strategy
       └── signal_routes/1 → base routes for adaptive actions
              │
              ▼
       Strategy Selection
              │
              ├── analyze_prompt/2 → calculates complexity score
              ├── detect_task_type/1 → identifies task category
              └── select_strategy/4 → maps analysis to strategy
                     │
                     ▼
       Delegated Strategies
              │
              ├── ChainOfThought (CoT) - simple tasks
              ├── ReAct - tool-use tasks
              ├── TreeOfThoughts (ToT) - complex exploration
              └── GraphOfThoughts (GoT) - graph-based reasoning
```

## Key Features

1. **Heuristic-Based Selection**: No LLM call required for strategy selection
2. **Task Type Detection**: Analyzes keywords to categorize tasks (in priority order)
   - `:synthesis` - Keywords like "synthesize", "combine", "merge", "perspectives" → GoT
   - `:tool_use` - Keywords like "search", "find", "calculate" → ReAct
   - `:exploration` - Keywords like "analyze", "explore", "compare" → ToT
   - `:simple_query` - Keywords like "what", "who", "define" → CoT
3. **Complexity Scoring**: Scores prompts 0.0-1.0 based on:
   - Prompt length
   - Sentence structure
   - Complex reasoning keywords
   - Questions and constraints
4. **Threshold-Based Selection** (when no task type match):
   - Simple (< 0.3) → CoT
   - Moderate (0.3-0.7) → ReAct
   - Complex (> 0.7) → ToT
5. **Re-evaluation When Done**: Strategy is re-evaluated when previous reasoning completes
6. **Manual Override**: Force specific strategy via `:strategy` option
7. **Configurable**: Available strategies, thresholds, default strategy

## Configuration

```elixir
use Jido.Agent,
  name: "my_adaptive_agent",
  strategy: {
    Jido.AI.Strategies.Adaptive,
    model: "anthropic:claude-sonnet-4-20250514",
    default_strategy: :react,
    available_strategies: [:cot, :react, :tot, :got],
    complexity_thresholds: %{simple: 0.3, complex: 0.7}
  }
```

## Signal Routes

| Signal | Action |
|--------|--------|
| `adaptive.query` | `:adaptive_start` |
| `reqllm.result` | `:adaptive_llm_result` |
| `reqllm.partial` | `:adaptive_llm_partial` |

## Public API

```elixir
# Analyze a prompt without executing
{strategy, score, task_type} = Adaptive.analyze_prompt("What is AI?")
# => {:cot, 0.089, :simple_query}

# Get the selected strategy for an agent
Adaptive.get_selected_strategy(agent)
# => :cot

# Get the complexity score for an agent
Adaptive.get_complexity_score(agent)
# => 0.089
```

## Usage Example

```elixir
# Start adaptive reasoning
instruction = %{
  action: :adaptive_start,
  params: %{prompt: "What is the capital of France?"}
}

{agent, directives} = Adaptive.cmd(agent, [instruction], %{})
# Strategy selected: :cot (simple query with low complexity)

# Complex prompt selects ToT
complex_instruction = %{
  action: :adaptive_start,
  params: %{prompt: "Analyze multiple alternatives and evaluate trade-offs..."}
}

{agent, directives} = Adaptive.cmd(agent, [complex_instruction], %{})
# Strategy selected: :tot (exploration keywords + high complexity)

# Synthesis prompt selects GoT
synthesis_instruction = %{
  action: :adaptive_start,
  params: %{prompt: "Synthesize these viewpoints and combine the perspectives..."}
}

{agent, directives} = Adaptive.cmd(agent, [synthesis_instruction], %{})
# Strategy selected: :got (synthesis keywords → graph-based reasoning)
```
