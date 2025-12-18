defmodule Examples.TreeOfThoughts.GameOf24 do
  @moduledoc """
  Basic Tree-of-Thoughts example demonstrating the Game of 24.

  This example shows how ToT explores multiple reasoning paths simultaneously
  through tree-structured search to solve mathematical puzzles.

  ## The Game of 24

  Given 4 numbers, use arithmetic operations (+, -, *, /) to make 24.
  Example: Given [4, 5, 6, 6], one solution is (6 - 4) * (6 + 6) = 24

  ## Usage

      # Run the example
      Examples.TreeOfThoughts.GameOf24.run()

      # Solve a custom problem
      Examples.TreeOfThoughts.GameOf24.solve([3, 3, 8, 8])

      # Compare with CoT
      Examples.TreeOfThoughts.GameOf24.compare_with_cot()

  ## Features

  - Tree-based exploration with multiple paths
  - Backtracking from dead ends
  - Thought evaluation and pruning
  - Complete solution path tracking
  - Tree visualization
  """

  require Logger

  @doc """
  Run the complete example with a sample Game of 24 problem.
  """
  def run do
    IO.puts("\n" <> String.duplicate("=", 70))
    IO.puts("  Tree-of-Thoughts: Game of 24")
    IO.puts(String.duplicate("=", 70) <> "\n")

    numbers = [4, 5, 6, 6]
    IO.puts("📝 **Problem:** Make 24 using #{inspect(numbers)}")
    IO.puts("🔧 **Operations:** +, -, *, /")
    IO.puts("🌳 **Strategy:** BFS with beam width 3\n")
    IO.puts(String.duplicate("-", 70) <> "\n")

    case solve(numbers) do
      {:ok, result} ->
        display_result(result)
        {:ok, result}

      {:error, reason} ->
        IO.puts("❌ **Error:** #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Solve a Game of 24 problem using Tree-of-Thoughts.

  ## Parameters

  - `numbers` - List of 4 numbers to use
  - `opts` - Options (search_strategy, beam_width, max_depth, budget)

  ## Returns

  - `{:ok, result}` - Success with solution and tree
  - `{:error, reason}` - Failure reason
  """
  def solve(numbers, opts \\ []) do
    search_strategy = Keyword.get(opts, :search_strategy, :bfs)
    beam_width = Keyword.get(opts, :beam_width, 3)
    max_depth = Keyword.get(opts, :max_depth, 4)
    budget = Keyword.get(opts, :budget, 50)

    # Initialize tree
    tree = initialize_tree(numbers)

    # Run tree search
    state = %{
      tree: tree,
      frontier: [tree.root_id],
      solution_id: nil,
      nodes_evaluated: 0,
      search_strategy: search_strategy,
      beam_width: beam_width,
      max_depth: max_depth,
      budget: budget,
      numbers: numbers
    }

    run_tree_search(state)
  end

  # Tree Structure

  defmodule TreeNode do
    @moduledoc false
    defstruct [
      :id,
      :thought,
      :state,
      :value,
      :depth,
      :parent_id,
      children_ids: [],
      metadata: %{}
    ]
  end

  defmodule Tree do
    @moduledoc false
    defstruct [
      :root_id,
      nodes: %{},
      edges: %{},
      size: 0,
      max_depth: 0
    ]

    def get_node(tree, node_id) do
      case Map.get(tree.nodes, node_id) do
        nil -> {:error, :node_not_found}
        node -> {:ok, node}
      end
    end

    def get_path(tree, node_id) do
      case get_node(tree, node_id) do
        {:ok, node} ->
          build_path(tree, node, [])

        {:error, _} = error ->
          error
      end
    end

    defp build_path(_tree, %{parent_id: nil} = node, acc) do
      [node | acc]
    end

    defp build_path(tree, node, acc) do
      {:ok, parent} = get_node(tree, node.parent_id)
      build_path(tree, parent, [node | acc])
    end

    def add_child(tree, parent_id, thought, state, value) do
      child_id = "node_#{tree.size + 1}"

      child = %TreeNode{
        id: child_id,
        thought: thought,
        state: state,
        value: value,
        depth: state.depth,
        parent_id: parent_id
      }

      updated_tree = %{
        tree
        | nodes: Map.put(tree.nodes, child_id, child),
          edges: Map.update(tree.edges, parent_id, [child_id], &(&1 ++ [child_id])),
          size: tree.size + 1,
          max_depth: max(tree.max_depth, state.depth)
      }

      {:ok, {updated_tree, child}}
    end
  end

  # Tree Search Implementation

  defp initialize_tree(numbers) do
    root_id = "node_1"

    root = %TreeNode{
      id: root_id,
      thought: "Start: Available numbers #{inspect(numbers)}",
      state: %{
        numbers_available: numbers,
        numbers_used: [],
        operations: [],
        intermediate_results: [],
        depth: 0
      },
      value: 1.0,
      depth: 0,
      parent_id: nil
    }

    %Tree{
      root_id: root_id,
      nodes: %{root_id => root},
      edges: %{},
      size: 1,
      max_depth: 0
    }
  end

  defp run_tree_search(state) do
    cond do
      # Found solution
      state.solution_id != nil ->
        {:ok, finalize_result(state, :solution_found)}

      # Budget exhausted
      state.nodes_evaluated >= state.budget ->
        {:ok, finalize_result(state, :budget_exhausted)}

      # Frontier exhausted
      Enum.empty?(state.frontier) ->
        {:ok, finalize_result(state, :frontier_exhausted)}

      true ->
        # Expand next node
        case expand_next_node(state) do
          {:ok, new_state} -> run_tree_search(new_state)
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp expand_next_node(state) do
    # Get next node to expand based on strategy
    {node_id, remaining_frontier} = select_next_node(state)

    {:ok, node} = Tree.get_node(state.tree, node_id)

    # Check if this node is a solution
    if is_solution?(node) do
      {:ok, %{state | solution_id: node_id, nodes_evaluated: state.nodes_evaluated + 1}}
    else
      # Generate thoughts for this node
      thoughts = generate_thoughts(node, state)

      # Evaluate thoughts
      evaluated_thoughts = evaluate_thoughts(thoughts, node, state)

      # Add best thoughts as children
      {new_tree, new_frontier} =
        add_children(state.tree, node, evaluated_thoughts, remaining_frontier, state)

      {:ok,
       %{
         state
         | tree: new_tree,
           frontier: new_frontier,
           nodes_evaluated: state.nodes_evaluated + 1
       }}
    end
  end

  defp select_next_node(state) do
    case state.search_strategy do
      :bfs ->
        # Breadth-first: take from front
        [node_id | rest] = state.frontier
        {node_id, rest}

      :dfs ->
        # Depth-first: take from back
        {node_id, rest} = List.pop_at(state.frontier, -1)
        {node_id, rest}

      :best_first ->
        # Best-first: take highest value
        best_id =
          Enum.max_by(state.frontier, fn id ->
            {:ok, node} = Tree.get_node(state.tree, id)
            node.value || 0.0
          end)

        {best_id, List.delete(state.frontier, best_id)}
    end
  end

  defp is_solution?(node) do
    # Check if we've reached 24
    state = node.state

    case state.intermediate_results do
      [24] when length(state.numbers_used) == 4 ->
        true

      [result] when length(state.numbers_used) == 4 and abs(result - 24) < 0.001 ->
        true

      _ ->
        false
    end
  end

  # Thought Generation

  defp generate_thoughts(node, state) do
    parent_state = node.state
    available = parent_state.numbers_available
    intermediates = parent_state.intermediate_results

    # All values we can work with (available numbers + intermediate results)
    all_values = available ++ intermediates

    # Generate possible operations
    thoughts =
      for i <- 0..(length(all_values) - 1),
          j <- (i + 1)..(length(all_values) - 1) do
        a = Enum.at(all_values, i)
        b = Enum.at(all_values, j)

        [
          generate_operation_thought(a, b, :add, parent_state),
          generate_operation_thought(a, b, :subtract, parent_state),
          generate_operation_thought(b, a, :subtract, parent_state),
          generate_operation_thought(a, b, :multiply, parent_state),
          generate_operation_thought(a, b, :divide, parent_state),
          generate_operation_thought(b, a, :divide, parent_state)
        ]
      end
      |> List.flatten()
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq_by(fn t -> t.result end)

    # Take top beam_width thoughts
    Enum.take(thoughts, state.beam_width)
  end

  defp generate_operation_thought(a, b, op, parent_state) do
    {op_symbol, result} =
      case op do
        :add -> {"+", a + b}
        :subtract -> {"-", a - b}
        :multiply -> {"*", a * b}
        :divide when b != 0 and rem(trunc(a * 100), trunc(b * 100)) == 0 -> {"/", a / b}
        :divide when b != 0 -> {"/", a / b}
        :divide -> {nil, nil}
      end

    if op_symbol do
      # Build new state
      all_values = parent_state.numbers_available ++ parent_state.intermediate_results
      remaining = List.delete(List.delete(all_values, a), b)
      new_intermediates = [result | List.delete(parent_state.intermediate_results, a) |> List.delete(b)]

      new_state = %{
        numbers_available: Enum.filter(remaining, fn v -> v in parent_state.numbers_available end),
        numbers_used:
          parent_state.numbers_used ++
            Enum.filter([a, b], fn v -> v in parent_state.numbers_available end),
        operations: parent_state.operations ++ ["#{a} #{op_symbol} #{b}"],
        intermediate_results: new_intermediates,
        depth: parent_state.depth + 1,
        last_result: result
      }

      %{
        thought: "#{a} #{op_symbol} #{b} = #{format_number(result)}",
        state: new_state,
        result: result
      }
    else
      nil
    end
  end

  defp format_number(n) when is_float(n) do
    if n == Float.round(n, 0), do: trunc(n), else: Float.round(n, 2)
  end

  defp format_number(n), do: n

  # Thought Evaluation

  defp evaluate_thoughts(thoughts, _node, state) do
    # Evaluate each thought
    thoughts
    |> Enum.map(fn thought ->
      value = evaluate_thought(thought, state)
      Map.put(thought, :value, value)
    end)
    |> Enum.sort_by(fn t -> -t.value end)
    |> Enum.take(state.beam_width)
  end

  defp evaluate_thought(thought, _state) do
    result = thought.state.last_result
    numbers_used = length(thought.state.numbers_used)
    operations_count = length(thought.state.operations)

    # Heuristic evaluation
    # Higher score for:
    # - Results closer to 24
    # - More numbers used
    # - Reasonable intermediate values

    closeness_score =
      cond do
        result == 24 -> 1.0
        abs(result - 24) < 5 -> 0.8
        abs(result - 24) < 10 -> 0.6
        abs(result - 24) < 20 -> 0.4
        true -> 0.2
      end

    progress_score = numbers_used / 4.0

    # Prefer intermediate values that could lead to 24
    feasibility_score =
      cond do
        result <= 0 -> 0.1
        result > 100 -> 0.3
        result >= 1 and result <= 48 -> 0.8
        true -> 0.5
      end

    # Weighted combination
    0.4 * closeness_score + 0.4 * progress_score + 0.2 * feasibility_score
  end

  # Tree Building

  defp add_children(tree, parent_node, thoughts, frontier, state) do
    {new_tree, new_nodes} =
      Enum.reduce(thoughts, {tree, []}, fn thought, {acc_tree, acc_nodes} ->
        {:ok, {updated_tree, child}} =
          Tree.add_child(
            acc_tree,
            parent_node.id,
            thought.thought,
            thought.state,
            thought.value
          )

        {updated_tree, [child.id | acc_nodes]}
      end)

    # Add new nodes to frontier based on strategy
    new_frontier =
      case state.search_strategy do
        :bfs -> frontier ++ Enum.reverse(new_nodes)
        :dfs -> Enum.reverse(new_nodes) ++ frontier
        :best_first -> frontier ++ Enum.reverse(new_nodes)
      end

    {new_tree, new_frontier}
  end

  # Result Handling

  defp finalize_result(state, reason) do
    solution_path =
      if state.solution_id do
        case Tree.get_path(state.tree, state.solution_id) do
          path when is_list(path) -> path
          _ -> []
        end
      else
        []
      end

    answer =
      if state.solution_id do
        {:ok, solution_node} = Tree.get_node(state.tree, state.solution_id)
        format_solution(solution_node)
      else
        nil
      end

    %{
      success: state.solution_id != nil,
      answer: answer,
      solution_path: solution_path,
      tree: state.tree,
      nodes_evaluated: state.nodes_evaluated,
      reason: reason,
      metadata: %{
        tree_size: state.tree.size,
        max_depth: state.tree.max_depth,
        budget: state.budget,
        search_strategy: state.search_strategy,
        beam_width: state.beam_width
      }
    }
  end

  defp format_solution(node) do
    operations = node.state.operations
    result = hd(node.state.intermediate_results)

    "#{Enum.join(operations, ", ")} = #{result}"
  end

  # Display Functions

  defp display_result(result) do
    IO.puts(String.duplicate("=", 70))
    IO.puts("\n✅ **Tree Search Complete**\n")

    IO.puts("📊 **Results:**")
    IO.puts("   • Success: #{result.success}")
    IO.puts("   • Nodes evaluated: #{result.nodes_evaluated}")
    IO.puts("   • Tree size: #{result.metadata.tree_size}")
    IO.puts("   • Max depth: #{result.metadata.max_depth}")
    IO.puts("   • Search strategy: #{result.metadata.search_strategy}")

    if result.success do
      IO.puts("\n🎯 **Solution Found:**")
      IO.puts("   #{result.answer}")

      IO.puts("\n📜 **Solution Path:**")

      result.solution_path
      |> Enum.with_index(1)
      |> Enum.each(fn {node, idx} ->
        indent = String.duplicate("  ", node.depth)
        value_str = if node.value, do: " (#{Float.round(node.value, 2)})", else: ""
        IO.puts("   #{idx}. #{indent}#{node.thought}#{value_str}")
      end)
    else
      IO.puts("\n❌ **No Solution Found**")
      IO.puts("   Reason: #{result.reason}")

      # Show best attempt
      best_node = find_best_leaf(result.tree)

      if best_node do
        IO.puts("\n🔍 **Best Attempt:**")
        path = Tree.get_path(result.tree, best_node.id)

        Enum.each(path, fn node ->
          IO.puts("   • #{node.thought}")
        end)
      end
    end

    IO.puts("\n" <> String.duplicate("=", 70))
  end

  defp find_best_leaf(tree) do
    tree.nodes
    |> Map.values()
    |> Enum.filter(fn node ->
      # Leaf nodes (no children)
      children = Map.get(tree.edges, node.id, [])
      Enum.empty?(children)
    end)
    |> Enum.max_by(fn node -> node.value || 0.0 end, fn -> nil end)
  end

  @doc """
  Compare Tree-of-Thoughts with Chain-of-Thought.
  """
  def compare_with_cot do
    IO.puts("\n" <> String.duplicate("=", 70))
    IO.puts("  Comparison: Chain-of-Thought vs Tree-of-Thoughts")
    IO.puts(String.duplicate("=", 70) <> "\n")

    numbers = [4, 5, 6, 6]
    IO.puts("**Problem:** Make 24 using #{inspect(numbers)}\n")

    IO.puts("**Chain-of-Thought (Single Path):**")
    IO.puts("   1. Try 6 + 6 = 12")
    IO.puts("   2. Try 12 + 4 = 16")
    IO.puts("   3. Try 16 + 5 = 21")
    IO.puts("   4. ❌ Failed - only one path explored")
    IO.puts("   Result: No solution (greedy approach failed)")

    IO.puts("\n**Tree-of-Thoughts (Multiple Paths):**")

    {:ok, result} = solve(numbers, beam_width: 3, max_depth: 4)

    if result.success do
      IO.puts("   ✓ Explored #{result.nodes_evaluated} paths")
      IO.puts("   ✓ Found solution: #{result.answer}")
      IO.puts("   ✓ Can backtrack from dead ends")
    else
      IO.puts("   Explored #{result.nodes_evaluated} paths")
    end

    IO.puts("\n**Key Differences:**")
    IO.puts("   • CoT: Single greedy path, fast but may fail")
    IO.puts("   • ToT: Multiple paths, systematic exploration, higher success rate")
    IO.puts("   • ToT Cost: ~50-100× more expensive")
    IO.puts("   • ToT Best For: Problems where greedy approach fails")
  end

  @doc """
  Solve multiple Game of 24 problems.
  """
  def batch_solve(problems \\\\ nil) do
    default_problems = [
      [4, 5, 6, 6],
      [1, 2, 3, 4],
      [3, 3, 8, 8]
    ]

    problems_to_solve = problems || default_problems

    IO.puts("\n" <> String.duplicate("=", 70))
    IO.puts("  Batch Game of 24 Solving")
    IO.puts(String.duplicate("=", 70) <> "\n")

    results =
      Enum.map(problems_to_solve, fn numbers ->
        IO.puts("Problem: Make 24 using #{inspect(numbers)}")

        case solve(numbers, budget: 50) do
          {:ok, result} ->
            if result.success do
              IO.puts("✓ Solution: #{result.answer}")
              IO.puts("  Nodes: #{result.nodes_evaluated}")
            else
              IO.puts("✗ No solution found")
              IO.puts("  Nodes: #{result.nodes_evaluated}")
            end

            IO.puts("")
            result

          {:error, reason} ->
            IO.puts("✗ Error: #{inspect(reason)}\n")
            nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    success_count = Enum.count(results, fn r -> r.success end)
    IO.puts("Solved #{success_count}/#{length(problems_to_solve)} problems")

    avg_nodes =
      if length(results) > 0 do
        results
        |> Enum.map(& &1.nodes_evaluated)
        |> Enum.sum()
        |> Kernel./(length(results))
        |> Float.round(1)
      else
        0.0
      end

    IO.puts("Average nodes evaluated: #{avg_nodes}")

    {:ok, results}
  end
end
