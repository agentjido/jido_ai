defmodule Jido.AI.Runner.TreeOfThoughts do
  @moduledoc """
  Tree-of-Thoughts (ToT) Chain-of-Thought implementation.

  Implements the ToT pattern that explores multiple reasoning branches
  with lookahead and backtracking. ToT provides dramatic accuracy improvements
  (+70% on Game of 24) but at significant cost (50-150x).

  ## Search Strategies

  - **BFS (Breadth-First)**: Explores level-by-level, prunes per level
  - **DFS (Depth-First)**: Explores deeply, backtracks, memory efficient
  - **Best-First**: Always expands highest-value node (like A*)

  ## Key Features

  - Systematic exploration of reasoning space
  - Thought evaluation guiding search
  - Pruning of low-value branches
  - Early termination on solution
  - Budget management preventing excessive search

  ## Usage

      {:ok, result} = TreeOfThoughts.run(
        problem: "Make 24 using 4, 5, 6, 6",
        search_strategy: :bfs,
        beam_width: 3,
        max_depth: 4,
        evaluation_strategy: :value
      )

      # => %{
      #   answer: "(6-4)*(6+5) = 2*12 = 24",
      #   solution_path: [thought1, thought2, thought3],
      #   tree_size: 47,
      #   search_steps: 15
      # }

  ## Research

  ToT shows dramatic improvements on planning and search tasks:
  - Game of 24: +74% success rate (4% → 74%)
  - Creative Writing: +20% quality score
  - Mini Crosswords: +60% solve rate

  Cost: 50-150x depending on tree size and evaluation strategy

  ## When to Use

  ✅ Critical accuracy tasks justifying high cost
  ✅ Problems requiring exhaustive exploration
  ✅ Planning tasks with multiple valid paths
  ✅ Complex algorithmic problems

  ❌ Simple queries (use basic CoT)
  ❌ Cost-sensitive applications
  ❌ Real-time requirements (<1s)
  """

  require Logger

  alias Jido.AI.Runner.TreeOfThoughts.{
    ThoughtEvaluator,
    ThoughtGenerator,
    Tree,
    TreeNode
  }

  @default_search_strategy :bfs
  @default_beam_width 3
  @default_max_depth 5
  @default_evaluation_strategy :value
  @default_budget 100

  @type result :: %{
          answer: String.t() | nil,
          success: boolean(),
          solution_path: list(TreeNode.t()),
          tree: Tree.t(),
          search_steps: non_neg_integer(),
          nodes_evaluated: non_neg_integer(),
          reason: atom(),
          metadata: map()
        }

  @doc """
  Runs Tree-of-Thoughts reasoning.

  ## Parameters

  - `opts` - Options:
    - `:problem` - Problem to solve (required)
    - `:initial_state` - Starting state (default: %{})
    - `:search_strategy` - Search strategy (:bfs, :dfs, :best_first)
    - `:beam_width` - Thoughts per node (default: 3)
    - `:max_depth` - Maximum tree depth (default: 5)
    - `:evaluation_strategy` - How to evaluate thoughts (:value, :vote, :heuristic, :hybrid)
    - `:budget` - Maximum nodes to evaluate (default: 100)
    - `:solution_check` - Function to check if node is solution
    - `:thought_fn` - Custom thought generation (for testing)
    - `:evaluation_fn` - Custom evaluation (for testing)

  ## Returns

  - `{:ok, result}` - Search completed
  - `{:error, reason}` - Search failed
  """
  @spec run(keyword()) :: {:ok, result()} | {:error, term()}
  def run(opts \\ []) do
    problem = Keyword.fetch!(opts, :problem)
    initial_state = Keyword.get(opts, :initial_state, %{})
    search_strategy = Keyword.get(opts, :search_strategy, @default_search_strategy)
    beam_width = Keyword.get(opts, :beam_width, @default_beam_width)
    max_depth = Keyword.get(opts, :max_depth, @default_max_depth)
    evaluation_strategy = Keyword.get(opts, :evaluation_strategy, @default_evaluation_strategy)
    budget = Keyword.get(opts, :budget, @default_budget)
    solution_check = Keyword.get(opts, :solution_check)
    thought_fn = Keyword.get(opts, :thought_fn)
    evaluation_fn = Keyword.get(opts, :evaluation_fn)

    Logger.info(
      "Starting ToT search: #{search_strategy}, beam_width: #{beam_width}, max_depth: #{max_depth}"
    )

    # Initialize tree with root
    tree = Tree.new("Problem: #{problem}", initial_state)

    # Initialize search state
    state = %{
      tree: tree,
      problem: problem,
      beam_width: beam_width,
      max_depth: max_depth,
      evaluation_strategy: evaluation_strategy,
      budget: budget,
      nodes_evaluated: 0,
      search_steps: 0,
      solution_check: solution_check,
      thought_fn: thought_fn,
      evaluation_fn: evaluation_fn
    }

    # Execute search based on strategy
    case search_strategy do
      :bfs -> execute_bfs(state)
      :dfs -> execute_dfs(state)
      :best_first -> execute_best_first(state)
      _ -> {:error, {:invalid_strategy, search_strategy}}
    end
  end

  # Private functions - BFS Search

  defp execute_bfs(state) do
    # BFS: Explore level by level, pruning at each level

    {:ok, root} = Tree.get_node(state.tree, state.tree.root_id)

    {final_state, result} = bfs_search(state, [root], %{found: false, solution: nil})

    build_result(final_state, result)
  end

  defp bfs_search(state, _frontier, %{found: true} = result) do
    # Solution found
    {state, result}
  end

  defp bfs_search(state, [], result) do
    # Frontier exhausted, no solution
    {state, Map.put(result, :reason, :frontier_exhausted)}
  end

  defp bfs_search(state, frontier, result) when state.nodes_evaluated >= state.budget do
    # Budget exhausted
    updated_result =
      result
      |> Map.put(:reason, :budget_exhausted)
      |> Map.put(:best_node, find_best_node(frontier))

    {state, updated_result}
  end

  defp bfs_search(state, frontier, result) do
    # Process current level
    # Check if any node is solution
    case find_solution_in_frontier(state, frontier) do
      {:found, solution_node} ->
        updated_result =
          Map.merge(result, %{found: true, solution: solution_node, reason: :solution_found})

        {state, updated_result}

      :not_found ->
        # Expand all nodes in frontier
        {new_state, new_frontier} = expand_frontier(state, frontier)

        # Continue to next level
        bfs_search(new_state, new_frontier, result)
    end
  end

  # Private functions - DFS Search

  defp execute_dfs(state) do
    {:ok, root} = Tree.get_node(state.tree, state.tree.root_id)

    {final_state, result} = dfs_search(state, root, %{found: false, solution: nil})

    build_result(final_state, result)
  end

  defp dfs_search(state, _node, %{found: true} = result) do
    # Solution found
    {state, result}
  end

  defp dfs_search(state, node, result) when state.nodes_evaluated >= state.budget do
    # Budget exhausted
    {state, Map.merge(result, %{reason: :budget_exhausted, best_node: node})}
  end

  defp dfs_search(state, node, result) when node.depth >= state.max_depth do
    # Max depth reached, backtrack
    {state, result}
  end

  defp dfs_search(state, node, result) do
    # Check if current node is solution
    if solution?(state, node) do
      {state, Map.merge(result, %{found: true, solution: node, reason: :solution_found})}
    else
      # Generate and evaluate children
      {new_state, children} = expand_node(state, node)

      # Recursively explore children (depth-first)
      explore_children_dfs(new_state, children, result)
    end
  end

  defp explore_children_dfs(state, [], result), do: {state, result}

  defp explore_children_dfs(state, [child | rest], result) do
    # Explore this child
    {new_state, child_result} = dfs_search(state, child, result)

    if child_result.found do
      {new_state, child_result}
    else
      # Continue with siblings
      explore_children_dfs(new_state, rest, child_result)
    end
  end

  # Private functions - Best-First Search

  defp execute_best_first(state) do
    {:ok, root} = Tree.get_node(state.tree, state.tree.root_id)

    # Priority queue (highest value first)
    frontier = [{root.value || 0.5, root}]

    {final_state, result} = best_first_search(state, frontier, %{found: false, solution: nil})

    build_result(final_state, result)
  end

  defp best_first_search(state, _frontier, %{found: true} = result) do
    {state, result}
  end

  defp best_first_search(state, [], result) do
    {state, Map.put(result, :reason, :frontier_exhausted)}
  end

  defp best_first_search(state, frontier, result) when state.nodes_evaluated >= state.budget do
    [{_value, best_node} | _] = frontier
    {state, Map.merge(result, %{reason: :budget_exhausted, best_node: best_node})}
  end

  defp best_first_search(state, frontier, result) do
    # Take highest-value node
    [{_value, node} | rest_frontier] = frontier

    if solution?(state, node) do
      {state, Map.merge(result, %{found: true, solution: node, reason: :solution_found})}
    else
      # Expand node
      {new_state, children} = expand_node(state, node)

      # Add children to frontier, re-sort
      new_frontier =
        (rest_frontier ++ Enum.map(children, fn c -> {c.value || 0.5, c} end))
        |> Enum.sort_by(fn {value, _node} -> value end, :desc)

      best_first_search(new_state, new_frontier, result)
    end
  end

  # Helper functions

  defp find_solution_in_frontier(state, frontier) do
    case Enum.find(frontier, &solution?(state, &1)) do
      nil -> :not_found
      node -> {:found, node}
    end
  end

  defp solution?(state, node) do
    if state.solution_check do
      state.solution_check.(node)
    else
      # Default: leaf node at sufficient depth with high value
      TreeNode.leaf?(node) && node.depth >= div(state.max_depth, 2) && (node.value || 0.0) > 0.8
    end
  end

  defp expand_frontier(state, frontier) do
    # Expand all nodes in current level, respecting budget
    Enum.reduce_while(frontier, {state, []}, fn node, {acc_state, acc_frontier} ->
      # Check if we're at budget before expanding
      if acc_state.nodes_evaluated >= acc_state.budget do
        {:halt, {acc_state, acc_frontier}}
      else
        {new_state, children} = expand_node(acc_state, node)

        # Check if expansion exceeded budget
        if new_state.nodes_evaluated >= new_state.budget do
          {:halt, {new_state, acc_frontier ++ children}}
        else
          {:cont, {new_state, acc_frontier ++ children}}
        end
      end
    end)
  end

  defp expand_node(state, node) do
    # Don't expand beyond max depth or budget
    cond do
      node.depth >= state.max_depth ->
        {state, []}

      state.nodes_evaluated >= state.budget ->
        {state, []}

      true ->
        # Generate thoughts
        {:ok, thoughts} =
          ThoughtGenerator.generate(
            problem: state.problem,
            parent_state: node.state,
            beam_width: state.beam_width,
            depth: node.depth,
            tree_size: state.tree.size,
            thought_fn: state.thought_fn
          )

        # Evaluate thoughts
        {:ok, scores} =
          ThoughtEvaluator.evaluate_batch(
            thoughts,
            problem: state.problem,
            state: node.state,
            strategy: state.evaluation_strategy,
            evaluation_fn: state.evaluation_fn
          )

        # Limit thoughts to remaining budget
        remaining_budget = state.budget - state.nodes_evaluated

        limited_thoughts_scores =
          thoughts
          |> Enum.zip(scores)
          |> Enum.take(remaining_budget)

        # Create child nodes
        {new_tree, children} =
          limited_thoughts_scores
          |> Enum.reduce({state.tree, []}, fn {thought, score}, {acc_tree, acc_children} ->
            {:ok, {updated_tree, child}} =
              Tree.add_child(acc_tree, node.id, thought, %{score: score})

            child_with_value = TreeNode.set_value(child, score)
            final_tree = Tree.update_node(updated_tree, child_with_value)

            {final_tree, [child_with_value | acc_children]}
          end)

        new_state = %{
          state
          | tree: new_tree,
            nodes_evaluated: state.nodes_evaluated + length(children),
            search_steps: state.search_steps + 1
        }

        {new_state, Enum.reverse(children)}
    end
  end

  defp find_best_node(frontier) do
    Enum.max_by(frontier, &(&1.value || 0.0), fn -> List.first(frontier) end)
  end

  defp build_result(state, search_result) do
    solution_node = search_result[:solution] || search_result[:best_node]

    solution_path =
      if solution_node do
        Tree.get_path(state.tree, solution_node.id)
      else
        []
      end

    answer =
      if solution_node do
        extract_answer(solution_node)
      else
        nil
      end

    result = %{
      answer: answer,
      success: search_result[:found] || false,
      solution_path: solution_path,
      tree: state.tree,
      search_steps: state.search_steps,
      nodes_evaluated: state.nodes_evaluated,
      reason: search_result[:reason] || :unknown,
      metadata: %{
        tree_size: state.tree.size,
        max_depth_reached: state.tree.max_depth,
        budget: state.budget,
        budget_used: state.nodes_evaluated
      }
    }

    {:ok, result}
  end

  defp extract_answer(node) do
    # Extract answer from solution node
    # Could be in thought or state
    if Map.has_key?(node.state, :answer) do
      node.state.answer
    else
      node.thought
    end
  end
end
