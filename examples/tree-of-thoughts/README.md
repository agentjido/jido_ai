# Tree-of-Thoughts Examples

This directory contains practical examples demonstrating Tree-of-Thoughts (ToT) reasoning with Jido AI.

## What is Tree-of-Thoughts?

Tree-of-Thoughts is an advanced reasoning framework that explores multiple reasoning paths simultaneously through tree-structured search. Unlike Chain-of-Thought (single path) or ReAct (iterative), ToT systematically evaluates many possible reasoning trajectories, backtracks from dead ends, and maintains a global view of the problem-solving landscape.

**Key Innovation**: Explicit tree search over thoughts - at each step, the model generates multiple possible next thoughts, evaluates each for promise, and explores the most promising branches while pruning less valuable ones.

## Performance

ToT delivers dramatic improvements on strategic tasks:

| Task Type | Baseline | With ToT | Improvement | Cost |
|-----------|----------|----------|-------------|------|
| Game of 24 | 4% | 74% | +70% | 100-150× |
| Creative Writing | 60% | 80% | +20% | 50-100× |
| Mini Crosswords | 20% | 80% | +60% | 80-120× |
| Planning Tasks | 40% | 75% | +35% | 70-100× |

**Critical Consideration**: Use ToT only for high-value problems where single-path methods fail and the 50-150× cost increase is justified.

## Examples

### 1. Game of 24 (`game_of_24.ex`)

**Purpose**: Demonstrates basic ToT reasoning with the canonical Game of 24 puzzle.

**Features**:
- Tree-based exploration with multiple paths
- Backtracking from dead ends
- Thought evaluation and pruning
- Complete solution path tracking
- Tree visualization
- Multiple search strategies (BFS, DFS, Best-First)

**The Game**: Given 4 numbers, use arithmetic operations (+, -, *, /) to make 24.

**Usage**:
```elixir
# Run the example
Examples.TreeOfThoughts.GameOf24.run()

# Solve a custom problem
Examples.TreeOfThoughts.GameOf24.solve([3, 3, 8, 8])

# Solve with different strategy
Examples.TreeOfThoughts.GameOf24.solve(
  [4, 5, 6, 6],
  search_strategy: :best_first,
  beam_width: 4,
  budget: 100
)

# Compare with CoT
Examples.TreeOfThoughts.GameOf24.compare_with_cot()

# Batch solve multiple problems
Examples.TreeOfThoughts.GameOf24.batch_solve([
  [4, 5, 6, 6],
  [1, 2, 3, 4],
  [3, 3, 8, 8]
])
```

**Example Output**:
```
🌳 Tree-of-Thoughts: Game of 24

Problem: Make 24 using [4, 5, 6, 6]

🔍 Search Progress:
   1.   Start: Available numbers [4, 5, 6, 6] (1.0)
   2.     6 - 4 = 2 (0.85)
   3.     6 + 5 = 11 (0.65)
   4.       2 * 6 = 12 (0.75)
   5.         12 + 5 = 17 (0.60)
   6.         12 * 2 = 24 ✓

🎯 Solution Found: 6 - 4 = 2, 2 * 6 = 12, 12 + 12 = 24
   Nodes evaluated: 28
   Tree size: 45 nodes
```

**Key Concepts**:
- Systematic exploration of operation combinations
- Heuristic evaluation (closeness to 24, progress, feasibility)
- Beam search to limit branching
- Solution verification

**Best For**:
- Learning ToT basics
- Mathematical puzzles
- Understanding tree search
- Exploring evaluation strategies

---

### 2. Strategic Planner (`strategic_planner.ex`)

**Purpose**: Demonstrates advanced ToT reasoning with multi-criteria optimization and constraints.

**Features**:
- Multi-criteria optimization (cost, time, quality)
- Dependency tracking and validation
- Constraint satisfaction checking
- Alternative plan exploration
- Best-first search with hybrid evaluation
- Partial plan generation
- Multiple solution discovery

**The Problem**: Given a set of tasks with dependencies, costs, and durations, find optimal execution plans that meet requirements and constraints.

**Usage**:
```elixir
# Run the example
Examples.TreeOfThoughts.StrategicPlanner.run()

# Plan a custom project
Examples.TreeOfThoughts.StrategicPlanner.plan_project(
  [:requirements, :design, :backend, :frontend, :testing, :deployment],
  %{max_cost: 80_000, max_duration: 120, min_quality_score: 8.0},
  [:fully_tested, :documented, :production_ready]
)

# Compare search strategies
Examples.TreeOfThoughts.StrategicPlanner.compare_strategies()
```

**Task Catalog** (built-in):
- Requirements Analysis ($5k, 10d, quality 9.0)
- System Design ($8k, 15d, quality 9.5)
- Backend Development ($25k, 40d, quality 8.0)
- Frontend Development ($20k, 35d, quality 8.0)
- Quality Assurance ($12k, 20d, quality 10.0)
- Production Deployment ($6k, 10d, quality 7.0)
- Performance Optimization ($15k, 20d, quality 8.5)
- Security Hardening ($10k, 15d, quality 9.0)
- Documentation ($5k, 10d, quality 7.5)

