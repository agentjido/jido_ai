# Tree-of-Thoughts: Multi-Path Exploration with Backtracking

## Introduction

Tree-of-Thoughts (ToT) is an advanced reasoning framework that explores multiple reasoning paths simultaneously through a tree-structured search space. Unlike linear Chain-of-Thought that follows a single reasoning path, or ReAct that explores iteratively, ToT systematically evaluates many possible reasoning trajectories, backtracks when paths prove unproductive, and maintains a global view of the problem-solving landscape.

The key innovation is **explicit tree search over thoughts**: at each reasoning step, the model generates multiple possible next thoughts, evaluates each for promise, and explores the most promising branches while pruning less valuable ones. This enables ToT to solve problems that require lookahead, planning, and systematic exploration that would be impossible with greedy single-path methods.

### Why Tree-of-Thoughts?

Research demonstrates that ToT delivers **dramatic improvements** on tasks requiring strategic exploration and planning:

- **Game of 24**: +74% success rate (4% → 74%)
- **Creative Writing**: +20% quality score
- **Mini Crosswords**: +60% solve rate
- **Cost**: 50-150× baseline (depends on tree size and search depth)
- **Best for**: Planning, game playing, algorithmic problems, exhaustive search

The framework excels because:
- **Systematic Exploration**: Considers multiple paths rather than committing early
- **Lookahead Capability**: Evaluates future promise before committing to a path
- **Backtracking**: Recovers from dead ends by exploring alternative branches
- **Global View**: Maintains understanding of the entire search space
- **Pruning**: Discards unpromising branches early to manage cost

### Performance

ToT achieves state-of-the-art results on tasks requiring strategic reasoning:

| Task Type | Baseline | With ToT | Improvement | Cost |
|-----------|----------|----------|-------------|------|
| Game of 24 | 4% | 74% | +70% | 100-150× |
| Creative Writing | 60% | 80% | +20% | 50-100× |
| Mini Crosswords | 20% | 80% | +60% | 80-120× |
| Planning Tasks | 40% | 75% | +35% | 70-100× |

**Critical Consideration**: The 50-150× cost increase makes ToT suitable only for:
- High-value problems where accuracy justifies expense
- Tasks genuinely requiring exhaustive exploration
- Applications where single-path methods demonstrably fail

> **💡 Practical Examples**: See the [Tree-of-Thoughts examples directory](../examples/tree-of-thoughts/) for complete working implementations including a game solver and a strategic planner.

---

## Core Concepts

### The Tree Structure

ToT organizes reasoning as a tree where:
- **Root**: Initial problem statement
- **Nodes**: Intermediate reasoning states
- **Edges**: Thought transitions between states
- **Leaves**: Terminal states (solutions or dead ends)
- **Path**: Sequence of thoughts from root to a node

```
                      [Problem: Make 24 using 4,5,6,6]
                     /              |              \
        [Try (6-4)*12]    [Try (6+5)*something]    [Try 6*6-12]
          /       \              /      \               /    \
    [6-4=2]    [6÷4=1.5]   [6+5=11]  [6+6=12]    [6*6=36]  [Dead]
      /  \         |           |         |           |
  [2*12=24] [2*11=22] [11*2=22] [12*2=24]  [36-12=24]
    ✓        ✗          ✗         ✓          ✓
```

### How It Works

#### 1. Thought Generation

At each node, generate `k` possible next thoughts:

```elixir
# Generate 3 possible next steps
thoughts = [
  "Calculate 6-4 = 2",
  "Calculate 6+5 = 11",
  "Calculate 6*6 = 36"
]
```

#### 2. Thought Evaluation

Evaluate each thought's promise using one of several strategies:

```elixir
# Value evaluation: Score each thought 0-1
scores = [0.8, 0.6, 0.5]

# Thoughts are evaluated before expanding
# Only high-scoring thoughts are explored further
```

#### 3. Tree Search

Use a search strategy to explore the tree:

- **BFS (Breadth-First)**: Explore level-by-level, guarantees optimal depth
- **DFS (Depth-First)**: Explore deeply first, memory efficient
- **Best-First**: Always expand most promising node (like A*)

#### 4. Pruning

Discard low-value branches early:

```elixir
# Keep only top-k thoughts at each step
beam_width = 3

# Prune thoughts with score < threshold
pruning_threshold = 0.4

# Stop expanding at max depth
max_depth = 5
```

### Key Components

| Component | Purpose |
|-----------|---------|
| **Tree** | Maintains all explored nodes and their relationships |
| **TreeNode** | Represents a reasoning state with thought, value, and connections |
| **ThoughtGenerator** | Creates multiple candidate next thoughts |
| **ThoughtEvaluator** | Scores thoughts for promise using various strategies |
| **SearchStrategy** | Determines which nodes to expand (BFS/DFS/Best-First) |
| **PruningPolicy** | Decides which branches to discard |

### Integration with Jido AI

Jido AI implements ToT as a standalone function that executes tree search:

```elixir
# Run tree search
{:ok, result} = Jido.AI.Runner.TreeOfThoughts.run(
  problem: "Make 24 using the numbers 4, 5, 6, 6",
  search_strategy: :bfs,
  beam_width: 3,
  max_depth: 4,
  evaluation_strategy: :value,
  budget: 100
)

# Result includes solution and complete tree
IO.puts("Answer: #{result.answer}")
IO.puts("Solution path: #{length(result.solution_path)} steps")
IO.puts("Tree size: #{result.metadata.tree_size} nodes")
IO.puts("Nodes evaluated: #{result.nodes_evaluated}")
```

The ToT runner:
- Generates multiple thoughts at each node
- Evaluates thoughts using configurable strategies
- Explores the tree using BFS, DFS, or Best-First search
- Prunes low-value branches to manage costs
- Returns the solution path and complete tree

---

## When to Use Tree-of-Thoughts

### Ideal Use Cases

