# Phase 4: Strategy Implementations

This phase implements AI reasoning strategies that leverage the Jido.Agent.Strategy protocol. Each strategy defines a different approach to AI problem-solving, from simple ReAct to complex graph-based reasoning.

## Module Structure

```
lib/jido_ai/
├── strategies/
│   ├── react.ex            # ReAct (Reasoning + Acting) strategy
│   ├── chain_of_thought.ex # Chain-of-Thought strategy
│   ├── tree_of_thoughts.ex # Tree-of-Thoughts strategy
│   ├── graph_of_thoughts.ex # Graph-of-Thoughts strategy
│   └── adaptive.ex         # Adaptive strategy selection
```

## Dependencies

- Phase 1: ReqLLM Integration Layer
- Phase 2: Tool System
- Phase 3: Algorithm Framework

---

## 4.1 ReAct Strategy

Implement the ReAct (Reasoning + Acting) strategy for LLM integration.

### 4.1.1 Strategy Setup

Create the ReAct strategy module implementing Jido.Agent.Strategy.

- [ ] 4.1.1.1 Create `lib/jido_ai/strategies/react.ex` with module documentation
- [ ] 4.1.1.2 Use `Jido.Agent.Strategy` macro
- [ ] 4.1.1.3 Add module aliases for Adapter, Registry, and related modules
- [ ] 4.1.1.4 Document ReAct loop semantics (Reason → Act → Observe → Repeat)

### 4.1.2 Init Callback

Implement strategy initialization.

- [ ] 4.1.2.1 Implement `init/2` callback with agent and context
- [ ] 4.1.2.2 Initialize strategy state with reasoning_steps, action_history, current_thought
- [ ] 4.1.2.3 Extract max_iterations from strategy_opts
- [ ] 4.1.2.4 Return `{updated_agent, directives}`

### 4.1.3 Cmd Callback

Implement the main command execution.

- [ ] 4.1.3.1 Implement `cmd/3` callback with agent, instructions, context
- [ ] 4.1.3.2 Extract model_spec from agent state
- [ ] 4.1.3.3 Get tools from Registry
- [ ] 4.1.3.4 Call process_react_loop/3

### 4.1.4 ReAct Loop Implementation

Implement the core ReAct loop.

- [ ] 4.1.4.1 Implement `process_react_loop/3` private function
- [ ] 4.1.4.2 Build system message with ReAct instructions
- [ ] 4.1.4.3 Stream response via Adapter
- [ ] 4.1.4.4 Parse response for thought, action, observation
- [ ] 4.1.4.5 Execute tool if action requested
- [ ] 4.1.4.6 Loop until completion or max_iterations

### 4.1.5 Response Parsing

Implement response parsing for ReAct format.

- [ ] 4.1.5.1 Implement `parse_react_response/1` for thought extraction
- [ ] 4.1.5.2 Implement `extract_action/1` for action parsing
- [ ] 4.1.5.3 Implement `extract_observation/1` for observation parsing
- [ ] 4.1.5.4 Handle final answer detection

### 4.1.6 Tool Execution

Implement tool execution within ReAct loop.

- [ ] 4.1.6.1 Implement `execute_action/3` for tool invocation
- [ ] 4.1.6.2 Parse action into tool name and parameters
- [ ] 4.1.6.3 Execute via Registry.execute_tool/3
- [ ] 4.1.6.4 Format observation from tool result

### 4.1.7 Unit Tests for ReAct Strategy

- [ ] Test init/2 initializes strategy state
- [ ] Test cmd/3 starts ReAct loop
- [ ] Test process_react_loop/3 iterates correctly
- [ ] Test parse_react_response/1 extracts thought
- [ ] Test extract_action/1 parses tool calls
- [ ] Test execute_action/3 invokes tools
- [ ] Test loop terminates on final answer
- [ ] Test loop terminates on max_iterations
- [ ] Test error handling during tool execution

