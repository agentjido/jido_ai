# Phase 4.4 Graph-of-Thoughts Strategy

**Branch**: `feature/phase4-graph-of-thoughts`
**Status**: Complete
**Created**: 2026-01-04

## Problem Statement

The project needs a Graph-of-Thoughts (GoT) strategy for graph-based reasoning. Unlike Tree-of-Thoughts which maintains a strict tree structure, GoT allows nodes to have multiple parents and supports merging/aggregation of thoughts. This enables more complex reasoning patterns like combining insights from different branches.

## Solution Overview

Implement a GoT strategy following the existing ReAct/CoT/ToT architecture:
1. Pure Fsmx state machine for state transitions
2. Strategy adapter that emits directives (no direct LLM calls)
3. Graph structure with nodes and edges (vs tree structure)
4. Graph operations: add_node, add_edge, merge_nodes, refine_node
5. Aggregation strategies: voting, weighted average, LLM synthesis
6. Signal routing for LLM results

### Design Decisions
- Follow existing Machine + Strategy pattern from ReAct/CoT/ToT
- Graph stored as `%{nodes: %{id => node}, edges: [{from, to, type}]}`
- Support directed edges with relationship types
- Aggregation produces new nodes from multiple source nodes
- Support cycle detection to prevent infinite loops

---

## Implementation Plan

### Phase 1: Machine Implementation

- [x] 1.1 Create `lib/jido_ai/graph_of_thoughts/machine.ex` with Fsmx
- [x] 1.2 Define states: `:idle`, `:generating`, `:connecting`, `:aggregating`, `:completed`, `:error`
- [x] 1.3 Define graph structure `%{nodes: %{}, edges: []}`
- [x] 1.4 Implement `update/3` for message handling
- [x] 1.5 Add usage tracking and telemetry

### Phase 2: Graph Operations

- [x] 2.1 `add_node/2` - Add thought node to graph
- [x] 2.2 `add_edge/3` - Connect two nodes with relationship type
- [x] 2.3 `get_ancestors/2` - Get all ancestor nodes
- [x] 2.4 `get_descendants/2` - Get all descendant nodes
- [x] 2.5 `detect_cycles/1` - Detect cycles in graph
- [x] 2.6 `find_leaves/1` - Find all leaf nodes
- [x] 2.7 `trace_path/2` - Trace path from root to node

### Phase 3: Message Types

- [x] 3.1 `{:start, prompt, call_id}` - Start GoT reasoning
- [x] 3.2 `{:thought_generated, call_id, content}` - Single thought generated
- [x] 3.3 `{:connections_found, call_id, connections}` - Related nodes found
- [x] 3.4 `{:aggregation_complete, call_id, result}` - Aggregation done
- [x] 3.5 `{:llm_result, call_id, result}` - Generic LLM response
- [x] 3.6 `{:llm_partial, call_id, delta, chunk_type}` - Streaming partial

### Phase 4: Directive Types

- [x] 4.1 `{:generate_thought, id, context}` - Generate single thought
- [x] 4.2 `{:find_connections, id, node_id, graph_context}` - Find related nodes
- [x] 4.3 `{:aggregate, id, node_ids, strategy}` - Aggregate multiple nodes

### Phase 5: Strategy Implementation

- [x] 5.1 Create `lib/jido_ai/strategies/graph_of_thoughts.ex`
- [x] 5.2 Implement `init/2` to create machine and config
- [x] 5.3 Implement `cmd/3` to process instructions
- [x] 5.4 Implement `signal_routes/1` for signal routing
- [x] 5.5 Implement `snapshot/2` for state inspection
- [x] 5.6 Implement `lift_directives/2` for directive conversion
- [x] 5.7 Configure aggregation_strategy and max_nodes in opts

### Phase 6: Aggregation Strategies

- [x] 6.1 LLM-based synthesis (request via directive)

### Phase 7: Solution Extraction

- [x] 7.1 Find terminal nodes (nodes with no outgoing edges)
- [x] 7.2 Trace paths from root to terminal nodes
- [x] 7.3 Select best path by scores

### Phase 8: Testing

- [x] 8.1 Machine unit tests (state transitions, directives)
- [x] 8.2 Graph operations tests (add node, add edge)
- [x] 8.3 Cycle detection tests
- [x] 8.4 Strategy tests (signal routing, config)
- [x] 8.5 Helper function tests

---

## Success Criteria

1. [x] Machine follows Fsmx pattern with pure state transitions
2. [x] Strategy emits directives (no direct LLM calls)
3. [x] Graph structure correctly maintains nodes and edges
4. [x] All graph operations work correctly
5. [x] Cycle detection prevents infinite loops
6. [x] All tests pass (63 GoT tests, 797 total)
7. [x] Usage and telemetry integration

## Current Status

**What Works**: Full implementation complete
**What's Next**: Commit and merge to v2
**How to Run**: `mix test test/jido_ai/graph_of_thoughts/`

---

## Changes Made

### New Files
- `lib/jido_ai/graph_of_thoughts/machine.ex` - Pure Fsmx state machine (~900 lines)
- `lib/jido_ai/strategies/graph_of_thoughts.ex` - Strategy adapter (~480 lines)
- `test/jido_ai/graph_of_thoughts/machine_test.exs` - Machine tests (41 tests)
- `test/jido_ai/strategies/graph_of_thoughts_test.exs` - Strategy tests (22 tests)

### Key Implementation Details

**State Machine States:**
- `idle` → `generating` → `connecting`/`aggregating` → `generating` (loop)
- `generating`/`connecting`/`aggregating` → `completed` (when conditions met)
- Any state → `error` (on failure)

**Edge Types:**
- `:generates` - Parent thought generates child thought
- `:refines` - Refinement of existing thought
- `:aggregates` - Multiple thoughts aggregated into one
- `:connects` - Conceptual connection between thoughts

**Configuration Options:**
- `:model` - LLM model identifier (default: "anthropic:claude-haiku-4-5")
- `:max_nodes` - Maximum number of nodes (default: 20)
- `:max_depth` - Maximum graph depth (default: 5)
- `:aggregation_strategy` - `:voting`, `:weighted`, or `:synthesis` (default: :synthesis)
- `:generation_prompt` - Custom thought generation prompt
- `:connection_prompt` - Custom connection finding prompt
- `:aggregation_prompt` - Custom aggregation prompt