ToT excels when tasks require:

**Strategic Planning**
- Multi-step plans with dependencies
- Resource allocation problems
- Scheduling and optimization
- Route planning with constraints

**Game Playing**
- Games requiring lookahead (chess, Go)
- Puzzle solving (crosswords, Sudoku)
- Mathematical games (Game of 24)
- Strategy games with decision trees

**Algorithmic Problems**
- Combinatorial optimization
- Search problems with multiple paths
- Problems requiring backtracking
- Exhaustive exploration tasks

**Creative Generation**
- Story writing with multiple plot branches
- Design exploration with alternatives
- Brainstorming with diverse options
- Comparative analysis of approaches

**Complex Reasoning**
- Problems where greedy approaches fail
- Tasks requiring revision and refinement
- Multi-criteria decision making
- Trade-off analysis

### When NOT to Use Tree-of-Thoughts

Consider alternatives when:

- **Single-Path Sufficient**: Most problems don't need multiple paths (use CoT)
- **Cost Prohibitive**: 50-150× increase is unacceptable
- **Latency Critical**: Tree search takes 50-100 seconds minimum
- **Simple Lookups**: Direct answers don't benefit from exploration
- **Linear Problems**: Sequential reasoning works fine (use CoT or ReAct)

### Cost-Benefit Analysis

```
Without ToT (Chain-of-Thought):
- Latency: 2-3s
- Tokens: 300-400
- LLM Calls: 1
- Accuracy: 4% (Game of 24)
- Cost: $0.003

With ToT (BFS, beam=3, depth=4):
- Latency: 60-90s (30-45× increase)
- Tokens: 15,000-25,000 (50-80× increase)
- LLM Calls: 50-100 (50-100× increase)
- Accuracy: 74% (+70%)
- Cost: $0.15-0.30 (50-100× increase)
```

**ROI Decision Matrix**:

| Problem Value | CoT Accuracy | ToT Accuracy | Use ToT? |
|---------------|--------------|--------------|----------|
| Low ($10) | 60% | 85% | ❌ No - cost exceeds value |
| Medium ($100) | 40% | 75% | ⚠️ Maybe - depends on failure cost |
| High ($10,000) | 30% | 80% | ✅ Yes - improvement justifies cost |
| Critical (lives) | 50% | 90% | ✅ Yes - accuracy paramount |

**When ToT Makes Sense**:
- Failure cost >> search cost
- No human can solve the problem efficiently
- Systematic exploration genuinely needed
- Single-path methods demonstrably inadequate

---

## Getting Started

### Prerequisites

1. **Jido AI installed** with LLM provider configured
2. **API keys set** for your chosen provider
3. **Problem defined** that benefits from tree search
4. **Budget allocated** for extensive LLM calls

### Basic Setup

```elixir
# Set your API key
Jido.AI.Keyring.set_env_value(:openai_api_key, "sk-...")

# Define the problem
problem = "Make 24 using the numbers 4, 5, 6, 6. You can use +, -, *, / and parentheses."

# Run ToT with BFS
{:ok, result} = Jido.AI.Runner.TreeOfThoughts.run(
  problem: problem,
  search_strategy: :bfs,
  beam_width: 3,
  max_depth: 4,
  budget: 50
)

case result.success do
  true ->
    IO.puts("✓ Solution found: #{result.answer}")
    IO.puts("  Steps: #{length(result.solution_path)}")
    IO.puts("  Nodes explored: #{result.nodes_evaluated}")

  false ->
    IO.puts("✗ No solution found")
    IO.puts("  Reason: #{result.reason}")
    IO.puts("  Nodes explored: #{result.nodes_evaluated}")
end
```

### Simple Example

```elixir
defmodule Examples.BasicToT do
  @moduledoc """
  Simple example demonstrating Tree-of-Thoughts for a planning problem.
  """

  alias Jido.AI.Runner.TreeOfThoughts

  def plan_route do
    IO.puts("=== Tree-of-Thoughts Route Planning ===\n")

    problem = """
    Plan a route from City A to City D with the following constraints:
    - Must visit at least 2 cities
    - Cannot revisit cities
    - Minimize total distance
    - Available routes: A→B(10), A→C(15), B→C(5), B→D(20), C→D(10)
    """

    IO.puts("Problem: #{problem}\n")

    # Custom solution checker
    solution_check = fn node ->
      # Check if we've reached City D with valid path
      state = node.state
      String.contains?(node.thought, "City D") and
        Map.get(state, :cities_visited, 0) >= 2
    end

    # Run ToT search
    {:ok, result} = TreeOfThoughts.run(
      problem: problem,
      initial_state: %{current_city: "A", cities_visited: 1, total_distance: 0},
      search_strategy: :best_first,  # Use best-first for optimization
      beam_width: 3,
      max_depth: 4,
      evaluation_strategy: :value,
      budget: 30,
      solution_check: solution_check
    )

    # Display results
    display_results(result)

    {:ok, result}
  end

  defp display_results(result) do
    IO.puts("\n=== Results ===")
    IO.puts("Success: #{result.success}")
    IO.puts("Answer: #{result.answer || "No solution"}")
    IO.puts("Search steps: #{result.search_steps}")
    IO.puts("Nodes evaluated: #{result.nodes_evaluated}")
    IO.puts("Tree size: #{result.metadata.tree_size}")

    if result.success and length(result.solution_path) > 0 do
      IO.puts("\n=== Solution Path ===")

      result.solution_path
      |> Enum.with_index(1)
      |> Enum.each(fn {node, idx} ->
        IO.puts("#{idx}. #{node.thought} (value: #{Float.round(node.value || 0.0, 2)})")
      end)
    end
  end
end

# Run the example
Examples.BasicToT.plan_route()
```

### Configuration Options

