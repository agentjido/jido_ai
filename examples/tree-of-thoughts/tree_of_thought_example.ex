defmodule Examples.TreeOfThoughtExample do
  @moduledoc """
  Practical example demonstrating Tree-of-Thought (ToT) reasoning usage.

  Tree-of-Thought is an advanced reasoning technique that explores multiple reasoning
  paths in a tree structure, evaluating different branches and backtracking to find
  optimal solutions. Unlike Chain-of-Thought which follows a single reasoning path,
  ToT explores multiple possibilities simultaneously.

  ## Basic Usage

      # Simple problem with multiple solution paths
      {:ok, result} = Examples.TreeOfThoughtExample.solve_with_tree_search(
        problem: "Find the optimal route from A to D visiting B and C",
        search_strategy: :breadth_first,
        max_depth: 4
      )

      IO.inspect(result.solution_tree)
      IO.puts("Best path: #{result.best_path}")
      IO.puts("Explored #{result.nodes_explored} possibilities")

  ## Comparison: Chain vs Tree of Thought

      # Chain-of-Thought: Single reasoning path
      {:ok, cot} = solve_with_chain(problem: "Plan a 3-day trip to Paris")

      # Tree-of-Thought: Explores multiple itineraries
      {:ok, tot} = solve_with_tree_search(
        problem: "Plan a 3-day trip to Paris",
        search_strategy: :best_first
      )

      # ToT finds better solutions by exploring alternatives

  ## Advanced Usage - Strategic Planning

      {:ok, result} = Examples.TreeOfThoughtExample.plan_with_alternatives(
        goal: "Launch a new product",
        constraints: ["6 month timeline", "limited budget"],
        explore_alternatives: 5
      )

      IO.inspect(result.alternative_plans)
      IO.puts("Best strategy: #{result.recommended_plan}")

  ## Features

  - Multiple reasoning path exploration
  - Branch evaluation and pruning
  - Backtracking from dead ends
  - Best-first and breadth-first search
  - Solution quality comparison
  - Optimal path selection
  """

  require Logger

  alias Jido.AI.Runner.TreeOfThought

  @doc """
  Solve a problem using Tree-of-Thought with exploration of multiple paths.

  ToT builds a tree of reasoning steps, evaluates branches, and selects the
  best solution path. More thorough than Chain-of-Thought but more expensive.

  ## Parameters

  - `:problem` - Problem statement to solve
  - `:search_strategy` - `:breadth_first`, `:depth_first`, or `:best_first` (default: :best_first)
  - `:max_depth` - Maximum tree depth (default: 5)
  - `:branching_factor` - Number of alternatives per node (default: 3)
  - `:evaluation_threshold` - Minimum score to continue branch (default: 0.3)

  ## Returns

  - `{:ok, result}` with:
    - `:solution_tree` - Full exploration tree
    - `:best_path` - Optimal reasoning path found
    - `:nodes_explored` - Number of nodes evaluated
    - `:confidence` - Confidence in solution
    - `:alternatives` - Other viable solutions

  ## Examples

      # Strategic decision with multiple paths
      {:ok, result} = solve_with_tree_search(
        problem: "Choose technology stack for web app",
        search_strategy: :best_first,
        branching_factor: 3,
        max_depth: 4
      )

      # Output shows explored alternatives:
      # %{
      #   solution_tree: %TreeNode{...},
      #   best_path: ["React + Node.js", "PostgreSQL", "AWS", "Docker"],
      #   nodes_explored: 24,
      #   confidence: 0.89,
      #   alternatives: [
      #     {0.85, ["Vue + Django", "MongoDB", "Heroku"]},
      #     {0.82, ["Angular + .NET", "SQL Server", "Azure"]}
      #   ]
      # }
  """
  @spec solve_with_tree_search(keyword()) :: {:ok, map()} | {:error, term()}
  def solve_with_tree_search(opts) do
    problem = Keyword.fetch!(opts, :problem)
    search_strategy = Keyword.get(opts, :search_strategy, :best_first)
    max_depth = Keyword.get(opts, :max_depth, 5)
    branching_factor = Keyword.get(opts, :branching_factor, 3)
    eval_threshold = Keyword.get(opts, :evaluation_threshold, 0.3)

    Logger.info("Starting Tree-of-Thought exploration for: #{problem}")
    Logger.info("Strategy: #{search_strategy}, Max depth: #{max_depth}, Branching: #{branching_factor}")

    start_time = System.monotonic_time(:millisecond)

    # Build exploration tree
    case TreeOfThought.explore(
      problem: problem,
      search_strategy: search_strategy,
      max_depth: max_depth,
      branching_factor: branching_factor,
      evaluation_fn: &evaluate_reasoning_quality/1,
      pruning_threshold: eval_threshold
    ) do
      {:ok, tree} ->
        execution_time = System.monotonic_time(:millisecond) - start_time

        result = %{
          solution_tree: tree,
          best_path: extract_best_path(tree),
          nodes_explored: count_nodes(tree),
          confidence: tree.best_score,
          alternatives: extract_alternatives(tree, 3),
          execution_time: execution_time,
          strategy_used: search_strategy
        }

        Logger.info("Exploration completed:")
        Logger.info("  Nodes explored: #{result.nodes_explored}")
        Logger.info("  Best score: #{Float.round(result.confidence, 2)}")
        Logger.info("  Time: #{execution_time}ms")

        {:ok, result}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Plan with multiple alternative strategies explored simultaneously.

  Generates several complete plans in parallel and evaluates them,
  returning the best plan along with viable alternatives.

  ## Parameters

  - `:goal` - High-level goal to achieve
  - `:constraints` - List of constraints or requirements
  - `:explore_alternatives` - Number of alternative strategies to explore (default: 3)
  - `:evaluation_criteria` - Criteria for ranking plans

  ## Returns

  - `{:ok, result}` with:
    - `:alternative_plans` - List of complete plans with scores
    - `:recommended_plan` - Best plan identified
    - `:comparison` - Side-by-side comparison
    - `:reasoning` - Why this plan was chosen

  ## Examples

      {:ok, result} = plan_with_alternatives(
        goal: "Reduce customer churn by 30%",
        constraints: ["3 month timeline", "existing team"],
        explore_alternatives: 5,
        evaluation_criteria: ["effectiveness", "feasibility", "cost"]
      )

      Enum.each(result.alternative_plans, fn {score, plan} ->
        IO.puts("\nPlan (Score: \#{score}):")
        IO.puts(plan.strategy)
      end)

      IO.puts("\nRecommended: \#{result.recommended_plan.strategy}")
  """
  @spec plan_with_alternatives(keyword()) :: {:ok, map()} | {:error, term()}
  def plan_with_alternatives(opts) do
    goal = Keyword.fetch!(opts, :goal)
    constraints = Keyword.get(opts, :constraints, [])
    num_alternatives = Keyword.get(opts, :explore_alternatives, 3)
    criteria = Keyword.get(opts, :evaluation_criteria, ["effectiveness", "feasibility", "cost"])

    Logger.info("Planning with #{num_alternatives} alternative strategies for: #{goal}")

    prompt = """
    Goal: #{goal}

    Constraints:
    #{Enum.map_join(constraints, "\n", fn c -> "- #{c}" end)}

    Evaluation Criteria:
    #{Enum.map_join(criteria, "\n", fn c -> "- #{c}" end)}

    Using Tree-of-Thought, explore #{num_alternatives} different strategic approaches:

    For each alternative strategy:
    1. Define the high-level approach
    2. Break down into concrete steps
    3. Identify key success factors
    4. Assess risks and mitigation
    5. Estimate timeline and resources

    Then evaluate each strategy against the criteria and recommend the best one.
    """

    case TreeOfThought.explore_alternatives(
      prompt: prompt,
      num_alternatives: num_alternatives,
      evaluation_criteria: criteria
    ) do
      {:ok, alternatives} ->
        # Rank and select best
        ranked = Enum.sort_by(alternatives, fn alt -> alt.score end, :desc)
        best = List.first(ranked)

        result = %{
          alternative_plans: Enum.map(ranked, fn alt -> {alt.score, alt.plan} end),
          recommended_plan: best.plan,
          comparison: build_comparison_matrix(ranked, criteria),
          reasoning: best.reasoning
        }

        Logger.info("Generated #{length(ranked)} alternative plans")
        Logger.info("Best plan score: #{Float.round(best.score, 2)}")

        {:ok, result}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Solve a problem step-by-step, evaluating multiple options at each step.

  At each decision point, ToT explores multiple possibilities, evaluates them,
  and chooses the best path forward. Can backtrack if a path proves unfruitful.

  ## Parameters

  - `:problem` - Problem to solve
  - `:max_steps` - Maximum steps in solution (default: 10)
  - `:backtrack_enabled` - Allow backtracking from poor choices (default: true)

  ## Returns

  - `{:ok, result}` with:
    - `:solution_steps` - Chosen solution path
    - `:decision_points` - Where alternatives were considered
    - `:backtrack_count` - Number of backtracks performed
    - `:total_paths_explored` - Total reasoning paths evaluated

  ## Examples

      {:ok, result} = solve_step_by_step(
        problem: "Design a distributed caching system",
        max_steps: 8,
        backtrack_enabled: true
      )

      IO.puts("Solution:")
      Enum.each(result.solution_steps, fn {step_num, description, score} ->
        IO.puts("\#{step_num}. \#{description} (score: \#{score})")
      end)

      IO.puts("\nBacktracked #{result.backtrack_count} times")
  """
  @spec solve_step_by_step(keyword()) :: {:ok, map()} | {:error, term()}
  def solve_step_by_step(opts) do
    problem = Keyword.fetch!(opts, :problem)
    max_steps = Keyword.get(opts, :max_steps, 10)
    backtrack_enabled = Keyword.get(opts, :backtrack_enabled, true)

    Logger.info("Solving step-by-step with Tree-of-Thought: #{problem}")

    case TreeOfThought.solve_iteratively(
      problem: problem,
      max_steps: max_steps,
      allow_backtracking: backtrack_enabled,
      step_evaluation_fn: &evaluate_step_quality/1
    ) do
      {:ok, solution} ->
        result = %{
          solution_steps: solution.steps,
          decision_points: solution.decision_points,
          backtrack_count: solution.backtracks_performed,
          total_paths_explored: solution.paths_explored,
          final_score: solution.quality_score
        }

        Logger.info("Solution found in #{length(solution.steps)} steps")
        Logger.info("Explored #{solution.paths_explored} paths, backtracked #{solution.backtracks_performed} times")

        {:ok, result}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Compare Chain-of-Thought vs Tree-of-Thought for the same problem.

  Runs both approaches and compares solution quality, exploration depth,
  and computational cost.

  ## Parameters

  - `:problem` - Problem to solve with both methods

  ## Returns

  - `{:ok, comparison}` with:
    - `:cot_result` - Chain-of-Thought result
    - `:tot_result` - Tree-of-Thought result
    - `:quality_difference` - Solution quality comparison
    - `:cost_difference` - Computational cost comparison
    - `:recommendation` - Which approach is better for this problem

  ## Examples

      {:ok, comp} = compare_cot_vs_tot(
        problem: "Optimize delivery routes for 10 locations"
      )

      IO.puts("Chain-of-Thought:")
      IO.puts("  Solution quality: \#{comp.cot_result.quality}")
      IO.puts("  Time: \#{comp.cot_result.time}ms")

      IO.puts("\nTree-of-Thought:")
      IO.puts("  Solution quality: \#{comp.tot_result.quality}")
      IO.puts("  Paths explored: \#{comp.tot_result.paths_explored}")
      IO.puts("  Time: \#{comp.tot_result.time}ms")

      IO.puts("\nRecommendation: \#{comp.recommendation}")
  """
  @spec compare_cot_vs_tot(keyword()) :: {:ok, map()} | {:error, term()}
  def compare_cot_vs_tot(opts) do
    problem = Keyword.fetch!(opts, :problem)

    Logger.info("Comparing CoT vs ToT for: #{problem}")

    # Run Chain-of-Thought
    cot_start = System.monotonic_time(:millisecond)
    {:ok, cot_result} = Examples.ChainOfThoughtExample.solve_with_reasoning(
      problem: problem,
      use_cot: true
    )
    cot_time = System.monotonic_time(:millisecond) - cot_start

    # Run Tree-of-Thought
    tot_start = System.monotonic_time(:millisecond)
    {:ok, tot_result} = solve_with_tree_search(
      problem: problem,
      search_strategy: :best_first,
      max_depth: 4
    )
    tot_time = System.monotonic_time(:millisecond) - tot_start

    # Compare
    quality_diff = tot_result.confidence - cot_result.confidence
    cost_multiplier = tot_time / max(cot_time, 1)

    recommendation = cond do
      quality_diff > 0.1 -> :use_tot  # Significantly better quality
      quality_diff < -0.05 -> :use_cot  # CoT is actually better
      cost_multiplier > 5 -> :use_cot  # ToT too expensive for marginal gain
      true -> :use_tot  # Slightly better, worth the cost
    end

    comparison = %{
      problem: problem,
      cot_result: %{
        answer: cot_result.answer,
        quality: cot_result.confidence,
        time: cot_time,
        approach: "Single reasoning path"
      },
      tot_result: %{
        best_path: tot_result.best_path,
        quality: tot_result.confidence,
        paths_explored: tot_result.nodes_explored,
        time: tot_time,
        approach: "Multiple paths explored"
      },
      quality_difference: Float.round(quality_diff * 100, 1),  # Percentage
      cost_multiplier: Float.round(cost_multiplier, 1),
      recommendation: recommendation,
      reasoning: explain_recommendation(recommendation, quality_diff, cost_multiplier)
    }

    Logger.info("Comparison complete:")
    Logger.info("  Quality improvement: #{comparison.quality_difference}%")
    Logger.info("  Cost multiplier: #{comparison.cost_multiplier}x")
    Logger.info("  Recommendation: #{recommendation}")

    {:ok, comparison}
  end

  @doc """
  Visualize the exploration tree showing all paths considered.

  Prints a tree visualization showing the reasoning exploration,
  with scores and pruned branches marked.

  ## Examples

      {:ok, result} = solve_with_tree_search(
        problem: "Find optimal algorithm",
        search_strategy: :best_first
      )

      visualize_tree(result.solution_tree)

      # Output:
      # Root: "Find optimal algorithm"
      # ├─ [0.85] "Use sorting-based approach"
      # │  ├─ [0.90] "Quick sort with optimization" ⭐ BEST
      # │  ├─ [0.75] "Merge sort"
      # │  └─ [0.60] "Bubble sort" ✗ PRUNED
      # ├─ [0.70] "Use hash-based approach"
      # │  └─ [0.72] "Hash map with caching"
      # └─ [0.40] "Brute force" ✗ PRUNED
  """
  @spec visualize_tree(map()) :: :ok
  def visualize_tree(tree) do
    IO.puts("\n=== Tree-of-Thought Exploration ===\n")
    print_node(tree, "", true)
    IO.puts("")
    :ok
  end

  # Private helper functions

  defp evaluate_reasoning_quality(reasoning_step) do
    # In real implementation, would use LLM or heuristics to score
    # For example: logical consistency, completeness, feasibility
    base_score = 0.7

    # Simulate evaluation factors
    length_bonus = min(String.length(reasoning_step) / 500, 0.2)
    randomness = :rand.uniform() * 0.1

    min(base_score + length_bonus + randomness, 1.0)
  end

  defp evaluate_step_quality(step) do
    # Evaluate quality of a single step
    # Higher scores for concrete, actionable steps
    case step do
      %{type: :concrete_action} -> 0.8 + :rand.uniform() * 0.15
      %{type: :analysis} -> 0.7 + :rand.uniform() * 0.15
      %{type: :vague_idea} -> 0.4 + :rand.uniform() * 0.2
      _ -> 0.6 + :rand.uniform() * 0.2
    end
  end

  defp extract_best_path(tree) do
    # Traverse tree to find highest-scoring path
    case tree.best_child do
      nil -> [tree.content]
      child -> [tree.content | extract_best_path(child)]
    end
  end

  defp count_nodes(tree) do
    children_count = tree.children
    |> Enum.map(&count_nodes/1)
    |> Enum.sum()

    1 + children_count
  end

  defp extract_alternatives(tree, n) do
    # Get top N alternative paths
    all_paths = collect_all_paths(tree)

    all_paths
    |> Enum.sort_by(fn {score, _path} -> score end, :desc)
    |> Enum.take(n)
  end

  defp collect_all_paths(tree, current_path \\ []) do
    current = {tree.score, current_path ++ [tree.content]}

    if Enum.empty?(tree.children) do
      [current]
    else
      child_paths = Enum.flat_map(tree.children, fn child ->
        collect_all_paths(child, current_path ++ [tree.content])
      end)

      [current | child_paths]
    end
  end

  defp build_comparison_matrix(ranked_plans, criteria) do
    # Build comparison matrix showing how each plan scores on each criterion
    header = ["Plan" | criteria]

    rows = Enum.with_index(ranked_plans, 1)
    |> Enum.map(fn {plan, idx} ->
      scores = Enum.map(criteria, fn _criterion ->
        # Simulate criterion-specific scoring
        Float.round(plan.score * (0.8 + :rand.uniform() * 0.4), 2)
      end)

      ["Plan #{idx}" | scores]
    end)

    [header | rows]
  end

  defp explain_recommendation(:use_tot, quality_diff, _cost) when quality_diff > 0.1 do
    "Tree-of-Thought provides significantly better solution quality (+#{Float.round(quality_diff * 100, 1)}%). Worth the additional cost."
  end

  defp explain_recommendation(:use_cot, _quality_diff, cost) when cost > 5 do
    "Chain-of-Thought is sufficient. Tree-of-Thought is #{Float.round(cost, 1)}x more expensive without proportional quality gain."
  end

  defp explain_recommendation(:use_cot, quality_diff, _cost) when quality_diff < -0.05 do
    "Chain-of-Thought actually produces better results (#{Float.round(abs(quality_diff) * 100, 1)}% better). Use simpler approach."
  end

  defp explain_recommendation(:use_tot, _quality_diff, _cost) do
    "Tree-of-Thought provides better exploration and solution quality. Recommended for this problem complexity."
  end

  defp print_node(node, prefix, is_last) do
    # Print current node
    marker = if is_last, do: "└─ ", else: "├─ "
    score_display = "[#{Float.round(node.score, 2)}]"

    status = cond do
      node.is_best -> " ⭐ BEST"
      node.pruned -> " ✗ PRUNED"
      true -> ""
    end

    IO.puts("#{prefix}#{marker}#{score_display} \"#{node.content}\"#{status}")

    # Print children
    new_prefix = prefix <> (if is_last, do: "    ", else: "│   ")

    node.children
    |> Enum.with_index()
    |> Enum.each(fn {child, idx} ->
      is_last_child = idx == length(node.children) - 1
      print_node(child, new_prefix, is_last_child)
    end)
  end
end
