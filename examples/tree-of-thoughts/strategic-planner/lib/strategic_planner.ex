defmodule Examples.TreeOfThoughts.StrategicPlanner do
  @moduledoc """
  Advanced Tree-of-Thoughts example demonstrating strategic project planning.

  This example shows how ToT can explore multiple planning strategies simultaneously,
  considering constraints, dependencies, and optimization criteria.

  ## The Planning Problem

  Given a set of tasks with dependencies, costs, and durations, find an optimal
  execution plan that meets requirements and constraints.

  ## Usage

      # Run the example
      Examples.TreeOfThoughts.StrategicPlanner.run()

      # Plan a custom project
      Examples.TreeOfThoughts.StrategicPlanner.plan_project(
        tasks: [:design, :implement, :test, :deploy],
        constraints: %{max_cost: 50_000, max_duration: 90},
        requirements: [:quality_assured, :scalable]
      )

  ## Features

  - Multi-criteria optimization (cost, time, quality)
  - Dependency tracking and validation
  - Constraint satisfaction
  - Alternative plan exploration
  - Best-first search with hybrid evaluation
  - Partial plan generation
  """

  require Logger

  @doc """
  Run the complete example with a sample project planning scenario.
  """
  def run do
    IO.puts("\n" <> String.duplicate("=", 70))
    IO.puts("  Tree-of-Thoughts: Strategic Project Planning")
    IO.puts(String.duplicate("=", 70) <> "\n")

    IO.puts("📋 **Scenario:** Plan a web application project")
    IO.puts("🎯 **Goal:** Find optimal task sequence")
    IO.puts("⚖️  **Optimize:** Cost, time, and quality")
    IO.puts("🔧 **Strategy:** Best-First search\n")
    IO.puts(String.duplicate("-", 70) <> "\n")

    # Define project
    tasks = [:requirements, :design, :backend, :frontend, :testing, :deployment]

    constraints = %{
      max_cost: 80_000,
      max_duration: 120,
      min_quality_score: 8.0
    }

    requirements = [:fully_tested, :documented, :production_ready]

    case plan_project(tasks, constraints, requirements) do
      {:ok, result} ->
        display_result(result)
        {:ok, result}

      {:error, reason} ->
        IO.puts("❌ **Error:** #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Plan a project using Tree-of-Thoughts.

  ## Parameters

  - `tasks` - List of task atoms to complete
  - `constraints` - Map with max_cost, max_duration, min_quality_score
  - `requirements` - List of requirements that must be met
  - `opts` - Search options

  ## Returns

  - `{:ok, result}` - Success with plan and alternatives
  - `{:error, reason}` - Failure reason
  """
  def plan_project(tasks, constraints, requirements, opts \\ []) do
    search_strategy = Keyword.get(opts, :search_strategy, :best_first)
    beam_width = Keyword.get(opts, :beam_width, 4)
    max_depth = Keyword.get(opts, :max_depth, length(tasks) + 1)
    budget = Keyword.get(opts, :budget, 100)

    # Get task catalog
    task_catalog = build_task_catalog()

    # Initialize tree
    tree = initialize_tree(tasks, constraints, requirements)

    # Run tree search
    state = %{
      tree: tree,
      frontier: [tree.root_id],
      solution_ids: [],
      nodes_evaluated: 0,
      search_strategy: search_strategy,
      beam_width: beam_width,
      max_depth: max_depth,
      budget: budget,
      tasks: tasks,
      constraints: constraints,
      requirements: requirements,
      task_catalog: task_catalog
    }

    run_tree_search(state)
  end

  # Task Catalog

  defp build_task_catalog do
    %{
      requirements: %{
        name: "Requirements Analysis",
        cost: 5_000,
        duration: 10,
        quality_impact: 9.0,
        dependencies: [],
        provides: [:specifications, :user_stories]
      },
      design: %{
        name: "System Design",
        cost: 8_000,
        duration: 15,
        quality_impact: 9.5,
        dependencies: [:requirements],
        provides: [:architecture, :documented]
      },
      backend: %{
        name: "Backend Development",
        cost: 25_000,
        duration: 40,
        quality_impact: 8.0,
        dependencies: [:design],
        provides: [:api, :database]
      },
      frontend: %{
        name: "Frontend Development",
        cost: 20_000,
        duration: 35,
        quality_impact: 8.0,
        dependencies: [:design],
        provides: [:ui, :responsive]
      },
      testing: %{
        name: "Quality Assurance",
        cost: 12_000,
        duration: 20,
        quality_impact: 10.0,
        dependencies: [:backend, :frontend],
        provides: [:fully_tested, :quality_assured]
      },
      deployment: %{
        name: "Production Deployment",
        cost: 6_000,
        duration: 10,
        quality_impact: 7.0,
        dependencies: [:testing],
        provides: [:production_ready, :live]
      },
      optimization: %{
        name: "Performance Optimization",
        cost: 15_000,
        duration: 20,
        quality_impact: 8.5,
        dependencies: [:backend, :frontend],
        provides: [:optimized, :scalable]
      },
      security: %{
        name: "Security Hardening",
        cost: 10_000,
        duration: 15,
        quality_impact: 9.0,
        dependencies: [:backend],
        provides: [:secure, :audited]
      },
      documentation: %{
        name: "Documentation",
        cost: 5_000,
        duration: 10,
        quality_impact: 7.5,
        dependencies: [:backend, :frontend],
        provides: [:documented, :maintainable]
      }
    }
  end

  # Tree Structure (reuse from game_of_24.ex for simplicity)

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

  defp initialize_tree(tasks, constraints, requirements) do
    root_id = "node_1"

    root = %TreeNode{
      id: root_id,
      thought: "Start planning: #{length(tasks)} tasks to schedule",
      state: %{
        plan: [],
        tasks_remaining: tasks,
        tasks_completed: [],
        total_cost: 0,
        total_duration: 0,
        quality_score: 10.0,
        requirements_met: [],
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
      # Found enough solutions
      length(state.solution_ids) >= 3 ->
        {:ok, finalize_result(state, :solutions_found)}

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
    # Get next node to expand
    {node_id, remaining_frontier} = select_next_node(state)

    {:ok, node} = Tree.get_node(state.tree, node_id)

    # Check if this node is a solution
    if is_solution?(node, state) do
      {:ok,
       %{
         state
         | solution_ids: [node_id | state.solution_ids],
           frontier: remaining_frontier,
           nodes_evaluated: state.nodes_evaluated + 1
       }}
    else
      # Generate thoughts for this node
      thoughts = generate_thoughts(node, state)

      if Enum.empty?(thoughts) do
        # Dead end - no valid next steps
        {:ok, %{state | frontier: remaining_frontier, nodes_evaluated: state.nodes_evaluated + 1}}
      else
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
  end

  defp select_next_node(state) do
    case state.search_strategy do
      :bfs ->
        [node_id | rest] = state.frontier
        {node_id, rest}

      :dfs ->
        {node_id, rest} = List.pop_at(state.frontier, -1)
        {node_id, rest}

      :best_first ->
        best_id =
          Enum.max_by(state.frontier, fn id ->
            {:ok, node} = Tree.get_node(state.tree, id)
            node.value || 0.0
          end)

        {best_id, List.delete(state.frontier, best_id)}
    end
  end

  defp is_solution?(node, state) do
    plan_state = node.state

    # Complete plan if:
    # 1. All tasks scheduled OR no more tasks can be added
    # 2. All requirements met
    # 3. Within constraints

    all_tasks_scheduled = Enum.empty?(plan_state.tasks_remaining)
    requirements_met = requirements_satisfied?(plan_state, state.requirements)
    within_constraints = meets_constraints?(plan_state, state.constraints)

    all_tasks_scheduled and requirements_met and within_constraints
  end

  defp requirements_satisfied?(plan_state, requirements) do
    Enum.all?(requirements, fn req ->
      req in plan_state.requirements_met
    end)
  end

  defp meets_constraints?(plan_state, constraints) do
    plan_state.total_cost <= constraints.max_cost and
      plan_state.total_duration <= constraints.max_duration and
      plan_state.quality_score >= constraints.min_quality_score
  end

  # Thought Generation

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

  defp dependencies_met?(dependencies, completed_tasks) do
    Enum.all?(dependencies, fn dep -> dep in completed_tasks end)
  end

  defp generate_task_thought(task, parent_state, state) do
    task_def = state.task_catalog[task]

    # Calculate new state after adding this task
    new_cost = parent_state.total_cost + task_def.cost
    new_duration = parent_state.total_duration + task_def.duration

    # Quality score decays slightly with each task, boosted by high-quality tasks
    quality_adjustment = (task_def.quality_impact - 8.0) * 0.1
    new_quality = max(0.0, parent_state.quality_score + quality_adjustment - 0.1)

    # Check if this would violate constraints
    if new_cost > state.constraints.max_cost or
         new_duration > state.constraints.max_duration do
      nil
    else
      new_state = %{
        plan: parent_state.plan ++ [task],
        tasks_remaining: List.delete(parent_state.tasks_remaining, task),
        tasks_completed: [task | parent_state.tasks_completed],
        total_cost: new_cost,
        total_duration: new_duration,
        quality_score: new_quality,
        requirements_met: parent_state.requirements_met ++ task_def.provides,
        depth: parent_state.depth + 1,
        last_task: task
      }

      %{
        thought: "Add task: #{task_def.name} (cost: $#{task_def.cost}, duration: #{task_def.duration}d)",
        state: new_state,
        task: task
      }
    end
  end

  # Thought Evaluation

  defp evaluate_thoughts(thoughts, _node, state) do
    thoughts
    |> Enum.map(fn thought ->
      value = evaluate_thought(thought, state)
      Map.put(thought, :value, value)
    end)
    |> Enum.sort_by(fn t -> -t.value end)
    |> Enum.take(state.beam_width)
  end

  defp evaluate_thought(thought, state) do
    plan_state = thought.state

    # Multi-criteria evaluation

    # 1. Cost efficiency (lower is better)
    cost_ratio = plan_state.total_cost / state.constraints.max_cost
    cost_score = 1.0 - cost_ratio

    # 2. Time efficiency (lower is better)
    time_ratio = plan_state.total_duration / state.constraints.max_duration
    time_score = 1.0 - time_ratio

    # 3. Quality (higher is better)
    quality_score = plan_state.quality_score / 10.0

    # 4. Progress (more tasks completed is better)
    progress_score = length(plan_state.tasks_completed) / length(state.tasks)

    # 5. Requirements satisfaction
    requirements_score =
      length(plan_state.requirements_met) / max(1, length(state.requirements))

    # 6. Critical path considerations (prioritize tasks with dependents)
    task = thought.task
    task_criticality = count_dependents(task, state.task_catalog) / 5.0

    # Weighted combination
    weights = %{
      cost: 0.2,
      time: 0.2,
      quality: 0.25,
      progress: 0.15,
      requirements: 0.15,
      criticality: 0.05
    }

    weights.cost * cost_score +
      weights.time * time_score +
      weights.quality * quality_score +
      weights.progress * progress_score +
      weights.requirements * requirements_score +
      weights.criticality * task_criticality
  end

  defp count_dependents(task, task_catalog) do
    task_catalog
    |> Map.values()
    |> Enum.count(fn task_def ->
      task in task_def.dependencies
    end)
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
    solutions =
      state.solution_ids
      |> Enum.map(fn solution_id ->
        case Tree.get_path(state.tree, solution_id) do
          path when is_list(path) ->
            {:ok, solution_node} = Tree.get_node(state.tree, solution_id)
            format_solution(solution_node, path, state)

          _ ->
            nil
        end
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.sort_by(fn s -> -s.score end)

    best_solution = List.first(solutions)

    # Find alternative solutions (high-value incomplete plans)
    alternatives = find_alternatives(state.tree, state.solution_ids)

    %{
      success: length(solutions) > 0,
      solution: best_solution,
      all_solutions: solutions,
      alternatives: alternatives,
      tree: state.tree,
      nodes_evaluated: state.nodes_evaluated,
      reason: reason,
      metadata: %{
        tree_size: state.tree.size,
        max_depth: state.tree.max_depth,
        budget: state.budget,
        search_strategy: state.search_strategy,
        solutions_found: length(solutions)
      }
    }
  end

  defp format_solution(node, path, state) do
    plan_state = node.state

    %{
      plan: plan_state.plan,
      cost: plan_state.total_cost,
      duration: plan_state.total_duration,
      quality_score: Float.round(plan_state.quality_score, 1),
      tasks_count: length(plan_state.plan),
      requirements_met: plan_state.requirements_met,
      score: node.value || 0.0,
      path: path,
      details: format_plan_details(plan_state, state)
    }
  end

  defp format_plan_details(plan_state, state) do
    plan_state.plan
    |> Enum.map(fn task ->
      task_def = state.task_catalog[task]

      %{
        task: task,
        name: task_def.name,
        cost: task_def.cost,
        duration: task_def.duration,
        quality_impact: task_def.quality_impact
      }
    end)
  end

  defp find_alternatives(tree, solution_ids) do
    tree.nodes
    |> Map.values()
    |> Enum.reject(fn node -> node.id in solution_ids end)
    |> Enum.filter(fn node ->
      # High-value nodes at reasonable depth
      (node.value || 0.0) > 0.7 and node.depth >= 3
    end)
    |> Enum.sort_by(fn node -> -(node.value || 0.0) end)
    |> Enum.take(3)
    |> Enum.map(fn node ->
      %{
        plan: node.state.plan,
        cost: node.state.total_cost,
        duration: node.state.total_duration,
        completion: length(node.state.tasks_completed) / 6 * 100,
        value: Float.round(node.value || 0.0, 2)
      }
    end)
  end

  # Display Functions

  defp display_result(result) do
    IO.puts(String.duplicate("=", 70))
    IO.puts("\n✅ **Planning Complete**\n")

    IO.puts("📊 **Search Statistics:**")
    IO.puts("   • Nodes evaluated: #{result.nodes_evaluated}")
    IO.puts("   • Tree size: #{result.metadata.tree_size}")
    IO.puts("   • Solutions found: #{result.metadata.solutions_found}")
    IO.puts("   • Strategy: #{result.metadata.search_strategy}")

    if result.success && result.solution do
      solution = result.solution

      IO.puts("\n🎯 **Optimal Plan Found:**")
      IO.puts("   • Total cost: $#{solution.cost}")
      IO.puts("   • Total duration: #{solution.duration} days")
      IO.puts("   • Quality score: #{solution.quality_score}/10")
      IO.puts("   • Tasks: #{solution.tasks_count}")
      IO.puts("   • Overall score: #{Float.round(solution.score, 2)}")

      IO.puts("\n📋 **Task Sequence:**")

      solution.details
      |> Enum.with_index(1)
      |> Enum.each(fn {task, idx} ->
        IO.puts(
          "   #{idx}. #{task.name} - $#{task.cost}, #{task.duration}d, quality #{task.quality_impact}"
        )
      end)

      IO.puts("\n✅ **Requirements Met:**")

      solution.requirements_met
      |> Enum.uniq()
      |> Enum.each(fn req ->
        IO.puts("   • #{req}")
      end)

      if length(result.all_solutions) > 1 do
        IO.puts("\n🔄 **Alternative Solutions:**")

        result.all_solutions
        |> Enum.drop(1)
        |> Enum.take(2)
        |> Enum.with_index(2)
        |> Enum.each(fn {alt, idx} ->
          IO.puts("   #{idx}. Cost: $#{alt.cost}, Duration: #{alt.duration}d, Score: #{Float.round(alt.score, 2)}")
        end)
      end
    else
      IO.puts("\n❌ **No Complete Solution Found**")
      IO.puts("   Reason: #{result.reason}")

      if length(result.alternatives) > 0 do
        IO.puts("\n🔍 **Partial Plans (Best Attempts):**")

        result.alternatives
        |> Enum.with_index(1)
        |> Enum.each(fn {alt, idx} ->
          IO.puts(
            "   #{idx}. #{Float.round(alt.completion, 0)}% complete - Cost: $#{alt.cost}, Duration: #{alt.duration}d"
          )

          IO.puts("      Tasks: #{inspect(alt.plan)}")
        end)
      end
    end

    IO.puts("\n" <> String.duplicate("=", 70))
  end

  @doc """
  Compare different search strategies.
  """
  def compare_strategies do
    IO.puts("\n" <> String.duplicate("=", 70))
    IO.puts("  Strategy Comparison")
    IO.puts(String.duplicate("=", 70) <> "\n")

    tasks = [:requirements, :design, :backend, :frontend, :testing, :deployment]

    constraints = %{
      max_cost: 80_000,
      max_duration: 120,
      min_quality_score: 8.0
    }

    requirements = [:fully_tested, :documented, :production_ready]

    strategies = [:bfs, :dfs, :best_first]

    results =
      Enum.map(strategies, fn strategy ->
        IO.puts("Testing #{strategy}...")

        {:ok, result} =
          plan_project(tasks, constraints, requirements,
            search_strategy: strategy,
            budget: 50
          )

        {strategy, result}
      end)

    IO.puts("\n📊 **Results:**\n")

    Enum.each(results, fn {strategy, result} ->
      IO.puts("**#{strategy}:**")
      IO.puts("   • Solutions: #{result.metadata.solutions_found}")
      IO.puts("   • Nodes: #{result.nodes_evaluated}")

      if result.success do
        IO.puts("   • Best cost: $#{result.solution.cost}")
        IO.puts("   • Best duration: #{result.solution.duration}d")
      end

      IO.puts("")
    end)
  end
end
