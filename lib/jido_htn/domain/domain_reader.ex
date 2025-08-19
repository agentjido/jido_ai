defmodule Jido.HTN.Domain.ReadHelpers do
  @moduledoc false
  use ExDbug, enabled: false

  alias Jido.HTN.CompoundTask
  alias Jido.HTN.Domain
  alias Jido.HTN.PrimitiveTask

  @doc """
  Retrieves a primitive task from the domain by name.
  """
  @spec get_primitive(Domain.t(), String.t()) :: {:ok, PrimitiveTask.t()} | {:error, String.t()}
  def get_primitive(%Domain{tasks: tasks}, name) when is_binary(name) do
    dbug("Getting primitive task: #{name}")

    case Map.get(tasks, name) do
      %PrimitiveTask{} = task ->
        {:ok, task}

      %CompoundTask{} ->
        dbug("Task '#{name}' is not a primitive task")
        {:error, "Task '#{name}' is not a primitive task"}

      nil ->
        dbug("Task '#{name}' not found")
        {:error, "Task '#{name}' not found"}
    end
  end

  def get_primitive(_, _) do
    dbug("Invalid arguments for get_primitive")
    {:error, "Invalid arguments for get_primitive"}
  end

  @doc """
  Retrieves a compound task from the domain by name.
  """
  @spec get_compound(Domain.t(), String.t()) :: {:ok, CompoundTask.t()} | {:error, String.t()}
  def get_compound(%Domain{tasks: tasks}, name) when is_binary(name) do
    dbug("Getting compound task: #{name}")

    case Map.get(tasks, name) do
      %CompoundTask{} = task ->
        {:ok, task}

      %PrimitiveTask{} ->
        dbug("Task '#{name}' is not a compound task")
        {:error, "Task '#{name}' is not a compound task"}

      nil ->
        dbug("Task '#{name}' not found")
        {:error, "Task '#{name}' not found"}
    end
  end

  def get_compound(_, _) do
    dbug("Invalid arguments for get_compound")
    {:error, "Invalid arguments for get_compound"}
  end

  @doc """
  Converts the domain's tasks to a map.
  """
  @spec tasks_to_map(Domain.t()) :: %{String.t() => CompoundTask.t() | PrimitiveTask.t()}
  def tasks_to_map(%Domain{tasks: tasks}) do
    dbug("Converting tasks to map")
    tasks
  end

  @doc """
  Lists all task names in the domain.
  """
  @spec list_tasks(Domain.t()) :: [String.t()]
  def list_tasks(%Domain{tasks: tasks}) do
    dbug("Listing all tasks")
    Map.keys(tasks)
  end

  @doc """
  Lists all allowed workflows in the domain.
  """
  @spec list_allowed_workflows(Domain.t()) :: [String.t()]
  def list_allowed_workflows(%Domain{allowed_workflows: allowed_ops}) do
    dbug("Listing allowed workflows")
    Map.keys(allowed_ops)
  end

  @doc """
  Lists all callback names in the domain.
  """
  @spec list_callbacks(Domain.t()) :: [String.t()]
  def list_callbacks(%Domain{callbacks: callbacks}) do
    dbug("Listing callbacks")
    Map.keys(callbacks)
  end
end