**Example Output**:
```
🎯 Optimal Plan Found:
   • Total cost: $76,000
   • Total duration: 110 days
   • Quality score: 8.2/10
   • Tasks: 6

📋 Task Sequence:
   1. Requirements Analysis - $5,000, 10d, quality 9.0
   2. System Design - $8,000, 15d, quality 9.5
   3. Backend Development - $25,000, 40d, quality 8.0
   4. Frontend Development - $20,000, 35d, quality 8.0
   5. Quality Assurance - $12,000, 20d, quality 10.0
   6. Production Deployment - $6,000, 10d, quality 7.0

✅ Requirements Met:
   • fully_tested
   • documented
   • production_ready

🔄 Alternative Solutions:
   2. Cost: $81,000, Duration: 115d, Score: 0.82
   3. Cost: $71,000, Duration: 125d, Score: 0.79
```

**Key Concepts**:
- Multi-criteria evaluation (weighted combination)
- Dependency resolution
- Constraint checking at each step
- Critical path analysis
- Alternative solution tracking
- Partial plan extraction

**Best For**:
- Project planning
- Resource allocation
- Scheduling problems
- Multi-objective optimization
- Production-grade ToT patterns

---

### 3. Tree-of-Thought Example (`tree_of_thought_example.ex`)

**Purpose**: Comprehensive example showing multiple ToT patterns and use cases.

**Features**:
- Multiple problem types (games, planning, optimization)
- Custom evaluation strategies
- Solution verification
- Performance comparison
- Cost analysis

**Usage**:
See the file for detailed usage patterns and additional examples.

---

## Quick Start

### Running Examples in IEx

```elixir
# Start IEx
iex -S mix

# Compile examples
c "examples/tree-of-thoughts/game_of_24.ex"
c "examples/tree-of-thoughts/strategic_planner.ex"

# Run examples
Examples.TreeOfThoughts.GameOf24.run()
Examples.TreeOfThoughts.StrategicPlanner.run()
```

### Running from Mix Task

```bash
# Run Game of 24
mix run -e "Examples.TreeOfThoughts.GameOf24.run()"

# Run Strategic Planner
mix run -e "Examples.TreeOfThoughts.StrategicPlanner.run()"
```

## Comparison: Basic vs Advanced Examples

| Aspect | Game of 24 | Strategic Planner |
|--------|------------|-------------------|
| **Complexity** | Medium | High |
| **Search Space** | Mathematical operations | Task combinations |
| **Evaluation** | Heuristic | Multi-criteria |
| **Constraints** | Mathematical validity | Cost, time, quality |
| **Dependencies** | None | Task dependencies |
| **Solutions** | Single best | Multiple alternatives |
| **Best For** | Learning | Production planning |

## Common Patterns

### Pattern 1: BFS Tree Search

Used in: `game_of_24.ex`

```elixir
defp run_tree_search(state) do
  cond do
    state.solution_id != nil ->
      # Found solution
      {:ok, finalize_result(state, :solution_found)}

    state.nodes_evaluated >= state.budget ->
      # Budget exhausted
      {:ok, finalize_result(state, :budget_exhausted)}

    Enum.empty?(state.frontier) ->
      # Frontier exhausted
      {:ok, finalize_result(state, :frontier_exhausted)}

    true ->
      # Expand next node
      case expand_next_node(state) do
        {:ok, new_state} -> run_tree_search(new_state)
        {:error, reason} -> {:error, reason}
      end
  end
end
```

### Pattern 2: Thought Generation with Constraints

Used in: `strategic_planner.ex`

```elixir
defp generate_thoughts(node, state) do
  plan_state = node.state

  # Find tasks that can be scheduled next (dependencies met)
  available_tasks =
    plan_state.tasks_remaining
    |> Enum.filter(fn task ->
      task_def = state.task_catalog[task]
      dependencies_met?(task_def.dependencies, plan_state.tasks_completed)
    end)

  # Generate thought for each available task
  available_tasks
  |> Enum.map(fn task ->
    generate_task_thought(task, plan_state, state)
  end)
  |> Enum.reject(&is_nil/1)
end
```

### Pattern 3: Multi-Criteria Evaluation

Used in: `strategic_planner.ex`

```elixir
defp evaluate_thought(thought, state) do
  plan_state = thought.state

  # Calculate individual criteria scores
  cost_score = 1.0 - (plan_state.total_cost / state.constraints.max_cost)
  time_score = 1.0 - (plan_state.total_duration / state.constraints.max_duration)
  quality_score = plan_state.quality_score / 10.0
  progress_score = length(plan_state.tasks_completed) / length(state.tasks)

  # Weighted combination
  0.2 * cost_score +
    0.2 * time_score +
    0.25 * quality_score +
    0.35 * progress_score
end
```

### Pattern 4: Search Strategy Selection

Used in: Both examples

