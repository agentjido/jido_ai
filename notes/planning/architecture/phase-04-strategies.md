# Phase 4: Strategy Implementations

This phase implements AI reasoning strategies that leverage the Jido.Agent.Strategy protocol. Each strategy defines a different approach to AI problem-solving, from simple ReAct to complex graph-based reasoning.

## Design Principle

**Follow the existing ReAct pattern: Pure Machine + Directive Emission.**

The existing `Jido.AI.Strategy.ReAct` implementation demonstrates the correct pattern:

```
Strategy (thin adapter)     → Signal routing, config, directive lifting
    ↓
Machine (pure Fsmx FSM)     → State transitions, returns directives (no side effects)
    ↓
Directives                  → ReqLLMStream, ToolExec (executed by runtime)
```

**Key patterns:**
1. Strategies emit directives (`ReqLLMStream`, `ToolExec`) - they don't call ReqLLM directly
2. Each strategy has a pure state machine (Fsmx) that handles all transitions
3. `signal_routes/1` auto-routes signals to strategy commands
4. Machine returns `{machine, directives}` - completely pure, no side effects

## Existing Implementation (Reference)

```
lib/jido_ai/
├── react_agent.ex           # Convenience macro for ReAct agents
├── strategy/
│   └── react.ex             # Strategy: signal routing, directive lifting
└── react/
    └── machine.ex           # Pure Fsmx state machine
```

The ReAct strategy already exists and is fully functional. New strategies should follow this same architecture.

## Module Structure (New)

```
lib/jido_ai/
├── strategies/
│   ├── chain_of_thought.ex      # CoT strategy
│   ├── tree_of_thoughts.ex      # ToT strategy
│   ├── graph_of_thoughts.ex     # GoT strategy
│   └── adaptive.ex              # Adaptive strategy selection
├── chain_of_thought/
│   └── machine.ex               # CoT pure state machine
├── tree_of_thoughts/
│   └── machine.ex               # ToT pure state machine
└── graph_of_thoughts/
    └── machine.ex               # GoT pure state machine
```

## Dependencies

- Phase 1: Foundation Enhancement
- Phase 2: Tool System
- Phase 3: Algorithm Framework

---

## 4.1 ReAct Strategy (Enhancement)

The ReAct strategy already exists. This section covers enhancements only.

### 4.1.1 Current State

The existing implementation includes:
- ✅ Pure Fsmx state machine (`Jido.AI.ReAct.Machine`)
- ✅ Signal routing (`signal_routes/1`)
- ✅ Directive emission (`ReqLLMStream`, `ToolExec`)
- ✅ Streaming support (content + thinking chunks)
- ✅ Max iterations handling
- ✅ Tool call execution via `ToolAdapter.from_actions/1`

### 4.1.2 Enhancements

Enhance the existing ReAct strategy.

- [ ] 4.1.2.1 Add model alias support via `Config.resolve_model/1`
- [ ] 4.1.2.2 Add usage metadata extraction from LLM responses
- [ ] 4.1.2.3 Add telemetry for iteration tracking
- [ ] 4.1.2.4 Support dynamic tool registration via Phase 2 Registry

### 4.1.3 Unit Tests for ReAct Enhancements

- [ ] Test model alias resolution
- [ ] Test usage metadata in signals
- [ ] Test telemetry emission
- [ ] Test dynamic tool registration

---

## 4.2 Chain-of-Thought Strategy

Implement the Chain-of-Thought (CoT) strategy for step-by-step reasoning.

### 4.2.1 Machine Implementation

Create the pure CoT state machine.

- [ ] 4.2.1.1 Create `lib/jido_ai/chain_of_thought/machine.ex` with Fsmx
- [ ] 4.2.1.2 Define states: `:idle`, `:reasoning`, `:completed`, `:error`
- [ ] 4.2.1.3 Define transitions following Fsmx pattern
- [ ] 4.2.1.4 Implement `update/3` for message handling
- [ ] 4.2.1.5 Return `{machine, directives}` tuple (pure, no side effects)

### 4.2.2 Message Types

