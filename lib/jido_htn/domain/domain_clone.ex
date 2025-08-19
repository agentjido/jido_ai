defmodule Jido.HTN.Domain.CloneHelpers do
  @moduledoc """
  Helper functions for cloning and merging HTN domains.
  """

  alias Jido.HTN.{Domain, CompoundTask, PrimitiveTask, Method}

  @doc """
  Creates a deep copy of a domain.
  """
  def clone(%Domain{} = domain) do
    # Create a new domain struct with deep copies of all fields
    %Domain{
      name: String.duplicate(domain.name, 1),
      tasks: Map.new(domain.tasks, fn {k, v} -> {String.duplicate(k, 1), clone_task(v)} end),
      allowed_workflows:
        Map.new(domain.allowed_workflows, fn {k, v} -> {String.duplicate(k, 1), v} end),
      callbacks: Map.new(domain.callbacks, fn {k, v} -> {String.duplicate(k, 1), v} end),
      root_tasks:
        MapSet.new(Enum.map(MapSet.to_list(domain.root_tasks), &String.duplicate(&1, 1)))
    }
  end

  @doc """
  Merges two domains, resolving name conflicts by appending a suffix to tasks in the second domain.
  """
  def merge(%Domain{} = domain1, %Domain{} = domain2) do
    # Clone both domains to avoid modifying originals
    domain1 = clone(domain1)
    domain2 = clone(domain2)

    # Find conflicting task names and rename them
    {renamed_tasks, new_tasks} = rename_conflicting_tasks(domain1.tasks, domain2.tasks)

    # Update references in the renamed tasks
    new_tasks = rename_task_references(new_tasks, renamed_tasks)

    # Update root tasks to use renamed task names
    renamed_root_tasks =
      domain2.root_tasks
      |> MapSet.to_list()
      |> Enum.map(fn task -> Map.get(renamed_tasks, task, task) end)
      |> MapSet.new()

    # Create the merged domain
    %Domain{
      name: "#{domain1.name}_merged_#{domain2.name}",
      tasks: Map.merge(domain1.tasks, new_tasks),
      allowed_workflows: Map.merge(domain1.allowed_workflows, domain2.allowed_workflows),
      callbacks: Map.merge(domain1.callbacks, domain2.callbacks),
      root_tasks: MapSet.union(domain1.root_tasks, renamed_root_tasks)
    }
  end

  # Private helpers

  defp clone_task(%CompoundTask{} = task) do
    # Create a new CompoundTask struct with deep copies of all fields
    %CompoundTask{
      name: String.duplicate(task.name, 1),
      methods: Enum.map(task.methods, &clone_method/1)
    }
  end

  defp clone_task(%PrimitiveTask{} = task) do
    # Create a new PrimitiveTask struct with deep copies of all fields
    %PrimitiveTask{
      name: String.duplicate(task.name, 1),
      task: task.task,
      cost: task.cost,
      duration: task.duration,
      scheduling_constraints: clone_scheduling_constraints(task.scheduling_constraints),
      preconditions: clone_functions(task.preconditions),
      effects: clone_functions(task.effects),
      expected_effects: clone_functions(task.expected_effects),
      background: task.background
    }
  end

  defp clone_method(%Method{} = method) do
    # Create a new Method struct with deep copies of all fields
    %Method{
      name: String.duplicate(method.name, 1),
      priority: method.priority,
      conditions: clone_functions(method.conditions),
      subtasks: Enum.map(method.subtasks, &String.duplicate(&1, 1)),
      ordering: clone_ordering(method.ordering)
    }
  end

  defp clone_scheduling_constraints(nil), do: nil
  defp clone_scheduling_constraints(constraints), do: Map.new(constraints)

  defp clone_functions(functions) when is_list(functions),
    do: Enum.map(functions, &clone_function/1)

  defp clone_functions(nil), do: []

  defp clone_function(fun) when is_function(fun), do: fun
  defp clone_function(other), do: other

  defp clone_ordering(ordering) when is_list(ordering) do
    Enum.map(ordering, fn {before_task, after_task} ->
      {String.duplicate(before_task, 1), String.duplicate(after_task, 1)}
    end)
  end

  defp clone_ordering(nil), do: []

  defp rename_conflicting_tasks(tasks1, tasks2) do
    # First, find all tasks that need to be renamed
    {renamed_map, new_tasks} =
      Enum.reduce(tasks2, {%{}, %{}}, fn {name, task}, {renamed_map, new_tasks} ->
        if Map.has_key?(tasks1, name) do
          # Get the task type (CompoundTask or PrimitiveTask) for the suffix
          task_type = task.__struct__ |> Module.split() |> List.last() |> String.downcase()
          new_name = "#{name}_from_#{task_type}"

          # Create a new task with the new name
          renamed_task = %{task | name: new_name}

          {
            Map.put(renamed_map, name, new_name),
            Map.put(new_tasks, new_name, renamed_task)
          }
        else
          {renamed_map, Map.put(new_tasks, name, task)}
        end
      end)

    {renamed_map, new_tasks}
  end

  defp rename_task_references(tasks, renamed_tasks) do
    Map.new(tasks, fn {name, task} -> {name, update_task_references(task, renamed_tasks)} end)
  end

  defp update_task_references(%CompoundTask{} = task, renamed_tasks) do
    %{task | methods: Enum.map(task.methods, &update_method_references(&1, renamed_tasks))}
  end

  defp update_task_references(%PrimitiveTask{} = task, _renamed_tasks), do: task

  defp update_method_references(%Method{} = method, renamed_tasks) do
    %{
      method
      | subtasks: Enum.map(method.subtasks, &Map.get(renamed_tasks, &1, &1)),
        ordering:
          Enum.map(method.ordering, fn {before_task, after_task} ->
            {
              Map.get(renamed_tasks, before_task, before_task),
              Map.get(renamed_tasks, after_task, after_task)
            }
          end)
    }
  end
end
