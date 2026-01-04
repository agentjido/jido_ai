# Phase 4.4 Graph-of-Thoughts Strategy - Summary

**Branch**: `feature/phase4-graph-of-thoughts`
**Completed**: 2026-01-04

## Overview

Implemented Graph-of-Thoughts (GoT) strategy for graph-based reasoning. GoT extends Tree-of-Thoughts by allowing nodes to have multiple parents and supporting merging/aggregation of thoughts. This enables more complex reasoning patterns like combining insights from different branches.

## Files Created

| File | Purpose | Tests |
|------|---------|-------|
| `lib/jido_ai/graph_of_thoughts/machine.ex` | Pure Fsmx state machine | 41 |
| `lib/jido_ai/strategies/graph_of_thoughts.ex` | Strategy adapter | 22 |
| `test/jido_ai/graph_of_thoughts/machine_test.exs` | Machine tests | - |
| `test/jido_ai/strategies/graph_of_thoughts_test.exs` | Strategy tests | - |

**Total**: 63 new tests, 797 tests passing overall

## Architecture

```
GraphOfThoughts Strategy (adapter)
         │
         ├── init/2 → creates Machine + config
         ├── cmd/3 → translates instructions → machine messages
         └── snapshot/2 → reports status
                │
                ▼
GraphOfThoughts Machine (pure state machine)
         │
         ├── States: idle → generating → connecting → aggregating → completed
         ├── Graph structure: nodes map + edges list
         └── Emits directives: {:generate_thought, ...}, {:find_connections, ...}, {:aggregate, ...}
```

## Key Features

1. **Pure State Machine**: All state transitions through Fsmx, no side effects
2. **Graph Structure**: Nodes with id, content, score, depth, metadata; Edges with from, to, type
3. **Edge Types**:
   - `:generates` - Parent thought generates child thought
   - `:refines` - Refinement of existing thought
   - `:aggregates` - Multiple thoughts aggregated into one
   - `:connects` - Conceptual connection between thoughts
4. **Graph Operations**:
   - `add_node/2`, `add_edge/4` - Build graph
   - `get_ancestors/2`, `get_descendants/2` - Navigate graph
   - `has_cycle?/1` - Detect cycles
   - `find_leaves/1`, `find_best_leaf/1` - Find terminal nodes
   - `trace_path/2` - Path from root to node
5. **Streaming Support**: Handles partial LLM responses via `llm_partial` messages
6. **Usage Tracking**: Accumulates token usage across LLM calls
7. **Telemetry**: Events under `[:jido, :ai, :got]` namespace

## Configuration

```elixir
use Jido.Agent,
  name: "my_got_agent",
  strategy: {
    Jido.AI.Strategies.GraphOfThoughts,
    model: "anthropic:claude-sonnet-4-20250514",
    max_nodes: 20,           # maximum nodes in graph
    max_depth: 5,            # maximum graph depth
    aggregation_strategy: :synthesis
  }
```

## Signal Routes

| Signal | Action |
|--------|--------|
| `got.query` | `:got_start` |
| `reqllm.result` | `:got_llm_result` |
| `reqllm.partial` | `:got_llm_partial` |

## Differences from Tree-of-Thoughts

| Feature | ToT | GoT |
|---------|-----|-----|
| Structure | Tree (single parent) | Graph (multiple parents) |
| Traversal | BFS/DFS/Best-first | Connection-based exploration |
| Operations | Expand, evaluate | Generate, connect, aggregate |
| Solution | Best leaf path | Aggregated synthesis |

## Usage Example

```elixir
# Start GoT exploration
instruction = %{
  action: :got_start,
  params: %{prompt: "Analyze this complex problem..."}
}

{agent, directives} = GraphOfThoughts.cmd(agent, [instruction], %{})

# directives contains ReqLLMStream directive to call LLM
# After receiving LLM result, send it back:
result_instruction = %{
  action: :got_llm_result,
  params: %{call_id: call_id, result: {:ok, %{text: "..."}}}
}
```