Define machine message types.

- [ ] 4.2.2.1 `{:start, prompt, call_id}` - Start CoT reasoning
- [ ] 4.2.2.2 `{:llm_result, call_id, result}` - Handle LLM response
- [ ] 4.2.2.3 `{:llm_partial, call_id, delta, chunk_type}` - Handle streaming

### 4.2.3 Directive Types

Define machine directive outputs.

- [ ] 4.2.3.1 `{:call_llm_stream, id, context}` - Request LLM call with CoT prompt
- [ ] 4.2.3.2 Build CoT system prompt ("Let's think step by step...")

### 4.2.4 Strategy Implementation

Create the CoT strategy adapter.

- [ ] 4.2.4.1 Create `lib/jido_ai/strategies/chain_of_thought.ex`
- [ ] 4.2.4.2 Use `Jido.Agent.Strategy` macro
- [ ] 4.2.4.3 Implement `init/2` to create machine and build config
- [ ] 4.2.4.4 Implement `cmd/3` to process instructions via machine
- [ ] 4.2.4.5 Implement `signal_routes/1` for signal → command routing
- [ ] 4.2.4.6 Implement `snapshot/2` for state inspection
- [ ] 4.2.4.7 Implement `lift_directives/2` to convert machine directives to SDK directives

### 4.2.5 Step Extraction

Implement reasoning step extraction from LLM responses.

- [ ] 4.2.5.1 Parse numbered step format ("Step 1:", "Step 2:", etc.)
- [ ] 4.2.5.2 Parse bullet point format
- [ ] 4.2.5.3 Detect final conclusion/answer
- [ ] 4.2.5.4 Store steps in machine state

### 4.2.6 Unit Tests for CoT Strategy

- [ ] Test machine state transitions
- [ ] Test machine returns correct directives
- [ ] Test strategy signal routing
- [ ] Test step extraction from responses
- [ ] Test CoT prompt generation
- [ ] Test conclusion detection

---

## 4.3 Tree-of-Thoughts Strategy

Implement the Tree-of-Thoughts (ToT) strategy for branching exploration.

### 4.3.1 Machine Implementation

Create the pure ToT state machine.

- [ ] 4.3.1.1 Create `lib/jido_ai/tree_of_thoughts/machine.ex` with Fsmx
- [ ] 4.3.1.2 Define states: `:idle`, `:generating`, `:evaluating`, `:expanding`, `:completed`, `:error`
- [ ] 4.3.1.3 Define tree node structure `%{id, parent_id, content, score, children}`
- [ ] 4.3.1.4 Implement `update/3` for message handling
- [ ] 4.3.1.5 Track thought tree in machine state

### 4.3.2 Message Types

Define machine message types.

- [ ] 4.3.2.1 `{:start, prompt, call_id}` - Start ToT exploration
- [ ] 4.3.2.2 `{:thoughts_generated, call_id, thoughts}` - Generated candidate thoughts
- [ ] 4.3.2.3 `{:thoughts_evaluated, call_id, scores}` - Evaluation scores
- [ ] 4.3.2.4 `{:llm_result, call_id, result}` - Generic LLM response

### 4.3.3 Directive Types

Define machine directive outputs.

- [ ] 4.3.3.1 `{:generate_thoughts, id, context, count}` - Generate N candidate thoughts
- [ ] 4.3.3.2 `{:evaluate_thoughts, id, thoughts}` - Evaluate thought candidates
- [ ] 4.3.3.3 `{:call_llm_stream, id, context}` - Standard LLM call

### 4.3.4 Strategy Implementation

Create the ToT strategy adapter.

- [ ] 4.3.4.1 Create `lib/jido_ai/strategies/tree_of_thoughts.ex`
- [ ] 4.3.4.2 Implement strategy callbacks following ReAct pattern
- [ ] 4.3.4.3 Configure branching_factor and max_depth in opts
- [ ] 4.3.4.4 Implement `lift_directives/2` for ToT-specific directives

### 4.3.5 Tree Traversal

Implement tree traversal in machine.