---

## 4.2 Chain-of-Thought Strategy

Implement the Chain-of-Thought (CoT) strategy for step-by-step reasoning.

### 4.2.1 Strategy Setup

Create the CoT strategy module.

- [ ] 4.2.1.1 Create `lib/jido_ai/strategies/chain_of_thought.ex` with module documentation
- [ ] 4.2.1.2 Use `Jido.Agent.Strategy` macro
- [ ] 4.2.1.3 Document CoT semantics (step-by-step reasoning)

### 4.2.2 Init Callback

Implement strategy initialization.

- [ ] 4.2.2.1 Implement `init/2` callback
- [ ] 4.2.2.2 Initialize state with reasoning_chain, current_step
- [ ] 4.2.2.3 Configure reasoning depth from opts

### 4.2.3 Cmd Callback

Implement command execution with CoT prompting.

- [ ] 4.2.3.1 Implement `cmd/3` callback
- [ ] 4.2.3.2 Build CoT prompt with "Let's think step by step" pattern
- [ ] 4.2.3.3 Stream response and parse steps
- [ ] 4.2.3.4 Build reasoning chain from steps

### 4.2.4 Step Extraction

Implement reasoning step extraction.

- [ ] 4.2.4.1 Implement `extract_steps/1` for step parsing
- [ ] 4.2.4.2 Support numbered step format
- [ ] 4.2.4.3 Support bullet point format
- [ ] 4.2.4.4 Detect final conclusion

### 4.2.5 Unit Tests for CoT Strategy

- [ ] Test init/2 initializes reasoning chain
- [ ] Test cmd/3 builds CoT prompt
- [ ] Test extract_steps/1 parses numbered steps
- [ ] Test extract_steps/1 parses bullet points
- [ ] Test reasoning chain accumulation
- [ ] Test final conclusion detection

---

## 4.3 Tree-of-Thoughts Strategy

Implement the Tree-of-Thoughts (ToT) strategy for branching exploration.

### 4.3.1 Strategy Setup

Create the ToT strategy module.

- [ ] 4.3.1.1 Create `lib/jido_ai/strategies/tree_of_thoughts.ex` with module documentation
- [ ] 4.3.1.2 Use `Jido.Agent.Strategy` macro
- [ ] 4.3.1.3 Document ToT semantics (generate, evaluate, expand)

### 4.3.2 Init Callback

Implement strategy initialization.

- [ ] 4.3.2.1 Implement `init/2` callback
- [ ] 4.3.2.2 Initialize state with thought_tree, current_node
- [ ] 4.3.2.3 Configure branching_factor and max_depth from opts

### 4.3.3 Thought Generation

Implement thought generation for tree nodes.

- [ ] 4.3.3.1 Implement `generate_thoughts/3` for branch generation
- [ ] 4.3.3.2 Generate N candidate thoughts per node
- [ ] 4.3.3.3 Store thoughts in tree structure

### 4.3.4 Thought Evaluation

Implement thought evaluation for pruning.

- [ ] 4.3.4.1 Implement `evaluate_thoughts/2` for scoring
- [ ] 4.3.4.2 Score each thought for promise/feasibility
- [ ] 4.3.4.3 Use LLM for evaluation or heuristics

### 4.3.5 Tree Traversal

Implement tree traversal strategies.

- [ ] 4.3.5.1 Implement `traverse_bfs/1` for breadth-first search
- [ ] 4.3.5.2 Implement `traverse_dfs/1` for depth-first search
- [ ] 4.3.5.3 Implement `traverse_best_first/1` for best-first search
- [ ] 4.3.5.4 Configure traversal via opts

### 4.3.6 Solution Extraction

Implement solution extraction from tree.

- [ ] 4.3.6.1 Implement `extract_solution/1` for path extraction
- [ ] 4.3.6.2 Find best leaf node
- [ ] 4.3.6.3 Trace path from root to solution