```elixir
# Minimal configuration
opts = [
  problem: "Your problem here",
  search_strategy: :bfs,
  beam_width: 3,
  max_depth: 5
]

# Full configuration
full_opts = [
  problem: "Complex problem",
  initial_state: %{custom: "state"},
  search_strategy: :best_first,       # :bfs, :dfs, or :best_first
  beam_width: 5,                      # Thoughts per node
  max_depth: 6,                       # Maximum tree depth
  evaluation_strategy: :hybrid,       # :value, :vote, :heuristic, :hybrid
  budget: 100,                        # Max nodes to evaluate
  solution_check: solution_fn,        # Custom solution checker
  thought_fn: thought_fn,             # Custom thought generation (testing)
  evaluation_fn: eval_fn              # Custom evaluation (testing)
]

{:ok, result} = TreeOfThoughts.run(full_opts)
```

---

## Understanding Tree-of-Thoughts Components

### Tree Structure

The tree maintains all explored reasoning states:

```elixir
tree = %Tree{
  root_id: "node_1",
  nodes: %{
    "node_1" => %TreeNode{...},
    "node_2" => %TreeNode{...},
    # ... more nodes
  },
  edges: %{
    "node_1" => ["node_2", "node_3", "node_4"],
    "node_2" => ["node_5", "node_6"],
    # ... more edges
  },
  size: 15,
  max_depth: 4
}

# Tree operations
{:ok, node} = Tree.get_node(tree, "node_5")
path = Tree.get_path(tree, "node_5")
{:ok, {updated_tree, child}} = Tree.add_child(tree, parent_id, thought, state)
```

### TreeNode Structure

Each node represents a reasoning state:

```elixir
node = %TreeNode{
  id: "node_5",
  thought: "Calculate 6-4 = 2",
  state: %{
    numbers_used: [6, 4],
    intermediate_result: 2,
    operations: ["6-4"]
  },
  value: 0.85,                    # Evaluation score (0-1)
  depth: 2,                       # Distance from root
  parent_id: "node_2",
  children_ids: ["node_8", "node_9"],
  metadata: %{
    created_at: ~U[2024-01-01 12:00:00Z],
    evaluated_by: :value_strategy
  }
}

# Node operations
TreeNode.leaf?(node)              # Check if leaf node
TreeNode.set_value(node, 0.9)     # Update value
TreeNode.add_child(node, "node_10")  # Add child reference
```

### Thought Generation

The `ThoughtGenerator` creates candidate next thoughts:

```elixir
# Generate thoughts for a node
{:ok, thoughts} = ThoughtGenerator.generate(
  problem: "Make 24 using 4,5,6,6",
  parent_state: %{numbers_available: [4, 5, 6, 6]},
  beam_width: 3,
  depth: 1,
  tree_size: 5
)

# Returns list of thought strings
thoughts = [
  "Try combining 6 and 4: 6-4 = 2",
  "Try combining 6 and 5: 6+5 = 11",
  "Try combining 6 and 6: 6*6 = 36"
]

# Thoughts are generated based on:
# - Current problem
# - Parent state (what's been done)
# - Depth (how far into search)
# - Tree size (for context)
```

### Thought Evaluation

The `ThoughtEvaluator` scores thoughts for promise:

```elixir
# Evaluate multiple thoughts
thoughts = ["6-4 = 2", "6+5 = 11", "6*6 = 36"]

{:ok, scores} = ThoughtEvaluator.evaluate_batch(
  thoughts,
  problem: "Make 24",
  state: %{numbers: [4, 5, 6, 6]},
  strategy: :value
)

# Returns scores 0-1
scores = [0.85, 0.65, 0.55]

# Higher scores = more promising thoughts
# Evaluation strategies:
# - :value - Direct value judgment
# - :vote - Multiple evaluations, majority vote
# - :heuristic - Domain-specific heuristic
# - :hybrid - Combination of strategies
```

### Search Strategies

Three search strategies are available:

#### Breadth-First Search (BFS)

```elixir
# Explore level-by-level
config = [search_strategy: :bfs]

# BFS characteristics:
# ✓ Finds optimal solution (shortest path)
# ✓ Systematic exploration
# ✗ High memory usage (stores all frontier)
# ✗ May explore many nodes before finding solution

# Best for:
# - Finding shortest solution path
# - When optimality matters
# - Shallow solutions expected
```

#### Depth-First Search (DFS)

```elixir
# Explore deeply before backtracking
config = [search_strategy: :dfs]

# DFS characteristics:
# ✓ Memory efficient (only stores path)
# ✓ Finds solutions quickly if they're deep
# ✗ May explore dead ends deeply
# ✗ No optimality guarantee

# Best for:
# - Memory-constrained scenarios
# - Deep solution paths expected
# - Don't need shortest path
```

#### Best-First Search

```elixir
# Always expand most promising node
config = [search_strategy: :best_first]

# Best-First characteristics:
# ✓ Focuses on promising branches
# ✓ Often finds solutions faster
# ✓ Balances exploration and exploitation
# ✗ Requires good evaluation function
# ✗ Can get stuck in local optima

# Best for:
# - Good heuristics available
# - Want to minimize nodes explored
# - Solution quality > optimality
```

### Evaluation Strategies

Four evaluation strategies score thought quality:

#### Value Strategy

```elixir
evaluation_strategy: :value

# Direct value judgment: "How promising is this thought?"
# - Single LLM call per thought
# - Fast, deterministic
# - Good for clear metrics

# Example prompt:
# "Rate this thought's promise (0-1) for solving 'Make 24':
#  Thought: '6-4 = 2'
#  Response: 0.85"
```

#### Vote Strategy

```elixir
evaluation_strategy: :vote

# Multiple evaluations, use majority/average
# - 3-5 LLM calls per thought
# - More robust, less variance
# - Higher cost (3-5× per thought)

# Example:
# Vote 1: 0.8
# Vote 2: 0.9
# Vote 3: 0.7
# Final: 0.8 (average)
```

