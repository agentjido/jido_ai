defmodule Jido.HTN.Domain.Builder do
  @moduledoc false
  defstruct [:domain, :error]

  @type t :: %__MODULE__{
          domain: Domain.t() | nil,
          error: String.t() | nil
        }

  def new(domain), do: %__MODULE__{domain: domain}
  def error(msg), do: %__MODULE__{error: msg}
end

defmodule Jido.HTN.Domain.BuilderHelpers do
  @moduledoc false
  use ExDbug, enabled: false

  alias Jido.HTN.CompoundTask
  alias Jido.HTN.Domain
  alias Jido.HTN.Domain.Builder
  alias Jido.HTN.Method
  alias Jido.HTN.PrimitiveTask

  @doc "Creates a new HTN domain with the given name."
  @spec new(String.t()) :: Builder.t()
  def new(name) when is_binary(name) do
    dbug("Creating new domain: #{name}")
    Builder.new(%Domain{name: name})
  end

  def new(name), do: invalid_input("Domain name must be a string", name)

  @doc "Adds a compound task to the domain."
  @spec compound(Builder.t(), String.t(), keyword()) :: Builder.t()
  def compound(%Builder{domain: domain, error: nil} = builder, name, opts) when is_binary(name) do
    dbug("Adding compound task: #{name}")

    if Map.has_key?(domain.tasks, name) do
      task_exists_error(name)
    else
      methods = opts |> Keyword.get(:methods, []) |> Enum.map(&normalize_method/1)
      task = CompoundTask.new(name, methods)
      %{builder | domain: %{domain | tasks: Map.put(domain.tasks, name, task)}}
    end
  end

  def compound(%Builder{error: nil}, name, _), do: invalid_input("Invalid task name", name)
  def compound(builder, _, _), do: builder

  @doc "Adds a primitive task to the domain."
  @spec primitive(Builder.t(), String.t(), {atom(), keyword()}, keyword()) :: Builder.t()
  def primitive(%Builder{domain: domain, error: nil} = builder, name, {action, params}, opts)
      when is_binary(name) and is_atom(action) do
    dbug("Adding primitive task: #{name}")

    if Map.has_key?(domain.tasks, name) do
      task_exists_error(name)
    else
      primitive_task =
        PrimitiveTask.new(name, {action, params}, normalize_primitive_task_opts(opts))

      %{builder | domain: %{domain | tasks: Map.put(domain.tasks, name, primitive_task)}}
    end
  end

  def primitive(%Builder{domain: domain, error: nil} = builder, name, action, opts) do
    dbug("Adding primitive task: #{name}")

    if Map.has_key?(domain.tasks, name) do
      task_exists_error(name)
    else
      primitive_task = PrimitiveTask.new(name, {action, []}, normalize_primitive_task_opts(opts))
      %{builder | domain: %{domain | tasks: Map.put(domain.tasks, name, primitive_task)}}
    end
  end

  def primitive(%Builder{error: nil}, name, _, _) when not is_binary(name),
    do: invalid_input("Invalid task name", name)

  def primitive(%Builder{error: nil}, _, {action, _}, _) when not is_atom(action),
    do: invalid_input("Invalid action", action)

  def primitive(builder, _, _, _), do: builder

  @doc "Marks a task as a root task in the domain."
  @spec root(Builder.t(), String.t()) :: Builder.t()
  def root(%Builder{domain: domain, error: nil} = builder, name) when is_binary(name) do
    dbug("Marking task as root: #{name}")

    case Map.get(domain.tasks, name) do
      nil ->
        raise ArgumentError, "Cannot mark '#{name}' as root: task not found"

      %CompoundTask{} ->
        %{builder | domain: %{domain | root_tasks: MapSet.put(domain.root_tasks, name)}}

      _ ->
        raise ArgumentError, "Cannot mark '#{name}' as root: must be a compound task"
    end
  end

  def root(%Builder{error: nil}, name), do: invalid_input("Invalid task name", name)
  def root(builder, _), do: builder

  @doc "Allows an workflow to be used in the domain."
  @spec allow(Builder.t(), String.t(), module()) :: Builder.t()
  def allow(%Builder{domain: domain, error: nil} = builder, name, module)
      when is_binary(name) and is_atom(module) do
    dbug("Allowing workflow: #{name}")

    %{
      builder
      | domain: %{domain | allowed_workflows: Map.put(domain.allowed_workflows, name, module)}
    }
  end

  def allow(%Builder{error: nil}, name, _) when not is_binary(name),
    do: invalid_input("Invalid workflow name", name)

  def allow(%Builder{error: nil}, _, module) when not is_atom(module),
    do: invalid_input("Invalid workflow module", module)

  def allow(builder, _, _), do: builder

  @doc "Adds a callback to the domain."
  @spec callback(Builder.t(), String.t(), (map() -> boolean()) | (map() -> map())) :: Builder.t()
  def callback(%Builder{domain: domain, error: nil} = builder, name, callback)
      when is_binary(name) and is_function(callback, 1) do
    dbug("Adding callback: #{name}")

    %{builder | domain: %{domain | callbacks: Map.put(domain.callbacks, name, callback)}}
  end

  def callback(%Builder{error: nil}, name, _) when not is_binary(name),
    do: invalid_input("Invalid callback name", name)

  def callback(%Builder{error: nil}, _, callback) when not is_function(callback, 1),
    do: invalid_input("Invalid callback function", callback)

  def callback(builder, _, _), do: builder

  @doc "Replaces a task in the domain with a new task."
  @spec replace(Domain.t(), String.t(), CompoundTask.t() | PrimitiveTask.t()) ::
          {:ok, Domain.t()} | {:error, String.t()}
  def replace(%Domain{tasks: tasks} = domain, name, new_task)
      when is_binary(name) and
             (is_struct(new_task, CompoundTask) or is_struct(new_task, PrimitiveTask)) do
    dbug("Replacing task: #{name}")

    if Map.has_key?(tasks, name) do
      {:ok, %{domain | tasks: Map.put(tasks, name, new_task)}}
    else
      {:error, "Task '#{name}' not found"}
    end
  end

  def replace(_, _, _), do: {:error, "Invalid arguments for replace"}

  @doc "Builds the final domain or returns an error."
  @spec build(Builder.t()) :: {:ok, Domain.t()} | {:error, String.t()}
  def build(%Builder{domain: domain, error: nil}), do: {:ok, domain}
  def build(%Builder{error: error}), do: {:error, error}

  def build!(%Builder{domain: domain, error: nil}), do: domain
  def build!(%Builder{error: error}), do: raise(error)

  # Private helper functions

  defp normalize_method(%{conditions: conditions, subtasks: subtasks} = method) do
    dbug("Normalizing method")

    normalized =
      struct(Method, %{
        name: Map.get(method, :name),
        priority: Map.get(method, :priority),
        conditions: Enum.map(conditions, &normalize_condition/1),
        subtasks: subtasks,
        ordering: Map.get(method, :ordering, [])
      })

    # Validate ordering constraints before returning
    Method.validate_ordering!(normalized)
    normalized
  end

  defp normalize_method(method) when is_map(method) do
    normalize_method(%{
      name: Map.get(method, :name),
      priority: Map.get(method, :priority),
      conditions: Map.get(method, :conditions, []),
      subtasks: Map.get(method, :subtasks, []),
      ordering: Map.get(method, :ordering, [])
    })
  end

  defp normalize_method(method), do: method

  defp normalize_condition(condition)
       when is_boolean(condition) or is_binary(condition) or is_function(condition, 1),
       do: condition

  defp normalize_primitive_task_opts(opts) do
    dbug("Normalizing primitive task options")
    opts
  end

  defp task_exists_error(name),
    do: Builder.error("Task name '#{name}' already exists in the domain")

  defp invalid_input(msg, value),
    do: Builder.error("#{msg}: #{inspect(value)}")
end