- [ ] 4.3.5.1 Implement BFS traversal
- [ ] 4.3.5.2 Implement DFS traversal
- [ ] 4.3.5.3 Implement best-first traversal (by score)
- [ ] 4.3.5.4 Configure traversal strategy via opts

### 4.3.6 Solution Extraction

Implement solution extraction from tree.

- [ ] 4.3.6.1 Find best leaf node by score
- [ ] 4.3.6.2 Trace path from root to solution
- [ ] 4.3.6.3 Format solution as final answer

### 4.3.7 Unit Tests for ToT Strategy

- [ ] Test machine state transitions
- [ ] Test thought tree construction
- [ ] Test evaluation scoring
- [ ] Test traversal strategies
- [ ] Test solution extraction
- [ ] Test max_depth limit

---

## 4.4 Graph-of-Thoughts Strategy

Implement the Graph-of-Thoughts (GoT) strategy for graph-based reasoning.

### 4.4.1 Machine Implementation

Create the pure GoT state machine.

- [ ] 4.4.1.1 Create `lib/jido_ai/graph_of_thoughts/machine.ex` with Fsmx
- [ ] 4.4.1.2 Define states: `:idle`, `:generating`, `:connecting`, `:aggregating`, `:completed`, `:error`
- [ ] 4.4.1.3 Define graph structure `%{nodes: %{}, edges: []}`
- [ ] 4.4.1.4 Implement `update/3` for message handling

### 4.4.2 Graph Operations

Implement graph operations in machine.

- [ ] 4.4.2.1 `add_node/2` - Add thought node to graph
- [ ] 4.4.2.2 `add_edge/3` - Connect two nodes
- [ ] 4.4.2.3 `merge_nodes/3` - Merge two nodes into one
- [ ] 4.4.2.4 `refine_node/3` - Refine a node's content

### 4.4.3 Directive Types

Define machine directive outputs.

- [ ] 4.4.3.1 `{:generate_thought, id, context}` - Generate single thought
- [ ] 4.4.3.2 `{:find_connections, id, node_id}` - Find related nodes
- [ ] 4.4.3.3 `{:aggregate, id, node_ids}` - Aggregate multiple nodes
- [ ] 4.4.3.4 `{:refine, id, node_id, context}` - Refine node content

### 4.4.4 Strategy Implementation

Create the GoT strategy adapter.

- [ ] 4.4.4.1 Create `lib/jido_ai/strategies/graph_of_thoughts.ex`
- [ ] 4.4.4.2 Implement strategy callbacks following ReAct pattern
- [ ] 4.4.4.3 Implement `lift_directives/2` for GoT-specific directives
- [ ] 4.4.4.4 Configure aggregation strategy via opts

### 4.4.5 Aggregation Strategies

Implement aggregation in machine.

- [ ] 4.4.5.1 Voting aggregation (majority wins)
- [ ] 4.4.5.2 Weighted average (by node scores)
- [ ] 4.4.5.3 LLM-based synthesis (request via directive)

### 4.4.6 Unit Tests for GoT Strategy

- [ ] Test machine state transitions
- [ ] Test graph construction
- [ ] Test node merging
- [ ] Test edge connections
- [ ] Test aggregation strategies
- [ ] Test cycle detection

---

## 4.5 Adaptive Strategy

Implement adaptive strategy selection based on task characteristics.

### 4.5.1 Strategy Implementation

Create the adaptive strategy.

- [ ] 4.5.1.1 Create `lib/jido_ai/strategies/adaptive.ex`
- [ ] 4.5.1.2 Use `Jido.Agent.Strategy` macro
- [ ] 4.5.1.3 Configure available strategies in opts
- [ ] 4.5.1.4 Delegate to selected strategy for all callbacks

### 4.5.2 Task Analysis

Implement task complexity analysis.

- [ ] 4.5.2.1 Analyze prompt length and complexity
- [ ] 4.5.2.2 Detect task type (reasoning, planning, search)
- [ ] 4.5.2.3 Optionally use LLM for classification (via directive)

### 4.5.3 Strategy Selection

Implement strategy selection logic.

