# Phase 4.3 Tree-of-Thoughts Strategy

**Branch**: `feature/phase4-tree-of-thoughts`
**Status**: Complete
**Created**: 2026-01-04

## Problem Statement

The project needs a Tree-of-Thoughts (ToT) strategy for branching exploration of solution spaces. ToT extends Chain-of-Thought by generating multiple candidate thoughts at each step, evaluating them, and exploring the most promising branches. This approach is effective for problems requiring search (puzzles, planning, creative writing).

## Solution Overview

Implement a ToT strategy following the existing ReAct/CoT architecture:
1. Pure Fsmx state machine for state transitions
2. Strategy adapter that emits directives (no direct LLM calls)
3. Tree structure with nodes containing thoughts, scores, and parent/child relationships
4. Multiple traversal strategies (BFS, DFS, best-first)
5. Signal routing for LLM results

### Design Decisions
- Follow existing Machine + Strategy pattern from ReAct/CoT
- Tree nodes stored in machine state as a map keyed by ID
- Evaluation scores determine which branches to expand
- Support configurable branching factor and max depth
- Multiple traversal strategies via configuration

---

## Implementation Plan

### Phase 1: Machine Implementation

- [x] 1.1 Create `lib/jido_ai/tree_of_thoughts/machine.ex` with Fsmx
- [x] 1.2 Define states: `:idle`, `:generating`, `:evaluating`, `:expanding`, `:completed`, `:error`
- [x] 1.3 Define tree node structure `%{id, parent_id, content, score, children, depth}`
- [x] 1.4 Implement `update/3` for message handling
- [x] 1.5 Add usage tracking and telemetry (like CoT)

### Phase 2: Message Types

- [x] 2.1 `{:start, prompt, call_id}` - Start ToT exploration
- [x] 2.2 `{:thoughts_generated, call_id, thoughts}` - Generated candidate thoughts
- [x] 2.3 `{:thoughts_evaluated, call_id, scores}` - Evaluation scores
- [x] 2.4 `{:llm_result, call_id, result}` - Generic LLM response
- [x] 2.5 `{:llm_partial, call_id, delta, chunk_type}` - Streaming partial

### Phase 3: Directive Types

- [x] 3.1 `{:generate_thoughts, id, context, count}` - Generate N candidate thoughts
- [x] 3.2 `{:evaluate_thoughts, id, thoughts}` - Evaluate thought candidates
- [x] 3.3 `{:call_llm_stream, id, context}` - Standard LLM call

### Phase 4: Tree Traversal

- [x] 4.1 Implement BFS traversal (breadth-first)
- [x] 4.2 Implement DFS traversal (depth-first)
- [x] 4.3 Implement best-first traversal (by score)
- [x] 4.4 Configure traversal strategy via opts

### Phase 5: Strategy Implementation

- [x] 5.1 Create `lib/jido_ai/strategies/tree_of_thoughts.ex`
- [x] 5.2 Implement `init/2` to create machine and config
- [x] 5.3 Implement `cmd/3` to process instructions
- [x] 5.4 Implement `signal_routes/1` for signal routing
- [x] 5.5 Implement `snapshot/2` for state inspection
- [x] 5.6 Implement `lift_directives/2` for directive conversion
- [x] 5.7 Configure branching_factor and max_depth in opts

### Phase 6: Solution Extraction

- [x] 6.1 Find best leaf node by score
- [x] 6.2 Trace path from root to solution
- [x] 6.3 Format solution as final answer

### Phase 7: Testing

- [x] 7.1 Machine unit tests (state transitions, directives)
- [x] 7.2 Tree construction tests (add node, get children)
- [x] 7.3 Traversal tests (BFS, DFS, best-first)
- [x] 7.4 Strategy tests (signal routing, config)
- [x] 7.5 Solution extraction tests

---

## Success Criteria

1. [x] Machine follows Fsmx pattern with pure state transitions
2. [x] Strategy emits directives (no direct LLM calls)
3. [x] Tree structure correctly maintains parent/child relationships
4. [x] All traversal strategies work correctly
5. [x] All tests pass (73 ToT tests, 734 total)
6. [x] Usage and telemetry integration

## Current Status

**What Works**: Full implementation complete
**What's Next**: Commit and merge to v2
**How to Run**: `mix test test/jido_ai/tree_of_thoughts/`

---

## Changes Made

### New Files
- `lib/jido_ai/tree_of_thoughts/machine.ex` - Pure Fsmx state machine (~700 lines)
- `lib/jido_ai/strategies/tree_of_thoughts.ex` - Strategy adapter (~400 lines)
- `test/jido_ai/tree_of_thoughts/machine_test.exs` - Machine tests (47 tests)
- `test/jido_ai/strategies/tree_of_thoughts_test.exs` - Strategy tests (26 tests)

### Key Implementation Details

**State Machine States:**
- `idle` → `generating` → `evaluating` → `expanding` → `generating` (loop)
- `expanding` → `completed` (when max depth reached or no frontier)
- Any state → `error` (on failure)

**Traversal Strategies:**
- `:bfs` - Breadth-first search (explore level by level)
- `:dfs` - Depth-first search (explore deep before wide)
- `:best_first` - Always expand highest-scoring node (default)

**Configuration Options:**
- `:model` - LLM model identifier (default: "anthropic:claude-haiku-4-5")
- `:branching_factor` - Thoughts per node (default: 3)
- `:max_depth` - Maximum tree depth (default: 3)
- `:traversal_strategy` - BFS, DFS, or best-first (default: :best_first)
- `:generation_prompt` - Custom thought generation prompt
- `:evaluation_prompt` - Custom thought evaluation prompt