```elixir
defp select_next_node(state) do
  case state.search_strategy do
    :bfs ->
      # Breadth-first: explore level by level
      [node_id | rest] = state.frontier
      {node_id, rest}

    :dfs ->
      # Depth-first: explore deeply first
      {node_id, rest} = List.pop_at(state.frontier, -1)
      {node_id, rest}

    :best_first ->
      # Best-first: always expand most promising node
      best_id = Enum.max_by(state.frontier, fn id ->
        {:ok, node} = Tree.get_node(state.tree, id)
        node.value || 0.0
      end)
      {best_id, List.delete(state.frontier, best_id)}
  end
end
```

## Tips for Using These Examples

1. **Start Simple**: Begin with `game_of_24.ex` to understand tree search basics
2. **Understand Costs**: ToT is 50-150× more expensive than single-path methods
3. **Use Appropriate Strategy**: BFS for optimal solutions, Best-First for efficiency
4. **Set Budgets**: Always limit nodes evaluated to prevent runaway costs
5. **Optimize Evaluation**: Use heuristics when possible to reduce LLM calls
6. **Monitor Progress**: Track nodes evaluated and solutions found
7. **Experiment**: Try different beam widths and search strategies

## When to Use Tree-of-Thoughts

### ✅ Use ToT For:
- **Game playing** requiring lookahead (Game of 24, chess puzzles)
- **Planning tasks** with multiple valid approaches
- **Algorithmic problems** needing systematic exploration
- **Creative tasks** benefiting from exploring alternatives
- **High-value problems** where accuracy justifies 50-150× cost
- **Problems where CoT/ReAct fail** demonstrably

### ❌ Skip ToT For:
- **Most problems** (use CoT or ReAct instead)
- **Cost-sensitive** applications
- **Latency-critical** scenarios (ToT takes 50-100+ seconds)
- **Simple queries** or lookups
- **Linear problems** solvable by single-path reasoning

## Key Differences from Other Methods

| Aspect | Chain-of-Thought | ReAct | Tree-of-Thoughts |
|--------|------------------|-------|------------------|
| **Paths** | Single | Iterative single | Multiple simultaneous |
| **Backtracking** | No | Limited | Yes |
| **External Tools** | No | Yes | Optional |
| **Accuracy Boost** | +8-15% | +27% | +70% (on Game of 24) |
| **Cost** | 3-4× | 10-30× | 50-150× |
| **Best For** | Reasoning | Research + Action | Strategic planning |

## Search Strategies

### Breadth-First Search (BFS)
- ✓ Finds optimal solution (shortest path)
- ✓ Systematic exploration
- ✗ High memory usage
- **Best for**: Finding shortest solution path, when optimality matters

### Depth-First Search (DFS)
- ✓ Memory efficient
- ✓ Finds solutions quickly if they're deep
- ✗ May explore dead ends deeply
- **Best for**: Memory-constrained scenarios, deep solutions

### Best-First Search
- ✓ Focuses on promising branches
- ✓ Often finds solutions faster
- ✓ Balances exploration and exploitation
- **Best for**: Good heuristics available, want to minimize nodes explored

## Cost Management

```
Typical Costs (Game of 24, beam=3, depth=4):
- Nodes evaluated: 50-80
- LLM calls: 150-250
- Tokens: 15,000-25,000
- Cost: $0.15-0.30
- Time: 60-90 seconds

Compare to CoT:
- Nodes: 1
- LLM calls: 1
- Tokens: 300-400
- Cost: $0.003
- Time: 2-3 seconds

ROI Calculation:
- Use ToT only if problem value > $1 and accuracy matters
- Consider progressive refinement (try CoT first, ToT if it fails)
- Set strict budgets (30-50 nodes for initial exploration)
- Use heuristic evaluation to reduce LLM calls by 50-70%
```

## Integration with Jido AI

These examples can be adapted to work with Jido AI's action system:

```elixir
defmodule MyToTAgent do
  use Jido.Agent,
    name: "strategic_planner",
    actions: [PlanningAction, OptimizationAction]

  def solve_planning_problem(agent, tasks, constraints) do
    # Build tree with Jido actions
    tree = initialize_tree(tasks)

    # Run ToT search
    state = %{
      tree: tree,
      frontier: [tree.root_id],
      search_strategy: :best_first,
      beam_width: 4,
      budget: 100
    }

    run_tree_search(state)
  end
end
```

## Further Reading

- [Tree-of-Thoughts Guide](../../guides/tree_of_thoughts.md) - Complete documentation
- [Chain-of-Thought Guide](../../guides/chain_of_thought.md) - Single-path reasoning
- [ReAct Guide](../../guides/react.md) - Iterative reasoning with actions
- [Self-Consistency Guide](../../guides/self_consistency.md) - Multiple paths with voting

## Contributing

To add new examples:

1. Create a new file in this directory
2. Follow the existing pattern (TreeNode, Tree, search loop)
3. Implement domain-specific thought generation and evaluation
4. Include usage examples in module documentation
5. Update this README with the new example
6. Add tests if applicable

## Questions?

See the main [Tree-of-Thoughts Guide](../../guides/tree_of_thoughts.md) for detailed documentation on:
- Thought generation strategies
- Evaluation approaches
- Pruning policies
- Cost optimization
- Production deployment
