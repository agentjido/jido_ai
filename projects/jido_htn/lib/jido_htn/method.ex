defmodule Jido.HTN.Method do
  @moduledoc """
  Represents a method in HTN planning, which describes how to decompose a compound task into subtasks.
  """

  alias __MODULE__

  @type ordering_constraint :: {String.t(), String.t()}
  @type t :: %Method{
          name: String.t() | nil,
          priority: non_neg_integer() | nil,
          conditions: list(),
          subtasks: list(),
          ordering: list(ordering_constraint)
        }

  defstruct [:name, :priority, conditions: [], subtasks: [], ordering: []]

  @doc """
  Creates a new Method struct with the given options.
  """
  def new(opts \\ []) do
    struct(Method, opts)
  end

  @doc """
  Validates the ordering constraints of a method.
  Raises ArgumentError if:
  - Any task in the ordering constraints doesn't exist in subtasks
  - There are cycles in the ordering constraints
  """
  def validate_ordering!(%Method{subtasks: [], ordering: _}) do
    :ok
  end

  def validate_ordering!(%Method{subtasks: subtasks, ordering: ordering}) do
    # Check that all tasks in ordering exist in subtasks
    task_names = MapSet.new(subtasks)

    Enum.each(ordering, fn {before, next_task} ->
      unless before in task_names and next_task in task_names do
        raise ArgumentError, "Invalid ordering constraint: tasks must be in subtasks list"
      end
    end)

    # Check for cycles using a directed graph
    graph = :digraph.new()

    try do
      # Add vertices
      Enum.each(subtasks, &:digraph.add_vertex(graph, &1))

      # Add edges
      Enum.each(ordering, fn {before, next_task} ->
        :digraph.add_edge(graph, before, next_task)
      end)

      # Check for cycles
      case :digraph.get_cycle(graph, hd(subtasks)) do
        false ->
          :ok

        cycle ->
          raise ArgumentError,
                "Cyclic dependency detected in ordering constraints: #{inspect(cycle)}"
      end
    after
      :digraph.delete(graph)
    end

    :ok
  end

  @doc """
  Orders the subtasks according to the ordering constraints.
  Returns a list of subtasks in the correct order.
  """
  def order_subtasks(%Method{subtasks: subtasks, ordering: []}) do
    subtasks
  end

  def order_subtasks(%Method{subtasks: subtasks, ordering: ordering}) do
    graph = :digraph.new()

    try do
      # Add vertices for all tasks
      Enum.each(subtasks, &:digraph.add_vertex(graph, &1))

      # Add edges for ordering constraints
      Enum.each(ordering, fn {before, next_task} ->
        :digraph.add_edge(graph, before, next_task)
      end)

      # Get a topological ordering
      case :digraph_utils.topsort(graph) do
        false -> subtasks
        ordered_names -> ordered_names
      end
    after
      :digraph.delete(graph)
    end
  end
end