#### Heuristic Strategy

```elixir
evaluation_strategy: :heuristic

# Domain-specific heuristic function
# - No LLM calls (code-based)
# - Fast, consistent, cheap
# - Requires domain knowledge

# Example for Game of 24:
def heuristic(thought, state) do
  numbers_used = count_numbers_used(thought)
  result_closeness = how_close_to_24(thought)

  0.3 * numbers_used + 0.7 * result_closeness
end
```

#### Hybrid Strategy

```elixir
evaluation_strategy: :hybrid

# Combines multiple strategies
# - Heuristic for quick filtering
# - Value/vote for final ranking
# - Balances cost and quality

# Example:
# 1. Heuristic filters to top 50%
# 2. Value evaluation on remaining
# 3. Best of both worlds
```

---

## Configuration Options

### Core Parameters

```elixir
config = [
  # Problem definition (required)
  problem: "Make 24 using 4, 5, 6, 6",

  # Initial state (optional)
  initial_state: %{
    numbers_available: [4, 5, 6, 6],
    operations: []
  },

  # Search configuration
  search_strategy: :bfs,          # :bfs, :dfs, or :best_first
  beam_width: 3,                  # Thoughts generated per node
  max_depth: 5,                   # Maximum tree depth
  budget: 100,                    # Maximum nodes to evaluate

  # Evaluation
  evaluation_strategy: :value,    # :value, :vote, :heuristic, :hybrid

  # Custom functions
  solution_check: fn node -> ... end,   # Check if node is solution
  thought_fn: fn state -> ... end,      # Override thought generation
  evaluation_fn: fn thought -> ... end  # Override evaluation
]
```

### Search Strategy Configuration

```elixir
# BFS: Optimal but expensive
bfs_config = [
  search_strategy: :bfs,
  beam_width: 3,              # Wider beam = more exploration
  max_depth: 4                # Shallower = faster solution
]

# DFS: Fast but may miss optimal
dfs_config = [
  search_strategy: :dfs,
  beam_width: 2,              # Narrower beam = deeper search
  max_depth: 6                # Allow deeper exploration
]

# Best-First: Balanced
best_first_config = [
  search_strategy: :best_first,
  beam_width: 5,              # More options at each step
  evaluation_strategy: :hybrid # Need good evaluation
]
```

### Beam Width

```elixir
# Narrow beam (2-3): Focused, cheaper
narrow_beam = [beam_width: 2]
# - Explores fewer options
# - Lower cost
# - May miss solutions

# Medium beam (3-5): Balanced (recommended)
medium_beam = [beam_width: 3]
# - Good coverage
# - Reasonable cost
# - Usually sufficient

# Wide beam (5-10): Thorough, expensive
wide_beam = [beam_width: 7]
# - Explores many options
# - High cost
# - Better for complex problems
```

### Max Depth

```elixir
# Shallow (3-4): Quick solutions
shallow = [max_depth: 3]
# - Fast search
# - Simple problems only

# Medium (4-6): Standard (recommended)
medium = [max_depth: 5]
# - Good for most problems
# - Balances depth and cost

# Deep (6-10): Complex problems
deep = [max_depth: 8]
# - Allows complex solutions
# - Very expensive
```

### Budget Control

```elixir
# Budget limits total nodes evaluated
# Prevents runaway costs

# Conservative (20-50 nodes)
conservative = [budget: 30]
# Cost: ~$0.30-0.75

# Standard (50-100 nodes)
standard = [budget: 75]
# Cost: ~$0.75-1.50

# Aggressive (100-200 nodes)
aggressive = [budget: 150]
# Cost: ~$1.50-3.00

# Calculate budget:
# budget = beam_width * max_depth * branching_factor
# Example: 3 * 5 * 3 = 45 nodes minimum
```

### Solution Checking

```elixir
# Custom solution checker
solution_check = fn node ->
  # Check if node represents a solution
  state = node.state
  thought = node.thought

  # Example: Game of 24
  String.contains?(thought, "= 24") and
    all_numbers_used?(state)
end

config = [
  problem: "...",
  solution_check: solution_check
]

# Default solution checker (if not provided):
# - Leaf node (no children)
# - Depth >= max_depth/2
# - Value > 0.8
```

### Custom Thought Generation (Testing)

```elixir
# Override thought generation for testing
thought_fn = fn opts ->
  problem = opts[:problem]
  state = opts[:parent_state]
  beam_width = opts[:beam_width]

  # Generate predetermined thoughts
  case state.depth do
    0 -> ["Thought A", "Thought B", "Thought C"]
    1 -> ["Next step 1", "Next step 2"]
    _ -> ["Final step"]
  end
end

config = [
  problem: "...",
  thought_fn: thought_fn
]
```

### Custom Evaluation (Testing)

```elixir
# Override evaluation for testing
evaluation_fn = fn thoughts, opts ->
  # Return predetermined scores
  thoughts
  |> Enum.with_index()
  |> Enum.map(fn {_thought, idx} ->
    0.9 - (idx * 0.1)  # Decreasing scores
  end)
end

config = [
  problem: "...",
  evaluation_fn: evaluation_fn
]
```

---

## Best Practices

### 1. Choose Appropriate Search Strategy

```elixir
# Simple problems → BFS
config = [search_strategy: :bfs, max_depth: 3]

# Complex problems → Best-First
config = [search_strategy: :best_first, evaluation_strategy: :hybrid]

# Memory constrained → DFS
config = [search_strategy: :dfs, max_depth: 6]
```

### 2. Set Realistic Budgets

```elixir
# Calculate minimum budget
min_budget = beam_width * max_depth

# Add buffer for branching
recommended_budget = min_budget * 2

# Example: beam=3, depth=5
# min = 15, recommended = 30

config = [budget: recommended_budget]
```

### 3. Use Appropriate Beam Width

