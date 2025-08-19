defmodule Jido.HTN do
  @moduledoc """
  The HTN planner implementation.
  """

  use ExDbug, enabled: false
  use Private

  alias Jido.HTN.CompoundTask
  alias Jido.HTN.Planner.TaskDecomposer

  @max_recursion 100

  @doc """
  Plans a sequence of actions to achieve the given task in the domain.
  """
  @spec plan(Domain.t(), map(), keyword()) ::
          {:ok, [{module(), keyword()}]} | {:error, String.t()}
  def plan(domain, world_state, opts \\ []) do
    dbug(
      "Starting planning with domain: #{inspect(domain)}, world_state: #{inspect(world_state)}"
    )

    debug = Keyword.get(opts, :debug, false)
    timeout = Keyword.get(opts, :timeout, 5000)
    current_plan_mtr = Keyword.get(opts, :current_plan_mtr, nil)

    # Validate root tasks
    root_tasks = validate_root_tasks!(domain, opts)

    # Initialize world state with background task tracking
    world_state = Map.put_new(world_state, :background_tasks, MapSet.new())

    result =
      case Task.yield(
             Task.async(fn ->
               do_plan(domain, world_state, debug, root_tasks, current_plan_mtr)
             end),
             timeout
           ) do
        {:ok, result} ->
          dbug("Planning completed: #{inspect(result)}")
          result

        {:exit, reason} ->
          dbug("Planning failed: #{inspect(reason)}")
          {:error, "Planning failed: #{inspect(reason)}"}

        nil ->
          dbug("Planning timed out after #{timeout}ms")
          {:error, "Planning timed out after #{timeout}ms"}
      end

    dbug("Planning result: #{inspect(result)}")
    result
  end

  @doc """
  Decomposes a list of tasks into their primitive components.
  """
  @spec decompose(map(), list(), map(), list(), list(), integer(), boolean(), map() | nil) ::
          {:ok, list(), map(), list(), tuple()} | {:error, String.t(), tuple()}
  def decompose(
        domain,
        tasks,
        world_state,
        current_plan,
        mtr,
        recursion_count,
        debug,
        current_plan_mtr \\ nil
      ) do
    dbug("Starting decompose with tasks: #{inspect(tasks)}, recursion_count: #{recursion_count}")

    do_decompose(
      domain,
      tasks,
      world_state,
      current_plan,
      mtr,
      recursion_count,
      debug,
      [],
      current_plan_mtr
    )
  end

  private do
    defp validate_root_tasks!(domain, opts) do
      case Keyword.get(opts, :root_tasks) do
        nil ->
          # If no root tasks specified, use the domain's root tasks
          if MapSet.size(domain.root_tasks) > 0 do
            MapSet.to_list(domain.root_tasks)
          else
            # Fallback for backward compatibility
            ["root"]
          end

        root_tasks when is_list(root_tasks) ->
          Enum.each(root_tasks, fn task ->
            case Map.get(domain.tasks, task) do
              %CompoundTask{} -> :ok
              nil -> raise ArgumentError, "Root task '#{task}' not found in domain"
              _ -> raise ArgumentError, "Root task '#{task}' must be a compound task"
            end
          end)

          root_tasks

        other ->
          raise ArgumentError, "root_tasks must be a list of task names, got: #{inspect(other)}"
      end
    end

    defp do_plan(domain, world_state, debug, root_tasks, current_plan_mtr) do
      dbug(
        "Starting do_plan with domain: #{inspect(domain)}, world_state: #{inspect(world_state)}, debug: #{debug}"
      )

      case decompose(
             domain,
             Enum.reverse(root_tasks),
             world_state,
             [],
             [],
             0,
             debug,
             current_plan_mtr
           ) do
        {:ok, plan, _final_state, mtr_list, tree} when debug ->
          dbug("do_plan completed successfully with debug tree")
          mtr_struct = %Jido.HTN.Planner.MethodTraversalRecord{choices: Enum.reverse(mtr_list)}
          {:ok, plan, mtr_struct, tree}

        {:ok, plan, _final_state, mtr_list, _tree} ->
          dbug("do_plan completed successfully")
          mtr_struct = %Jido.HTN.Planner.MethodTraversalRecord{choices: Enum.reverse(mtr_list)}
          {:ok, plan, mtr_struct}

        {:error, reason, tree} ->
          dbug("do_plan failed: #{reason}")

          if debug do
            {:error, reason, tree}
          else
            {:error, reason}
          end
      end
    end

    defp do_decompose(
           _domain,
           [],
           world_state,
           current_plan,
           mtr,
           _recursion_count,
           _debug,
           acc_tree,
           _current_plan_mtr
         ) do
      dbug("do_decompose completed, all tasks processed")
      {:ok, current_plan, world_state, mtr, {:compound, "root", true, Enum.reverse(acc_tree)}}
    end

    defp do_decompose(
           _domain,
           _tasks,
           _world_state,
           _current_plan,
           _mtr,
           recursion_count,
           _debug,
           _acc_tree,
           _current_plan_mtr
         )
         when recursion_count >= @max_recursion do
      dbug("Max recursion depth reached: #{recursion_count}")

      {:error, "Max recursion depth reached",
       {:compound, "root", false, [{:empty, "Max recursion", false, []}]}}
    end

    defp do_decompose(
           domain,
           [task | rest_tasks],
           world_state,
           current_plan,
           mtr,
           recursion_count,
           debug,
           acc_tree,
           current_plan_mtr
         ) do
      dbug("Processing task: #{inspect(task)}")

      case TaskDecomposer.decompose_task(
             domain,
             task,
             world_state,
             current_plan,
             mtr,
             recursion_count,
             debug,
             current_plan_mtr
           ) do
        {:ok, new_plan, new_world_state, new_mtr, subtree} ->
          dbug("Task #{inspect(task)} decomposed successfully")

          do_decompose(
            domain,
            rest_tasks,
            new_world_state,
            new_plan,
            new_mtr,
            recursion_count,
            debug,
            [subtree | acc_tree],
            current_plan_mtr
          )

        {:error, reason, error_tree} ->
          dbug("Task #{inspect(task)} decomposition failed: #{reason}")
          {:error, reason, {:compound, task, false, Enum.reverse([error_tree | acc_tree])}}
      end
    end
  end
end
