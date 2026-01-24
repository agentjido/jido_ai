# Phase 4.3 Tree-of-Thoughts Strategy - Summary

**Branch**: `feature/phase4-tree-of-thoughts`
**Completed**: 2026-01-04

## Overview

Implemented Tree-of-Thoughts (ToT) strategy for branching exploration of solution spaces. ToT extends Chain-of-Thought by generating multiple candidate thoughts at each step, evaluating them, and exploring the most promising branches.

## Files Created

| File | Purpose | Tests |
|------|---------|-------|
| `lib/jido_ai/tree_of_thoughts/machine.ex` | Pure Fsmx state machine | 47 |
| `lib/jido_ai/strategies/tree_of_thoughts.ex` | Strategy adapter | 26 |
| `test/jido_ai/tree_of_thoughts/machine_test.exs` | Machine tests | - |
| `test/jido_ai/strategies/tree_of_thoughts_test.exs` | Strategy tests | - |

**Total**: 73 new tests, 734 tests passing overall

## Architecture

```
TreeOfThoughts Strategy (adapter)
         │
         ├── init/2 → creates Machine + config
         ├── cmd/3 → translates instructions → machine messages
         └── snapshot/2 → reports status
                │
                ▼
TreeOfThoughts Machine (pure state machine)
         │
         ├── States: idle → generating → evaluating → expanding → completed
         ├── Tree structure: nodes map with parent/child relationships
         └── Emits directives: {:generate_thoughts, ...}, {:evaluate_thoughts, ...}
```

## Key Features

1. **Pure State Machine**: All state transitions through Fsmx, no side effects
2. **Tree Structure**: Nodes with id, parent_id, content, score, children, depth
3. **Three Traversal Strategies**:
   - BFS (breadth-first): Explore level by level
   - DFS (depth-first): Explore deep before wide
   - Best-first (default): Always expand highest-scoring node
4. **Streaming Support**: Handles partial LLM responses via `llm_partial` messages
5. **Usage Tracking**: Accumulates token usage across LLM calls
6. **Telemetry**: Events under `[:jido, :ai, :tot]` namespace

## Configuration

```elixir
use Jido.Agent,
  name: "my_tot_agent",
  strategy: {
    Jido.AI.Strategies.TreeOfThoughts,
    model: "anthropic:claude-sonnet-4-20250514",
    branching_factor: 3,      # thoughts per node
    max_depth: 4,             # max tree depth
    traversal_strategy: :best_first
  }
```

## Signal Routes

| Signal | Action |
|--------|--------|
| `tot.query` | `:tot_start` |
| `reqllm.result` | `:tot_llm_result` |
| `reqllm.partial` | `:tot_llm_partial` |

## Issues Fixed During Implementation

1. **Type name conflict**: Renamed `@type node` to `@type thought_node` (built-in conflict)
2. **Usage accumulation error**: Fixed calling `accumulate_usage/2` with unwrapped tuple
3. **Credo refactoring**: Extracted helpers to reduce complexity in `from_map`, `find_best_leaf`, and `expand_next_node`

## Usage Example

```elixir
# Start ToT exploration
instruction = %Jido.Instruction{
  action: :tot_start,
  params: %{prompt: "Solve this puzzle..."}
}

{agent, directives} = TreeOfThoughts.cmd(agent, [instruction], %{})

# directives contains ReqLLMStream directive to call LLM
# After receiving LLM result, send it back:
result_instruction = %Jido.Instruction{
  action: :tot_llm_result,
  params: %{call_id: call_id, result: {:ok, %{text: "..."}}}
}
```