```elixir
# Start narrow, increase if needed
initial_config = [beam_width: 2]

# If no solution found, widen beam
retry_config = [beam_width: 4]

# Monitor success rate
def choose_beam_width(problem_complexity) do
  case problem_complexity do
    :simple -> 2
    :medium -> 3
    :complex -> 5
  end
end
```

### 4. Implement Good Solution Checkers

```elixir
# Good: Specific, fast checks
good_checker = fn node ->
  result = extract_result(node.thought)
  result == 24 and all_numbers_used?(node.state)
end

# Bad: Vague, slow checks
bad_checker = fn node ->
  # Calls LLM to verify - very expensive!
  verify_with_llm(node.thought)
end

# Solution checkers should be:
# - Fast (no LLM calls)
# - Deterministic
# - Precise (no false positives)
```

### 5. Use Heuristics When Possible

```elixir
# Hybrid strategy with domain heuristic
config = [
  evaluation_strategy: :hybrid,
  heuristic: fn thought, state ->
    # Fast, domain-specific scoring
    closeness_to_goal(thought) * 0.5 +
    efficiency_score(state) * 0.5
  end
]

# Heuristics reduce LLM calls significantly
# Can cut costs by 50-70%
```

### 6. Monitor and Limit Costs

```elixir
# Track costs during search
defmodule CostMonitor do
  def track_search(config) do
    start_budget = config[:budget]

    result = TreeOfThoughts.run(config)

    estimated_cost = result.nodes_evaluated * 0.01

    Logger.info("""
    ToT Search Complete:
      Nodes evaluated: #{result.nodes_evaluated}/#{start_budget}
      Estimated cost: $#{Float.round(estimated_cost, 2)}
      Success: #{result.success}
    """)

    result
  end
end

# Set budget alerts
if result.nodes_evaluated >= budget * 0.8 do
  Logger.warning("Approaching budget limit!")
end
```

### 7. Start Small, Scale Up

```elixir
# Progressive refinement
defmodule ProgressiveToT do
  def solve(problem) do
    # Phase 1: Quick exploration
    {:ok, quick_result} = TreeOfThoughts.run(
      problem: problem,
      beam_width: 2,
      max_depth: 3,
      budget: 20
    )

    if quick_result.success do
      quick_result
    else
      # Phase 2: Deeper search
      TreeOfThoughts.run(
        problem: problem,
        beam_width: 4,
        max_depth: 5,
        budget: 100
      )
    end
  end
end
```

### 8. Analyze Solution Paths

```elixir
# Review solution paths for insights
defmodule PathAnalyzer do
  def analyze(result) do
    if result.success do
      IO.puts("\n=== Solution Path Analysis ===")

      result.solution_path
      |> Enum.with_index(1)
      |> Enum.each(fn {node, step} ->
        IO.puts("""
        Step #{step}:
          Thought: #{node.thought}
          Value: #{Float.round(node.value, 2)}
          Depth: #{node.depth}
        """)
      end)

      # Analyze decision points
      critical_steps =
        result.solution_path
        |> Enum.filter(fn node -> node.value > 0.8 end)

      IO.puts("\nCritical steps: #{length(critical_steps)}")
    end
  end
end
```

### 9. Cache Thought Evaluations

```elixir
# Cache evaluations to avoid redundant LLM calls
defmodule CachedEvaluator do
  use GenServer

  def evaluate_with_cache(thought, opts) do
    key = :crypto.hash(:md5, thought) |> Base.encode16()

    case get_cached(key) do
      nil ->
        score = ThoughtEvaluator.evaluate(thought, opts)
        cache_score(key, score)
        score

      cached_score ->
        cached_score
    end
  end

  # Cache management...
end

# Can reduce costs by 20-40% on similar problems
```

### 10. Test with Simpler Problems First

```elixir
# Validate ToT setup on simple problems
defmodule ToTValidator do
  def validate_setup(config) do
    simple_problems = [
      "Find a path from A to B",
      "Order numbers: 3, 1, 2",
      "Simple math: 2 + 2"
    ]

    results =
      Enum.map(simple_problems, fn problem ->
        TreeOfThoughts.run(
          problem: problem,
          search_strategy: config[:search_strategy],
          beam_width: 2,
          max_depth: 2,
          budget: 10
        )
      end)

    success_rate =
      Enum.count(results, fn {:ok, r} -> r.success end) / length(results)

    if success_rate > 0.7 do
      IO.puts("✓ Setup validated, ready for complex problems")
      :ok
    else
      IO.puts("✗ Setup needs adjustment")
      {:error, "Low success rate: #{success_rate}"}
    end
  end
end
```

---

## Integration Patterns

### Pattern 1: Game Solving

Use ToT for strategic game playing:

```elixir
defmodule GameSolver do
  alias Jido.AI.Runner.TreeOfThoughts

  def solve_game_of_24(numbers) do
    problem = "Make 24 using #{inspect(numbers)} with operations +, -, *, /"

    solution_check = fn node ->
      String.match?(node.thought, ~r/=\s*24\s*$/) and
        all_numbers_used?(node.state, numbers)
    end

    {:ok, result} = TreeOfThoughts.run(
      problem: problem,
      initial_state: %{numbers: numbers, used: [], operations: []},
      search_strategy: :best_first,
      beam_width: 4,
      max_depth: length(numbers),
      evaluation_strategy: :value,
      budget: 100,
      solution_check: solution_check
    )

    if result.success do
      %{
        solution: result.answer,
        steps: result.solution_path,
        efficiency: calculate_efficiency(result)
      }
    else
      {:error, "No solution found within budget"}
    end
  end

  defp all_numbers_used?(state, numbers) do
    MapSet.equal?(
      MapSet.new(state.used),
      MapSet.new(numbers)
    )
  end

  defp calculate_efficiency(result) do
    # Fewer nodes = more efficient
    1.0 - (result.nodes_evaluated / result.metadata.budget)
  end
end

# Solve Game of 24
{:ok, solution} = GameSolver.solve_game_of_24([4, 5, 6, 6])
IO.puts("Solution: #{solution.solution}")
```

