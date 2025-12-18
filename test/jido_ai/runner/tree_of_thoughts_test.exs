defmodule Jido.AI.Runner.TreeOfThoughtsTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Runner.TreeOfThoughts
  alias Jido.AI.Runner.TreeOfThoughts.{ThoughtEvaluator, ThoughtGenerator, Tree, TreeNode}

  # =============================================================================
  # TreeNode Tests
  # =============================================================================

  describe "TreeNode" do
    test "creates new node with required fields" do
      node = TreeNode.new("Test thought", %{key: "value"})

      assert node.thought == "Test thought"
      assert node.state == %{key: "value"}
      assert node.depth == 0
      assert node.parent_id == nil
      assert node.children_ids == []
      assert is_binary(node.id)
    end

    test "creates child node with parent reference" do
      parent = TreeNode.new("Parent", %{})
      child = TreeNode.new("Child", %{}, parent_id: parent.id)

      assert child.parent_id == parent.id
      assert child.depth == 1
    end

    test "sets value for node" do
      node = TreeNode.new("Test", %{})
      updated = TreeNode.set_value(node, 0.85)

      assert updated.value == 0.85
    end

    test "increments visit count" do
      node = TreeNode.new("Test", %{})
      assert node.visits == 0

      updated = TreeNode.increment_visits(node)
      assert updated.visits == 1
    end

    test "adds child to node" do
      parent = TreeNode.new("Parent", %{})
      child_id = "child_123"

      updated = TreeNode.add_child(parent, child_id)
      assert child_id in updated.children_ids
    end

    test "identifies leaf nodes" do
      leaf = TreeNode.new("Leaf", %{})
      assert TreeNode.leaf?(leaf)

      parent = TreeNode.add_child(leaf, "child_id")
      refute TreeNode.leaf?(parent)
    end

    test "identifies root nodes" do
      root = TreeNode.new("Root", %{})
      assert TreeNode.root?(root)

      child = TreeNode.new("Child", %{}, parent_id: "parent_id")
      refute TreeNode.root?(child)
    end

    test "calculates UCT score" do
      node = TreeNode.new("Test", %{})
      node = TreeNode.set_value(node, 0.7)
      node = TreeNode.increment_visits(node)

      score = TreeNode.uct_score(node, 10)
      assert is_float(score)
      assert score > 0
    end

    test "gives infinite UCT to unvisited nodes" do
      node = TreeNode.new("Test", %{})
      score = TreeNode.uct_score(node, 10)
      assert score == :infinity
    end
  end

  # =============================================================================
  # Tree Tests
  # =============================================================================

  describe "Tree" do
    test "creates new tree with root" do
      tree = Tree.new("Root thought", %{initial: true})

      assert tree.root_id != nil
      assert tree.size == 1
      assert tree.max_depth == 0
      assert map_size(tree.nodes) == 1
    end

    test "adds child to tree" do
      tree = Tree.new("Root", %{})
      {:ok, {updated_tree, child}} = Tree.add_child(tree, tree.root_id, "Child thought", %{})

      assert updated_tree.size == 2
      assert child.parent_id == tree.root_id
      assert child.depth == 1
    end

    test "gets node by ID" do
      tree = Tree.new("Root", %{})
      {:ok, node} = Tree.get_node(tree, tree.root_id)

      assert node.thought == "Root"
    end

    test "returns error for non-existent node" do
      tree = Tree.new("Root", %{})
      assert {:error, :not_found} = Tree.get_node(tree, "nonexistent")
    end

    test "updates node in tree" do
      tree = Tree.new("Root", %{})
      {:ok, node} = Tree.get_node(tree, tree.root_id)

      updated_node = TreeNode.set_value(node, 0.95)
      updated_tree = Tree.update_node(tree, updated_node)

      {:ok, retrieved} = Tree.get_node(updated_tree, tree.root_id)
      assert retrieved.value == 0.95
    end

    test "gets children of node" do
      tree = Tree.new("Root", %{})
      {:ok, {tree, child1}} = Tree.add_child(tree, tree.root_id, "Child 1", %{})
      {:ok, {tree, _child2}} = Tree.add_child(tree, tree.root_id, "Child 2", %{})

      children = Tree.get_children(tree, tree.root_id)
      assert length(children) == 2
      assert Enum.any?(children, &(&1.id == child1.id))
    end

    test "gets parent of node" do
      tree = Tree.new("Root", %{})
      {:ok, {tree, child}} = Tree.add_child(tree, tree.root_id, "Child", %{})

      {:ok, parent} = Tree.get_parent(tree, child.id)
      assert parent.id == tree.root_id
    end

    test "returns error for parent of root" do
      tree = Tree.new("Root", %{})
      assert {:error, :no_parent} = Tree.get_parent(tree, tree.root_id)
    end

    test "gets path from root to node" do
      tree = Tree.new("Root", %{})
      {:ok, {tree, child}} = Tree.add_child(tree, tree.root_id, "Child", %{})
      {:ok, {tree, grandchild}} = Tree.add_child(tree, child.id, "Grandchild", %{})

      path = Tree.get_path(tree, grandchild.id)
      assert length(path) == 3
      assert List.first(path).id == tree.root_id
      assert List.last(path).id == grandchild.id
    end

    test "performs BFS traversal" do
      tree = Tree.new("Root", %{})
      {:ok, {tree, c1}} = Tree.add_child(tree, tree.root_id, "C1", %{})
      {:ok, {tree, c2}} = Tree.add_child(tree, tree.root_id, "C2", %{})
      {:ok, {tree, gc1}} = Tree.add_child(tree, c1.id, "GC1", %{})

      nodes = Tree.bfs(tree)
      assert length(nodes) == 4

      # BFS should visit root, then c1 and c2, then gc1
      [n1, n2, n3, n4] = nodes
      assert n1.id == tree.root_id
      assert n2.id in [c1.id, c2.id]
      assert n3.id in [c1.id, c2.id]
      assert n4.id == gc1.id
    end

    test "performs DFS traversal" do
      tree = Tree.new("Root", %{})
      {:ok, {tree, c1}} = Tree.add_child(tree, tree.root_id, "C1", %{})
      {:ok, {tree, _c2}} = Tree.add_child(tree, tree.root_id, "C2", %{})
      {:ok, {tree, _gc1}} = Tree.add_child(tree, c1.id, "GC1", %{})

      nodes = Tree.dfs(tree)
      assert length(nodes) == 4
    end

    test "gets all leaf nodes" do
      tree = Tree.new("Root", %{})
      {:ok, {tree, c1}} = Tree.add_child(tree, tree.root_id, "C1", %{})
      {:ok, {tree, c2}} = Tree.add_child(tree, tree.root_id, "C2", %{})
      {:ok, {tree, gc1}} = Tree.add_child(tree, c1.id, "GC1", %{})

      leaves = Tree.get_leaves(tree)
      assert length(leaves) == 2
      leaf_ids = Enum.map(leaves, & &1.id)
      assert c2.id in leaf_ids
      assert gc1.id in leaf_ids
      refute tree.root_id in leaf_ids
    end

    test "prunes by value threshold" do
      tree = Tree.new("Root", %{})
      {:ok, {tree, c1}} = Tree.add_child(tree, tree.root_id, "C1", %{})
      {:ok, {tree, c2}} = Tree.add_child(tree, tree.root_id, "C2", %{})

      # Set values
      {:ok, c1_node} = Tree.get_node(tree, c1.id)
      c1_valued = TreeNode.set_value(c1_node, 0.9)
      tree = Tree.update_node(tree, c1_valued)

      {:ok, c2_node} = Tree.get_node(tree, c2.id)
      c2_valued = TreeNode.set_value(c2_node, 0.3)
      tree = Tree.update_node(tree, c2_valued)

      # Prune nodes with value < 0.5
      pruned_tree = Tree.prune_by_value(tree, 0.5)

      # Should keep root and c1, remove c2
      assert pruned_tree.size == 2
      assert {:ok, _} = Tree.get_node(pruned_tree, c1.id)
      assert {:error, :not_found} = Tree.get_node(pruned_tree, c2.id)
    end

    test "prunes by beam width" do
      tree = Tree.new("Root", %{})

      # Add 5 children with different values
      {tree, _} = add_valued_child(tree, tree.root_id, "C1", 0.9)
      {tree, _} = add_valued_child(tree, tree.root_id, "C2", 0.8)
      {tree, _} = add_valued_child(tree, tree.root_id, "C3", 0.7)
      {tree, _} = add_valued_child(tree, tree.root_id, "C4", 0.6)
      {tree, _} = add_valued_child(tree, tree.root_id, "C5", 0.5)

      # Prune to keep only top 3
      pruned_tree = Tree.prune_by_beam_width(tree, 3)

      # Should keep root + 3 best children = 4 nodes
      assert pruned_tree.size == 4
    end
  end

  # =============================================================================
  # ThoughtGenerator Tests
  # =============================================================================

  describe "ThoughtGenerator" do
    test "generates thoughts with sampling strategy" do
      thought_fn = fn opts ->
        ThoughtGenerator.simulate_sampling_thoughts(
          opts[:problem],
          opts[:parent_state],
          opts[:beam_width],
          opts[:temperature] || 0.7
        )
      end

      {:ok, thoughts} =
        ThoughtGenerator.generate(
          problem: "Solve 2+2",
          parent_state: %{},
          strategy: :sampling,
          beam_width: 3,
          thought_fn: thought_fn
        )

      assert length(thoughts) == 3
      assert Enum.all?(thoughts, &is_binary/1)
    end

    test "generates thoughts with proposal strategy" do
      thought_fn = fn opts ->
        ThoughtGenerator.simulate_proposal_thoughts(
          opts[:problem],
          opts[:parent_state],
          opts[:beam_width],
          opts[:temperature] || 0.4
        )
      end

      {:ok, thoughts} =
        ThoughtGenerator.generate(
          problem: "Write fibonacci",
          parent_state: %{},
          strategy: :proposal,
          beam_width: 4,
          thought_fn: thought_fn
        )

      assert length(thoughts) == 4
      assert Enum.all?(thoughts, &is_binary/1)
    end

    test "generates thoughts with adaptive beam width" do
      thought_fn = fn opts ->
        # Adaptive strategy uses sampling, so use sampling simulation
        ThoughtGenerator.simulate_sampling_thoughts(
          opts[:problem],
          opts[:parent_state],
          opts[:beam_width],
          opts[:temperature] || 0.7
        )
      end

      {:ok, thoughts} =
        ThoughtGenerator.generate(
          problem: "Complex problem",
          parent_state: %{},
          strategy: :adaptive,
          beam_width: 5,
          depth: 3,
          tree_size: 100,
          thought_fn: thought_fn
        )

      # Should reduce beam width based on depth/size
      assert length(thoughts) <= 5
    end

    test "uses custom thought function when provided" do
      custom_fn = fn _opts ->
        ["Custom thought 1", "Custom thought 2"]
      end

      {:ok, thoughts} =
        ThoughtGenerator.generate(
          problem: "Test",
          parent_state: %{},
          thought_fn: custom_fn
        )

      assert thoughts == ["Custom thought 1", "Custom thought 2"]
    end

    test "adaptive beam width reduces with depth" do
      width_depth_0 = ThoughtGenerator.adaptive_beam_width(5, 0, 10)
      width_depth_4 = ThoughtGenerator.adaptive_beam_width(5, 4, 10)

      assert width_depth_4 < width_depth_0
    end

    test "adaptive beam width reduces with tree size" do
      width_small = ThoughtGenerator.adaptive_beam_width(5, 1, 100)
      width_large = ThoughtGenerator.adaptive_beam_width(5, 1, 1000)

      assert width_large <= width_small
    end
  end

  # =============================================================================
  # ThoughtEvaluator Tests
  # =============================================================================

  describe "ThoughtEvaluator" do
    test "evaluates thought with value strategy" do
      evaluation_fn = fn opts ->
        ThoughtEvaluator.simulate_value_evaluation(
          opts[:thought],
          opts[:problem],
          opts[:state] || %{}
        )
      end

      {:ok, score} =
        ThoughtEvaluator.evaluate(
          thought: "Try approach X to solve Y",
          problem: "Solve Y",
          strategy: :value,
          evaluation_fn: evaluation_fn
        )

      assert is_float(score)
      assert score >= 0.0 and score <= 1.0
    end

    test "evaluates thought with vote strategy" do
      evaluation_fn = fn opts ->
        ThoughtEvaluator.simulate_value_evaluation(
          opts[:thought],
          opts[:problem],
          opts[:state] || %{}
        )
      end

      {:ok, score} =
        ThoughtEvaluator.evaluate(
          thought: "Complex step",
          problem: "Hard problem",
          strategy: :vote,
          num_votes: 3,
          evaluation_fn: evaluation_fn
        )

      assert is_float(score)
      assert score >= 0.0 and score <= 1.0
    end

    test "evaluates thought with heuristic strategy" do
      heuristic_fn = fn _opts -> 0.75 end

      {:ok, score} =
        ThoughtEvaluator.evaluate(
          thought: "Test thought",
          problem: "Test problem",
          strategy: :heuristic,
          heuristic_fn: heuristic_fn
        )

      assert score == 0.75
    end

    test "evaluates thought with hybrid strategy" do
      evaluation_fn = fn opts ->
        ThoughtEvaluator.simulate_value_evaluation(
          opts[:thought],
          opts[:problem],
          opts[:state] || %{}
        )
      end

      {:ok, score} =
        ThoughtEvaluator.evaluate(
          thought: "Hybrid test",
          problem: "Test",
          strategy: :hybrid,
          evaluation_fn: evaluation_fn
        )

      assert is_float(score)
      assert score >= 0.0 and score <= 1.0
    end

    test "uses custom evaluation function when provided" do
      custom_fn = fn _opts -> 0.88 end

      {:ok, score} =
        ThoughtEvaluator.evaluate(
          thought: "Test",
          problem: "Test",
          evaluation_fn: custom_fn
        )

      assert score == 0.88
    end

    test "evaluates batch of thoughts" do
      thoughts = ["Thought 1", "Thought 2", "Thought 3"]

      evaluation_fn = fn opts ->
        ThoughtEvaluator.simulate_value_evaluation(
          opts[:thought],
          opts[:problem],
          opts[:state] || %{}
        )
      end

      {:ok, scores} =
        ThoughtEvaluator.evaluate_batch(
          thoughts,
          problem: "Test problem",
          strategy: :value,
          evaluation_fn: evaluation_fn
        )

      assert length(scores) == 3
      assert Enum.all?(scores, fn s -> s >= 0.0 and s <= 1.0 end)
    end
  end

  # =============================================================================
  # TreeOfThoughts Integration Tests
  # =============================================================================

  describe "TreeOfThoughts.run/1" do
    test "executes BFS search successfully" do
      thought_fn = fn opts ->
        depth = opts[:depth] || 0

        if depth < 2 do
          ["Approach A", "Approach B"]
        else
          []
        end
      end

      evaluation_fn = fn opts ->
        thought = opts[:thought]

        if String.contains?(thought, "A") do
          0.9
        else
          0.6
        end
      end

      {:ok, result} =
        TreeOfThoughts.run(
          problem: "Test problem",
          search_strategy: :bfs,
          beam_width: 2,
          max_depth: 2,
          budget: 20,
          thought_fn: thought_fn,
          evaluation_fn: evaluation_fn
        )

      assert result.search_steps >= 1
      assert result.tree.size > 1
      assert result.nodes_evaluated > 0
    end

    test "executes DFS search successfully" do
      thought_fn = fn opts ->
        depth = opts[:depth] || 0
        if depth < 2, do: ["Next step"], else: []
      end

      evaluation_fn = fn _opts -> 0.7 end

      {:ok, result} =
        TreeOfThoughts.run(
          problem: "Test DFS",
          search_strategy: :dfs,
          beam_width: 2,
          max_depth: 3,
          budget: 15,
          thought_fn: thought_fn,
          evaluation_fn: evaluation_fn
        )

      assert result.tree.size > 1
      assert result.search_steps >= 1
    end

    test "executes best-first search successfully" do
      thought_fn = fn _opts -> ["High value thought", "Low value thought"] end

      evaluation_fn = fn opts ->
        if String.contains?(opts[:thought], "High"), do: 0.9, else: 0.3
      end

      {:ok, result} =
        TreeOfThoughts.run(
          problem: "Test best-first",
          search_strategy: :best_first,
          beam_width: 2,
          max_depth: 2,
          budget: 20,
          thought_fn: thought_fn,
          evaluation_fn: evaluation_fn
        )

      assert result.tree.size > 1
    end

    test "stops when budget exhausted" do
      thought_fn = fn _opts -> ["Thought 1", "Thought 2", "Thought 3"] end
      evaluation_fn = fn _opts -> 0.7 end

      {:ok, result} =
        TreeOfThoughts.run(
          problem: "Budget test",
          search_strategy: :bfs,
          beam_width: 3,
          max_depth: 5,
          budget: 5,
          # Very small budget
          thought_fn: thought_fn,
          evaluation_fn: evaluation_fn
        )

      assert result.reason == :budget_exhausted
      assert result.nodes_evaluated <= 5
    end

    test "finds solution with custom solution check" do
      thought_fn = fn _opts -> ["Solution!", "Not solution"] end
      evaluation_fn = fn _opts -> 0.8 end
      solution_check = fn node -> String.contains?(node.thought, "Solution!") end

      {:ok, result} =
        TreeOfThoughts.run(
          problem: "Find solution",
          search_strategy: :bfs,
          beam_width: 2,
          max_depth: 2,
          thought_fn: thought_fn,
          evaluation_fn: evaluation_fn,
          solution_check: solution_check
        )

      assert result.success
      assert result.reason == :solution_found
      assert result.answer =~ "Solution!"
    end

    test "returns solution path when found" do
      thought_fn = fn opts ->
        case opts[:depth] do
          0 -> ["Step 1"]
          1 -> ["Step 2"]
          _ -> []
        end
      end

      evaluation_fn = fn _opts -> 0.85 end

      solution_check = fn node ->
        node.depth >= 2 && node.value > 0.8
      end

      {:ok, result} =
        TreeOfThoughts.run(
          problem: "Path test",
          search_strategy: :bfs,
          beam_width: 1,
          max_depth: 3,
          thought_fn: thought_fn,
          evaluation_fn: evaluation_fn,
          solution_check: solution_check
        )

      if result.success do
        assert length(result.solution_path) >= 2
        assert List.first(result.solution_path).depth == 0
      end
    end

    test "handles frontier exhaustion" do
      thought_fn = fn _opts -> [] end
      # No thoughts generated
      evaluation_fn = fn _opts -> 0.5 end

      {:ok, result} =
        TreeOfThoughts.run(
          problem: "Exhaustion test",
          search_strategy: :bfs,
          beam_width: 2,
          max_depth: 2,
          thought_fn: thought_fn,
          evaluation_fn: evaluation_fn
        )

      assert result.reason == :frontier_exhausted
      refute result.success
    end
  end

  # =============================================================================
  # Performance and Cost Tests
  # =============================================================================

  describe "Performance characteristics" do
    test "documents expected cost multiplier" do
      # ToT typically explores b^d nodes where b=beam_width, d=depth
      # With pruning, typically 10-50 nodes evaluated
      # Each node: 1 generation call + k evaluations
      # Cost: (10-50) * (1 + k) LLM calls

      cost_model = %{
        base_cot_cost: 1,
        nodes_evaluated: 30,
        # Typical
        beam_width: 3,
        evaluation_strategy: :value,
        # 1 LLM call per node
        evaluations_per_node: 1,
        total_cost: fn model ->
          model.base_cot_cost +
            model.nodes_evaluated * (1 + model.evaluations_per_node)
        end
      }

      total = cost_model.total_cost.(cost_model)

      # ToT typically 50-150x cost
      assert total >= 50
      assert total <= 150
    end

    test "documents accuracy improvement" do
      # Research shows dramatic improvements on specific tasks
      metrics = %{
        game_of_24_baseline: 0.04,
        game_of_24_tot: 0.74,
        # +70% absolute
        creative_writing_improvement: 0.20,
        # +20% quality
        crossword_improvement: 0.60
        # +60% solve rate
      }

      improvement =
        (metrics.game_of_24_tot - metrics.game_of_24_baseline) / metrics.game_of_24_baseline

      # Should be ~1750% relative improvement
      assert improvement > 10.0
    end
  end

  describe "Use case validation" do
    test "documents when to use ToT" do
      use_cases = %{
        critical_accuracy: "Tasks where exhaustive exploration justified",
        planning: "Multi-step planning with branching choices",
        algorithmic: "Algorithmic problems like Game of 24",
        creative: "Creative tasks benefiting from diverse exploration"
      }

      assert Map.has_key?(use_cases, :critical_accuracy)
      assert Map.has_key?(use_cases, :planning)
    end

    test "documents when NOT to use ToT" do
      avoid_cases = %{
        simple_queries: "Direct questions answerable with basic CoT",
        cost_sensitive: "Applications where 50-150x cost prohibitive",
        real_time: "Sub-second latency requirements",
        single_path: "Problems with obvious single solution path"
      }

      assert Map.has_key?(avoid_cases, :cost_sensitive)
      assert Map.has_key?(avoid_cases, :real_time)
    end
  end

  # Helper functions

  defp add_valued_child(tree, parent_id, thought, value) do
    {:ok, {updated_tree, child}} = Tree.add_child(tree, parent_id, thought, %{})
    child_with_value = TreeNode.set_value(child, value)
    final_tree = Tree.update_node(updated_tree, child_with_value)
    {final_tree, child_with_value}
  end
end