- [ ] 4.5.3.1 Map task complexity to strategy:
  - Simple → CoT
  - Moderate → ReAct
  - Complex → ToT/GoT
- [ ] 4.5.3.2 Consider resource constraints
- [ ] 4.5.3.3 Support manual override via opts

### 4.5.4 Strategy Delegation

Implement delegation to selected strategy.

- [ ] 4.5.4.1 Initialize selected strategy on first command
- [ ] 4.5.4.2 Delegate `cmd/3`, `signal_routes/1`, `snapshot/2`
- [ ] 4.5.4.3 Support mid-conversation strategy switch (experimental)

### 4.5.5 Unit Tests for Adaptive Strategy

- [ ] Test task analysis classification
- [ ] Test strategy selection for different complexities
- [ ] Test delegation to selected strategy
- [ ] Test manual override
- [ ] Test fallback on selection failure

---

## 4.6 Phase 4 Integration Tests

Comprehensive integration tests verifying all Phase 4 components work together.

**Status**: COMPLETED (2026-01-04) - 27 tests passing

### 4.6.1 Strategy Execution Integration

Verify strategies execute correctly with the agent runtime.

- [x] 4.6.1.1 Create `test/jido_ai/integration/strategies_phase4_test.exs`
- [x] 4.6.1.2 Test: ReAct strategy completes multi-turn conversation
- [x] 4.6.1.3 Test: CoT strategy produces step-by-step reasoning
- [x] 4.6.1.4 Test: ToT strategy explores multiple branches

### 4.6.2 Signal Routing Integration

Test signal routing for all strategies.

- [x] 4.6.2.1 Test: `reqllm.result` routes to correct strategy command
- [x] 4.6.2.2 Test: `ai.tool_result` routes correctly
- [x] 4.6.2.3 Test: `reqllm.partial` routes for streaming

### 4.6.3 Directive Execution Integration

Test directive execution.

- [x] 4.6.3.1 Test: ReqLLMStream directive executes via runtime
- [x] 4.6.3.2 Test: ToolExec directive executes action
- [x] 4.6.3.3 Test: Result signals arrive back at strategy

### 4.6.4 Adaptive Selection Integration

Test adaptive strategy selection.

- [x] 4.6.4.1 Test: Simple prompt selects CoT
- [x] 4.6.4.2 Test: Tool-requiring prompt selects ReAct
- [x] 4.6.4.3 Test: Complex prompt selects ToT/GoT

---

## Phase 4 Success Criteria

1. **Machine Pattern**: Each strategy has a pure Fsmx state machine
2. **Directive Emission**: Strategies emit directives, don't call ReqLLM directly
3. **Signal Routing**: All strategies implement `signal_routes/1`
4. **ReAct Enhanced**: Existing strategy enhanced with config/telemetry
5. **New Strategies**: CoT, ToT, GoT implemented following pattern
6. **Adaptive Selection**: Task-based strategy selection working
7. **Test Coverage**: Minimum 80% for Phase 4 modules

---

## Phase 4 Critical Files

**Existing Files (Enhance):**
- `lib/jido_ai/strategy/react.ex` - Add config/telemetry
- `lib/jido_ai/react/machine.ex` - Reference implementation

**New Files:**
- `lib/jido_ai/strategies/chain_of_thought.ex`
- `lib/jido_ai/chain_of_thought/machine.ex`
- `lib/jido_ai/strategies/tree_of_thoughts.ex`
- `lib/jido_ai/tree_of_thoughts/machine.ex`
- `lib/jido_ai/strategies/graph_of_thoughts.ex`
- `lib/jido_ai/graph_of_thoughts/machine.ex`
- `lib/jido_ai/strategies/adaptive.ex`
- `test/jido_ai/strategies/chain_of_thought_test.exs`
- `test/jido_ai/strategies/tree_of_thoughts_test.exs`
- `test/jido_ai/strategies/graph_of_thoughts_test.exs`
- `test/jido_ai/strategies/adaptive_test.exs`
- `test/jido_ai/integration/strategies_phase4_test.exs`