### Pattern 2: Strategic Planning

Use ToT for multi-step planning:

```elixir
defmodule StrategicPlanner do
  alias Jido.AI.Runner.TreeOfThoughts

  def plan_project(requirements, constraints) do
    problem = """
    Plan a project with:
    Requirements: #{inspect(requirements)}
    Constraints: #{inspect(constraints)}

    Find an optimal plan considering cost, time, and quality.
    """

    solution_check = fn node ->
      plan = extract_plan(node.state)
      meets_requirements?(plan, requirements) and
        within_constraints?(plan, constraints)
    end

    {:ok, result} = TreeOfThoughts.run(
      problem: problem,
      initial_state: %{
        plan: [],
        cost: 0,
        duration: 0,
        tasks_completed: []
      },
      search_strategy: :best_first,
      beam_width: 5,
      max_depth: 8,
      evaluation_strategy: :hybrid,
      budget: 150,
      solution_check: solution_check
    )

    if result.success do
      analyze_plan(result)
    else
      generate_partial_plan(result)
    end
  end

  defp extract_plan(state), do: state.plan

  defp meets_requirements?(plan, requirements) do
    # Check if plan satisfies all requirements
    Enum.all?(requirements, fn req ->
      Enum.any?(plan, fn task -> satisfies?(task, req) end)
    end)
  end

  defp within_constraints?(plan, constraints) do
    # Check if plan respects constraints
    cost = Enum.sum(Enum.map(plan, & &1.cost))
    duration = calculate_duration(plan)

    cost <= constraints.max_cost and
      duration <= constraints.max_duration
  end

  defp analyze_plan(result) do
    %{
      plan: extract_plan(List.last(result.solution_path).state),
      alternatives: extract_alternatives(result.tree),
      confidence: calculate_confidence(result),
      cost_breakdown: analyze_costs(result)
    }
  end

  defp generate_partial_plan(result) do
    # Even if no complete solution, extract best partial plan
    best_node = find_best_node(result.tree)

    %{
      partial_plan: extract_plan(best_node.state),
      completion: calculate_completion(best_node, result),
      suggestions: generate_suggestions(best_node)
    }
  end
end

# Plan a software project
{:ok, plan} = StrategicPlanner.plan_project(
  [:feature_a, :feature_b, :testing, :deployment],
  %{max_cost: 50_000, max_duration: 90}
)

IO.inspect(plan)
```

### Pattern 3: Creative Writing

Use ToT for exploring creative alternatives:

```elixir
defmodule CreativeWriter do
  alias Jido.AI.Runner.TreeOfThoughts

  def write_story(prompt, style, constraints) do
    problem = """
    Write a story based on: #{prompt}
    Style: #{style}
    Constraints: #{inspect(constraints)}

    Explore multiple plot directions and choose the most compelling.
    """

    solution_check = fn node ->
      story_complete?(node.thought) and
        satisfies_constraints?(node.state, constraints)
    end

    {:ok, result} = TreeOfThoughts.run(
      problem: problem,
      initial_state: %{
        paragraphs: [],
        characters: [],
        plot_points: [],
        word_count: 0
      },
      search_strategy: :bfs,  # Explore all creative directions
      beam_width: 5,          # Many alternatives
      max_depth: 6,           # Multiple story beats
      evaluation_strategy: :vote,  # Multiple judges
      budget: 200,
      solution_check: solution_check
    )

    %{
      story: assemble_story(result.solution_path),
      alternatives: extract_alternative_paths(result.tree),
      creative_score: calculate_creativity(result),
      plot_analysis: analyze_plot(result.solution_path)
    }
  end

  defp story_complete?(thought) do
    # Check if story has conclusion
    String.contains?(String.downcase(thought), ["end", "conclusion", "finally"])
  end

  defp satisfies_constraints?(state, constraints) do
    state.word_count >= constraints.min_words and
      state.word_count <= constraints.max_words and
      length(state.plot_points) >= constraints.min_plot_points
  end

  defp assemble_story(path) do
    path
    |> Enum.map(& &1.thought)
    |> Enum.join("\n\n")
  end

  defp extract_alternative_paths(tree) do
    # Find other high-quality story branches
    tree.nodes
    |> Enum.filter(fn {_id, node} -> node.value > 0.7 end)
    |> Enum.map(fn {id, _node} -> Tree.get_path(tree, id) end)
    |> Enum.take(3)
  end

  defp calculate_creativity(result) do
    # More diverse branches = more creative
    unique_branches = count_unique_branches(result.tree)
    min(1.0, unique_branches / 10.0)
  end

  defp analyze_plot(path) do
    %{
      rising_action: identify_rising_action(path),
      climax: identify_climax(path),
      resolution: identify_resolution(path),
      character_arcs: analyze_characters(path)
    }
  end
end

# Write a creative story
{:ok, story_result} = CreativeWriter.write_story(
  "A detective discovers their partner is the culprit",
  "noir thriller",
  %{min_words: 500, max_words: 1000, min_plot_points: 5}
)

IO.puts(story_result.story)
```

### Pattern 4: Algorithm Design

Use ToT for designing algorithms:

```elixir
defmodule AlgorithmDesigner do
  alias Jido.AI.Runner.TreeOfThoughts

  def design_algorithm(problem_spec, requirements) do
    problem = """
    Design an algorithm for: #{problem_spec}

    Requirements:
    - Time complexity: #{requirements.time_complexity}
    - Space complexity: #{requirements.space_complexity}
    - Constraints: #{inspect(requirements.constraints)}

    Explore different algorithmic approaches.
    """

    solution_check = fn node ->
      algorithm = extract_algorithm(node.state)
      valid_algorithm?(algorithm) and
        meets_complexity_requirements?(algorithm, requirements)
    end

    {:ok, result} = TreeOfThoughts.run(
      problem: problem,
      initial_state: %{
        approach: nil,
        steps: [],
        data_structures: [],
        complexity_analysis: nil
      },
      search_strategy: :best_first,
      beam_width: 4,
      max_depth: 7,
      evaluation_strategy: :hybrid,
      budget: 120,
      solution_check: solution_check
    )

    %{
      algorithm: extract_algorithm(List.last(result.solution_path).state),
      approach: identify_approach(result.solution_path),
      complexity: analyze_complexity(result.solution_path),
      alternatives: find_alternative_algorithms(result.tree),
      pseudocode: generate_pseudocode(result.solution_path)
    }
  end

  defp extract_algorithm(state) do
    %{
      steps: state.steps,
      data_structures: state.data_structures
    }
  end

  defp valid_algorithm?(algorithm) do
    length(algorithm.steps) > 0 and
      has_base_case?(algorithm) and
      has_recursive_case?(algorithm)
  end

  defp meets_complexity_requirements?(algorithm, requirements) do
    actual_time = estimate_time_complexity(algorithm)
    actual_space = estimate_space_complexity(algorithm)

    complexity_within_bounds?(actual_time, requirements.time_complexity) and
      complexity_within_bounds?(actual_space, requirements.space_complexity)
  end

  defp identify_approach(path) do
    # Identify algorithmic paradigm
    cond do
      uses_divide_and_conquer?(path) -> :divide_and_conquer
      uses_dynamic_programming?(path) -> :dynamic_programming
      uses_greedy?(path) -> :greedy
      uses_backtracking?(path) -> :backtracking
      true -> :other
    end
  end

  defp find_alternative_algorithms(tree) do
    # Find other valid algorithms explored
    tree.nodes
    |> Enum.filter(fn {_id, node} ->
      node.value > 0.6 and
        node.depth >= tree.max_depth - 1
    end)
    |> Enum.map(fn {id, _} ->
      path = Tree.get_path(tree, id)
      extract_algorithm(List.last(path).state)
    end)
    |> Enum.uniq()
  end
end

# Design sorting algorithm
{:ok, algorithm} = AlgorithmDesigner.design_algorithm(
  "Sort an array of integers",
  %{
    time_complexity: "O(n log n)",
    space_complexity: "O(n)",
    constraints: [:stable, :comparison_based]
  }
)

IO.inspect(algorithm.approach)
IO.puts(algorithm.pseudocode)
```

---

## Troubleshooting

### Common Issues

#### Budget Exhausted Without Solution

**Problem**: `{:ok, %{success: false, reason: :budget_exhausted}}`

**Solutions**:

```elixir
# 1. Increase budget
config = [budget: 200]  # Was 100

# 2. Reduce search space
config = [
  beam_width: 3,  # Was 5
  max_depth: 4    # Was 6
]

# 3. Improve solution checker
# Make it less restrictive
solution_check = fn node ->
  # Accept "close enough" solutions
  node.depth >= 3 and node.value > 0.7
end

# 4. Use better evaluation strategy
config = [evaluation_strategy: :hybrid]
```

#### Frontier Exhausted

**Problem**: `{:ok, %{success: false, reason: :frontier_exhausted}}`

**Solutions**:

```elixir
# 1. Increase beam width
config = [beam_width: 5]  # Was 3

# 2. Increase max depth
config = [max_depth: 6]  # Was 4

# 3. Check solution checker isn't too strict
# Review solution_check function

# 4. Verify problem is solvable
# Test with simpler version first
```

#### All Nodes Low Value

**Problem**: All thoughts scored < 0.5, search terminated early

**Solutions**:

```elixir
# 1. Improve thought generation
# Thoughts may not be relevant to problem

# 2. Adjust evaluation criteria
# May be too harsh

# 3. Use different evaluation strategy
config = [evaluation_strategy: :vote]  # More lenient

# 4. Provide better initial state
config = [
  initial_state: %{
    helpful: "context",
    domain: "knowledge"
  }
]
```

#### Very Slow Execution

**Problem**: ToT takes > 2 minutes

**Solutions**:

```elixir
# 1. Reduce budget
config = [budget: 50]  # Was 150

# 2. Reduce beam width
config = [beam_width: 2]  # Was 5

# 3. Use DFS instead of BFS
config = [search_strategy: :dfs]

# 4. Reduce max depth
config = [max_depth: 4]  # Was 7

# 5. Use heuristic evaluation (no LLM)
config = [evaluation_strategy: :heuristic]
```

#### High Costs

**Problem**: Each run costs $5-10

**Solutions**:

```elixir
# 1. Strict budget limits
config = [budget: 30]  # Limit total nodes

# 2. Use heuristic evaluation
config = [
  evaluation_strategy: :heuristic,
  heuristic: fn thought, state ->
    # Fast, code-based scoring
    score_thought(thought, state)
  end
]

# 3. Cache evaluations
# Avoid re-evaluating similar thoughts

# 4. Use cheaper model
# GPT-3.5 instead of GPT-4

# 5. Progressive refinement
# Start small, expand only if needed
{:ok, quick} = ToT.run(budget: 20)
if not quick.success do
  ToT.run(budget: 100)
end
```

### Debugging Tips

1. **Visualize the Tree**

```elixir
defmodule TreeVisualizer do
  def visualize(tree) do
    IO.puts("\n=== Tree Structure ===")
    IO.puts("Size: #{tree.size} nodes")
    IO.puts("Max depth: #{tree.max_depth}")

    # Print tree breadth-first
    visualize_node(tree, tree.root_id, 0)
  end

  defp visualize_node(tree, node_id, indent) do
    {:ok, node} = Tree.get_node(tree, node_id)

    prefix = String.duplicate("  ", indent)
    IO.puts("#{prefix}├─ #{String.slice(node.thought, 0, 50)}... (value: #{Float.round(node.value || 0, 2)})")

    children_ids = tree.edges[node_id] || []
    Enum.each(children_ids, fn child_id ->
      visualize_node(tree, child_id, indent + 1)
    end)
  end
end

{:ok, result} = TreeOfThoughts.run(...)
TreeVisualizer.visualize(result.tree)
```