### 4.3.7 Unit Tests for ToT Strategy

- [ ] Test init/2 initializes thought tree
- [ ] Test generate_thoughts/3 creates branches
- [ ] Test evaluate_thoughts/2 scores thoughts
- [ ] Test traverse_bfs/1 explores breadth-first
- [ ] Test traverse_dfs/1 explores depth-first
- [ ] Test traverse_best_first/1 prioritizes best
- [ ] Test extract_solution/1 finds best path
- [ ] Test max_depth limit respected

---

## 4.4 Graph-of-Thoughts Strategy

Implement the Graph-of-Thoughts (GoT) strategy for graph-based reasoning.

### 4.4.1 Strategy Setup

Create the GoT strategy module.

- [ ] 4.4.1.1 Create `lib/jido_ai/strategies/graph_of_thoughts.ex` with module documentation
- [ ] 4.4.1.2 Use `Jido.Agent.Strategy` macro
- [ ] 4.4.1.3 Document GoT semantics (non-linear reasoning graph)

### 4.4.2 Init Callback

Implement strategy initialization.

- [ ] 4.4.2.1 Implement `init/2` callback
- [ ] 4.4.2.2 Initialize state with thought_graph (nodes, edges)
- [ ] 4.4.2.3 Configure graph operations from opts

### 4.4.3 Graph Operations

Implement graph manipulation operations.

- [ ] 4.4.3.1 Implement `add_thought/2` for node creation
- [ ] 4.4.3.2 Implement `connect_thoughts/3` for edge creation
- [ ] 4.4.3.3 Implement `merge_thoughts/2` for node merging
- [ ] 4.4.3.4 Implement `refine_thought/2` for node refinement

### 4.4.4 Graph Traversal

Implement graph traversal for reasoning.

- [ ] 4.4.4.1 Implement `traverse_graph/2` for graph exploration
- [ ] 4.4.4.2 Support directed and undirected edges
- [ ] 4.4.4.3 Detect cycles and handle appropriately

### 4.4.5 Aggregation

Implement thought aggregation.

- [ ] 4.4.5.1 Implement `aggregate/2` for combining thoughts
- [ ] 4.4.5.2 Support voting aggregation
- [ ] 4.4.5.3 Support weighted average
- [ ] 4.4.5.4 Support LLM-based synthesis

### 4.4.6 Unit Tests for GoT Strategy

- [ ] Test init/2 initializes thought graph
- [ ] Test add_thought/2 creates nodes
- [ ] Test connect_thoughts/3 creates edges
- [ ] Test merge_thoughts/2 combines nodes
- [ ] Test refine_thought/2 updates nodes
- [ ] Test traverse_graph/2 explores graph
- [ ] Test aggregate/2 combines results
- [ ] Test cycle detection

---

## 4.5 Adaptive Strategy

Implement adaptive strategy selection based on task characteristics.

### 4.5.1 Strategy Setup

Create the adaptive strategy module.

- [ ] 4.5.1.1 Create `lib/jido_ai/strategies/adaptive.ex` with module documentation
- [ ] 4.5.1.2 Use `Jido.Agent.Strategy` macro
- [ ] 4.5.1.3 Document adaptive selection semantics

### 4.5.2 Init Callback

Implement strategy initialization.

- [ ] 4.5.2.1 Implement `init/2` callback
- [ ] 4.5.2.2 Initialize with strategy registry
- [ ] 4.5.2.3 Configure selection criteria from opts

### 4.5.3 Strategy Registry

Implement available strategy management.

- [ ] 4.5.3.1 Implement `register_strategy/2` for strategy registration
- [ ] 4.5.3.2 Store strategy with metadata (complexity, use_case)
- [ ] 4.5.3.3 Implement `list_strategies/0` for available strategies

### 4.5.4 Task Analysis

Implement task complexity analysis.

