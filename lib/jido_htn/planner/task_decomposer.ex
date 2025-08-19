defmodule Jido.HTN.Planner.TaskDecomposer do
  @moduledoc """
  Handles task decomposition in the HTN planner.
  """

  use ExDbug, enabled: false
  use Private

  alias Jido.HTN.CompoundTask
  alias Jido.HTN.PrimitiveTask
  alias Jido.HTN.Planner.ConditionEvaluator
  alias Jido.HTN.Planner.EffectHandler

  @doc """
  Decomposes a task into its primitive components.
  """
  @spec decompose_task(
          map(),
          String.t(),
          map(),
          list(),
          list(),
          integer(),
          boolean(),
          map() | nil
        ) ::
          {:ok, list(), map(), tuple()} | {:error, String.t(), tuple()}
  def decompose_task(
        domain,
        task_name,
        world_state,
        current_plan,
        mtr,
        recursion_count,
        debug,
        current_plan_mtr \\ nil
      ) do
    case Map.get(domain.tasks, task_name) do
      %PrimitiveTask{} = task ->
        decompose_primitive(domain, task, world_state, current_plan, mtr)

      %CompoundTask{} = task ->
        decompose_compound(
          domain,
          task,
          world_state,
          current_plan,
          mtr,
          recursion_count + 1,
          debug,
          current_plan_mtr
        )

      nil ->
        {:error, "Unknown task: #{inspect(task_name)}", {:empty, task_name, false, []}}
    end
  end

  private do
    defp decompose_primitive(domain, task, world_state, current_plan, mtr) do
      {conditions_met, condition_results} =
        ConditionEvaluator.preconditions_met?(domain, task.preconditions, world_state)

      if conditions_met do
        action = task_to_action(task)

        # --- STATE SIMULATION with Expected Effects ---
        # The 'result' map for planning-time simulation is empty for primitive tasks,
        # as actual action output isn't available yet.
        # For expected_effects, they generally operate on world_state directly.
        final_world_state_for_this_step =
          EffectHandler.apply_all_effects_for_simulation(domain, task, %{}, world_state)

        final_world_state_for_this_step =
          if task.background do
            Map.update!(
              # Use the state *after* all effects
              final_world_state_for_this_step,
              :background_tasks,
              &MapSet.put(&1, task.name)
            )
          else
            final_world_state_for_this_step
          end

        # --- END STATE SIMULATION ---

        {:ok, current_plan ++ [action], final_world_state_for_this_step, mtr,
         {:primitive, task.name, true, condition_results}}
      else
        {:error, "Precondition not met for #{inspect(task.name)}",
         {:primitive, task.name, false, condition_results}}
      end
    end

    defp decompose_compound(
           domain,
           task,
           world_state,
           current_plan,
           mtr,
           recursion_count,
           debug,
           current_plan_mtr
         ) do
      {result, debug_trees} =
        task.methods
        |> sort_methods_by_priority()
        |> Enum.with_index()
        |> Enum.reduce_while({{:error, "No valid method found"}, []}, fn {method, index},
                                                                         {_, acc_trees} ->
          # Ensure method has a name, fallback to index-based name if not provided
          method_name = Map.get(method, :name) || "method#{index + 1}"

          # Store initial state before trying this method
          initial_state = %{
            world_state: world_state,
            current_plan: current_plan
          }

          {conditions_met, condition_results} =
            ConditionEvaluator.method_conditions_met?(domain, method, world_state)

          case conditions_met &&
                 try_method(
                   domain,
                   task,
                   method,
                   initial_state.world_state,
                   initial_state.current_plan,
                   mtr,
                   recursion_count,
                   debug,
                   current_plan_mtr
                 ) do
            {:pruned, pruned_debug_tree} ->
              {:cont,
               {{:error, "Path pruned due to lower priority"},
                [{false, method_name, condition_results, pruned_debug_tree} | acc_trees]}}

            {:ok, new_plan, new_world_state, new_mtr, subtrees} when is_list(subtrees) ->
              # Build the debug tree for this successful method
              method_debug_tree = {:compound, task.name, true, subtrees}

              {:halt,
               {{:ok, new_plan, new_world_state, new_mtr},
                [{true, method_name, condition_results, method_debug_tree} | acc_trees]}}

            {:ok, new_plan, new_world_state, new_mtr, subtree} ->
              # Build the debug tree for this successful method
              method_debug_tree = {:compound, task.name, true, [subtree]}

              {:halt,
               {{:ok, new_plan, new_world_state, new_mtr},
                [{true, method_name, condition_results, method_debug_tree} | acc_trees]}}

            _ ->
              # Restore state before trying next method
              dbug("Method #{method_name} failed, restoring state and trying next method")

              {:cont,
               {{:error, "Method failed"},
                [{false, method_name, condition_results, {:empty, "", false, []}} | acc_trees]}}
          end
        end)

      debug_tree =
        {:compound, task.name, is_tuple(result) and elem(result, 0) == :ok,
         Enum.reverse(debug_trees)}

      case result do
        {:ok, plan, state, mtr} -> {:ok, plan, state, mtr, debug_tree}
        {:error, reason} -> {:error, reason, debug_tree}
      end
    end

    # Sort methods by priority (lower number = higher priority)
    # Methods without a priority are given a default priority of 100
    defp sort_methods_by_priority(methods) do
      methods
      |> Enum.map(fn method ->
        # Convert plain map to Method struct if needed
        method_struct =
          case method do
            %Jido.HTN.Method{} -> method
            %{} = map -> struct(Jido.HTN.Method, map)
          end

        {method_struct, Map.get(method_struct, :priority, 100)}
      end)
      # Sort by priority (second element of tuple)
      |> Enum.sort_by(&elem(&1, 1))
      # Extract just the method structs
      |> Enum.map(&elem(&1, 0))
    end

    defp try_method(
           domain,
           task,
           method,
           world_state,
           current_plan,
           mtr,
           recursion_count,
           debug,
           current_plan_mtr
         ) do
      if ConditionEvaluator.method_conditions_met?(domain, method, world_state) do
        # Convert plain map to Method struct if needed
        method_struct =
          case method do
            %Jido.HTN.Method{} -> method
            %{} = map -> struct(Jido.HTN.Method, map)
          end

        # Get ordered subtasks based on constraints
        ordered_subtasks = Jido.HTN.Method.order_subtasks(method_struct)

        # Record this method choice in the MTR
        new_mtr =
          case mtr do
            nil -> []
            _ -> mtr
          end
          |> Kernel.++([
            {task.name, Map.get(method_struct, :name), Map.get(method_struct, :priority)}
          ])

        # PLAN CULLING: If current_plan_mtr is provided, compare and prune if lower priority
        if current_plan_mtr do
          current_path_mtr = %Jido.HTN.Planner.MethodTraversalRecord{
            choices: Enum.reverse(new_mtr)
          }

          comparison_result =
            Jido.HTN.Planner.MethodTraversalRecord.compare_priority(
              current_path_mtr,
              current_plan_mtr
            )

          if comparison_result == :lt do
            pruned_debug_tree =
              {:compound, task.name, false, [{:empty, "pruned_due_to_lower_priority", false, []}]}

            {:pruned, pruned_debug_tree}
          else
            Jido.HTN.decompose(
              domain,
              ordered_subtasks,
              world_state,
              current_plan,
              new_mtr,
              recursion_count + 1,
              debug
            )
          end
        else
          Jido.HTN.decompose(
            domain,
            ordered_subtasks,
            world_state,
            current_plan,
            new_mtr,
            recursion_count + 1,
            debug
          )
        end
      else
        {:error, "Method conditions not met"}
      end
    end

    defp task_to_action(%PrimitiveTask{task: {module, params}})
         when is_atom(module) and is_list(params) do
      {module, Enum.to_list(params)}
    end

    defp task_to_action(%PrimitiveTask{task: module}) when is_atom(module) do
      module
    end
  end
end