2. **Inspect Solution Path**

```elixir
if result.success do
  IO.puts("\n=== Solution Path ===")

  result.solution_path
  |> Enum.with_index(1)
  |> Enum.each(fn {node, step} ->
    IO.puts("""
    Step #{step}:
      Thought: #{node.thought}
      Value: #{node.value}
      Depth: #{node.depth}
      State: #{inspect(node.state)}
    """)
  end)
end
```

3. **Analyze Node Distribution**

```elixir
defmodule TreeAnalyzer do
  def analyze(result) do
    nodes = Map.values(result.tree.nodes)

    value_distribution =
      nodes
      |> Enum.map(& &1.value || 0)
      |> Enum.chunk_by(fn v -> div(trunc(v * 10), 2) end)
      |> Enum.map(&length/1)

    depth_distribution =
      nodes
      |> Enum.group_by(& &1.depth)
      |> Enum.map(fn {depth, nodes} -> {depth, length(nodes)} end)
      |> Enum.sort()

    IO.puts("""
    Tree Analysis:
      Total nodes: #{length(nodes)}
      Value distribution: #{inspect(value_distribution)}
      Depth distribution: #{inspect(depth_distribution)}
      Budget used: #{result.nodes_evaluated}/#{result.metadata.budget}
    """)
  end
end

TreeAnalyzer.analyze(result)
```

4. **Test with Simple Problems**

```elixir
# Test ToT on trivially solvable problem
simple_problem = "Count from 1 to 3"

{:ok, result} = TreeOfThoughts.run(
  problem: simple_problem,
  search_strategy: :bfs,
  beam_width: 2,
  max_depth: 3,
  budget: 10
)

if result.success do
  IO.puts("✓ ToT working correctly")
else
  IO.puts("✗ ToT setup issue: #{result.reason}")
end
```

### Getting Help

If issues persist:

1. Check [Tree-of-Thoughts examples directory](../examples/tree-of-thoughts/)
2. Review [API documentation](https://hexdocs.pm/jido_ai)
3. Search [GitHub issues](https://github.com/agentjido/jido_ai/issues)
4. Ask in [Elixir Forum](https://elixirforum.com/)

---

## Conclusion

Tree-of-Thoughts provides a powerful framework for problems requiring systematic exploration and strategic reasoning. By maintaining a tree of possibilities and using search strategies to navigate it, ToT achieves dramatic accuracy improvements on planning, game-playing, and algorithmic tasks. However, the 50-150× cost increase makes it suitable only for high-value problems where single-path methods fail.

### Key Takeaways

- **Dramatic Gains**: +70% on Game of 24, but at 50-150× cost
- **Tree Search**: Systematic exploration with BFS, DFS, or Best-First
- **Multiple Paths**: Explores alternatives, backtracks from dead ends
- **Evaluation-Guided**: Thought scoring directs search toward promising branches
- **Budget Control**: Explicit limits prevent runaway costs

### When to Use Tree-of-Thoughts

**Use ToT for:**
- Game playing requiring lookahead (Game of 24, chess puzzles)
- Planning tasks with multiple valid approaches
- Algorithmic problems needing systematic exploration
- Creative tasks benefiting from exploring alternatives
- High-value problems where accuracy justifies cost

**Skip ToT for:**
- Most problems (use CoT or ReAct instead)
- Cost-sensitive applications
- Latency-critical scenarios
- Problems solvable by single-path reasoning
- Simple queries or lookups

### Cost Decision Framework

```
Should I use ToT?

1. Is problem unsolvable by CoT/ReAct?
   No → Don't use ToT
   Yes → Continue

2. Is accuracy improvement worth 50-100× cost?
   No → Don't use ToT
   Yes → Continue

3. Can problem benefit from exploring multiple paths?
   No → Don't use ToT
   Yes → Continue

4. Is budget available ($1-5+ per query)?
   No → Don't use ToT
   Yes → Use ToT with strict budget limits
```

### Next Steps

1. **Test on Simple Problems**: Validate setup with trivial problems
2. **Start Small**: Begin with budget=20-30, expand as needed
3. **Use Heuristics**: Reduce costs with domain-specific evaluation
4. **Monitor Carefully**: Track costs and success rates
5. **Consider Alternatives**: Try CoT/ReAct first, ToT as last resort

### Further Reading

- [Chain-of-Thought Guide](./chain_of_thought.md) - Single-path reasoning
- [ReAct Guide](./react.md) - Iterative reasoning with actions
- [Self-Consistency Guide](./self_consistency.md) - Multiple paths with voting
- [Prompt Engineering Guide](./prompt.md) - Prompt design best practices
- [Actions Guide](./actions.md) - Building custom actions

### Examples

Explore complete working examples:

- [Tree-of-Thoughts Examples Directory](../examples/tree-of-thoughts/) - Complete working implementations:
  - `game_solver.ex` - Basic ToT with BFS/DFS search and thought evaluation
  - `strategic_planner.ex` - Advanced ToT with best-first search and pruning strategies
  - `README.md` - Comprehensive documentation and usage patterns
- `lib/jido_ai/runner/tree_of_thoughts.ex` - Full implementation
- `test/jido_ai/runner/tree_of_thoughts_test.exs` - Test suite

By mastering Tree-of-Thoughts, you can tackle problems that require strategic exploration and planning, achieving dramatic accuracy improvements on tasks where single-path reasoning falls short. However, always consider the significant cost increase and use ToT judiciously for high-value problems where the investment is justified.