- [ ] 4.5.4.1 Implement `analyze_task/1` for task classification
- [ ] 4.5.4.2 Analyze task complexity (simple, moderate, complex)
- [ ] 4.5.4.3 Identify task type (reasoning, planning, search)
- [ ] 4.5.4.4 Use LLM for task analysis if needed

### 4.5.5 Strategy Selection

Implement strategy selection logic.

- [ ] 4.5.5.1 Implement `select_strategy/2` based on analysis
- [ ] 4.5.5.2 Match complexity to strategy capability
- [ ] 4.5.5.3 Consider resource constraints
- [ ] 4.5.5.4 Support manual override

### 4.5.6 Cmd Callback

Implement adaptive command execution.

- [ ] 4.5.6.1 Implement `cmd/3` callback
- [ ] 4.5.6.2 Analyze task
- [ ] 4.5.6.3 Select appropriate strategy
- [ ] 4.5.6.4 Delegate to selected strategy

### 4.5.7 Unit Tests for Adaptive Strategy

- [ ] Test init/2 initializes strategy registry
- [ ] Test register_strategy/2 adds strategies
- [ ] Test analyze_task/1 classifies tasks
- [ ] Test select_strategy/2 chooses appropriate strategy
- [ ] Test cmd/3 delegates to selected strategy
- [ ] Test manual override works
- [ ] Test fallback on selection failure

---

## 4.6 Phase 4 Integration Tests

Comprehensive integration tests verifying all Phase 4 components work together.

### 4.6.1 Strategy Execution Integration

Verify strategies execute correctly with tools.

- [ ] 4.6.1.1 Create `test/jido_ai/integration/strategies_phase4_test.exs`
- [ ] 4.6.1.2 Test: ReAct strategy with tool calling
- [ ] 4.6.1.3 Test: CoT strategy reasoning flow
- [ ] 4.6.1.4 Test: ToT strategy branching exploration

### 4.6.2 Agent Integration

Test strategies with full agent lifecycle.

- [ ] 4.6.2.1 Test: Agent with ReAct strategy completes task
- [ ] 4.6.2.2 Test: Strategy state persists across commands
- [ ] 4.6.2.3 Test: Strategy switch mid-conversation

### 4.6.3 Adaptive Selection Integration

Test adaptive strategy selection.

- [ ] 4.6.3.1 Test: Simple task selects CoT
- [ ] 4.6.3.2 Test: Complex task selects ToT/GoT
- [ ] 4.6.3.3 Test: Tool-heavy task selects ReAct
- [ ] 4.6.3.4 Test: Strategy fallback on failure

---

## Phase 4 Success Criteria

1. **ReAct Strategy**: Complete Reason-Act-Observe loop with tool calling
2. **CoT Strategy**: Step-by-step reasoning with chain extraction
3. **ToT Strategy**: Tree exploration with evaluation and pruning
4. **GoT Strategy**: Graph-based reasoning with aggregation
5. **Adaptive Strategy**: Task-based strategy selection
6. **Test Coverage**: Minimum 80% for Phase 4 modules

---

## Phase 4 Critical Files

**New Files:**
- `lib/jido_ai/strategies/react.ex` (or update existing)
- `lib/jido_ai/strategies/chain_of_thought.ex`
- `lib/jido_ai/strategies/tree_of_thoughts.ex`
- `lib/jido_ai/strategies/graph_of_thoughts.ex`
- `lib/jido_ai/strategies/adaptive.ex`
- `test/jido_ai/strategies/react_test.exs`
- `test/jido_ai/strategies/chain_of_thought_test.exs`
- `test/jido_ai/strategies/tree_of_thoughts_test.exs`
- `test/jido_ai/strategies/graph_of_thoughts_test.exs`
- `test/jido_ai/strategies/adaptive_test.exs`
- `test/jido_ai/integration/strategies_phase4_test.exs`

**Modified Files:**
- `lib/jido_ai/strategy/react.ex` - Enhance with ReqLLM integration
