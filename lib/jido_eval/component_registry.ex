defmodule Jido.Eval.ComponentRegistry do
  @moduledoc """
  ETS-based registry for Jido Eval components.

  Manages registration and discovery of evaluation components including
  reporters, stores, broadcasters, processors, and middleware.

  ## Component Types

  - `:reporter` - Output handlers for results
  - `:store` - Persistent storage backends
  - `:broadcaster` - Event publishing systems
  - `:processor` - Data transformation components
  - `:middleware` - Execution wrappers
  - `:metric` - Evaluation metrics

  ## Examples

      iex> Jido.Eval.ComponentRegistry.register(:reporter, MyReporter)
      :ok
      
      iex> Jido.Eval.ComponentRegistry.lookup(:reporter, MyReporter)
      {:ok, MyReporter}
      
      iex> Jido.Eval.ComponentRegistry.list(:reporter)
      [MyReporter]
  """

  @table_name :jido_eval_components

  @type component_type :: :reporter | :store | :broadcaster | :processor | :middleware | :metric
  @type component_name :: module() | atom()

  @doc """
  Start the component registry.

  Creates the ETS table for component storage.

  ## Returns

  - `:ok` - Registry started successfully
  - `{:error, reason}` - Failed to start
  """
  @spec start_link() :: :ok | {:error, any()}
  def start_link do
    case :ets.whereis(@table_name) do
      :undefined ->
        :ets.new(@table_name, [:set, :public, :named_table])
        :ok

      _table ->
        :ok
    end
  end

  @doc """
  Register a component.

  ## Parameters

  - `type` - Component type
  - `module` - Component module

  ## Returns

  - `:ok` - Component registered successfully
  - `{:error, reason}` - Registration failed

  ## Examples

      iex> Jido.Eval.ComponentRegistry.register(:reporter, MyReporter)
      :ok
  """
  @spec register(component_type(), component_name()) :: :ok | {:error, any()}
  def register(type, module)
      when type in [:reporter, :store, :broadcaster, :processor, :middleware, :metric] do
    ensure_table_exists()

    case validate_component(type, module) do
      :ok ->
        :ets.insert(@table_name, {{type, module}, module})
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  def register(type, _module) do
    {:error, {:invalid_type, type}}
  end

  @doc """
  Register a component with a custom name/alias.

  ## Parameters

  - `type` - Component type
  - `name` - Name/alias for the component
  - `module` - Component module

  ## Returns

  - `:ok` - Component registered successfully
  - `{:error, reason}` - Registration failed

  ## Examples

      iex> Jido.Eval.ComponentRegistry.register(:metric, :faithfulness, Jido.Eval.Metrics.Faithfulness)
      :ok
  """
  @spec register(component_type(), component_name(), module()) :: :ok | {:error, any()}
  def register(type, name, module)
      when type in [:reporter, :store, :broadcaster, :processor, :middleware, :metric] do
    ensure_table_exists()

    case validate_component(type, module) do
      :ok ->
        :ets.insert(@table_name, {{type, name}, module})
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  def register(type, _name, _module) do
    {:error, {:invalid_type, type}}
  end

  @doc """
  Lookup a registered component.

  ## Parameters

  - `type` - Component type
  - `name` - Component name/module

  ## Returns

  - `{:ok, module}` - Component found
  - `{:error, :not_found}` - Component not registered

  ## Examples

      iex> Jido.Eval.ComponentRegistry.lookup(:reporter, MyReporter)
      {:ok, MyReporter}
  """
  @spec lookup(component_type(), component_name()) :: {:ok, module()} | {:error, :not_found}
  def lookup(type, name) do
    ensure_table_exists()

    case :ets.lookup(@table_name, {type, name}) do
      [{{^type, ^name}, module}] -> {:ok, module}
      [] -> {:error, :not_found}
    end
  end

  @doc """
  List all registered components of a type.

  ## Parameters

  - `type` - Component type

  ## Returns

  - `[module()]` - List of registered components

  ## Examples

      iex> Jido.Eval.ComponentRegistry.list(:reporter)
      [MyReporter, AnotherReporter]
  """
  @spec list(component_type()) :: [module()]
  def list(type) do
    ensure_table_exists()

    :ets.match(@table_name, {{type, :"$1"}, :"$1"})
    |> List.flatten()
  end

  @doc """
  Clear all registered components.

  Primarily used for testing.

  ## Returns

  - `:ok` - Registry cleared
  """
  @spec clear() :: :ok
  def clear do
    ensure_table_exists()
    :ets.delete_all_objects(@table_name)
    :ok
  end

  # Private functions

  defp ensure_table_exists do
    case :ets.whereis(@table_name) do
      :undefined ->
        :ets.new(@table_name, [:set, :public, :named_table])

      _table ->
        :ok
    end
  end

  defp validate_component(type, module) do
    case type do
      :reporter -> validate_behaviour(module, Jido.Eval.Reporter)
      :store -> validate_behaviour(module, Jido.Eval.Store)
      :broadcaster -> validate_behaviour(module, Jido.Eval.Broadcaster)
      :processor -> validate_behaviour(module, Jido.Eval.Processor)
      :middleware -> validate_behaviour(module, Jido.Eval.Middleware)
      :metric -> validate_behaviour(module, Jido.Eval.Metric)
    end
  end

  defp validate_behaviour(module, behaviour) do
    case Code.ensure_loaded(module) do
      {:module, ^module} ->
        behaviours = module.module_info(:attributes)[:behaviour] || []

        if behaviour in behaviours do
          :ok
        else
          {:error, {:missing_behaviour, behaviour}}
        end

      {:error, reason} ->
        {:error, {:module_load_error, reason}}
    end
  end
end
