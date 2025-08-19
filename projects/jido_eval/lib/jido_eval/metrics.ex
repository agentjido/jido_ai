defmodule Jido.Eval.Metrics do
  @moduledoc """
  Registry and utilities for core evaluation metrics.

  This module provides functions to register and discover built-in metrics,
  as well as utilities for working with metrics in general.

  ## Built-in Metrics

  - `Jido.Eval.Metrics.Faithfulness` - Measures response grounding in contexts
  - `Jido.Eval.Metrics.ContextPrecision` - Measures context relevance to questions

  ## Examples

      # Register all built-in metrics
      Jido.Eval.Metrics.register_all()

      # List available metrics
      metrics = Jido.Eval.Metrics.list_available()

      # Get metric information
      {:ok, info} = Jido.Eval.Metrics.get_info(Jido.Eval.Metrics.Faithfulness)
  """

  alias Jido.Eval.ComponentRegistry
  alias Jido.Eval.Metrics.{Faithfulness, ContextPrecision}

  require Logger

  @built_in_metrics [
    Faithfulness,
    ContextPrecision
  ]

  # Metric aliases for convenient access
  @metric_aliases %{
    Faithfulness => :faithfulness,
    ContextPrecision => :context_precision
  }

  @doc """
  Register all built-in metrics with the ComponentRegistry.

  This function is typically called during application startup to make
  all built-in metrics available for use.

  ## Returns

  - `:ok` - All metrics registered successfully
  - `{:error, reason}` - Registration failed

  ## Examples

      :ok = Jido.Eval.Metrics.register_all()
  """
  @spec register_all() :: :ok | {:error, term()}
  def register_all do
    Logger.debug("Registering built-in evaluation metrics")

    results =
      @built_in_metrics
      |> Enum.map(fn metric ->
        # Register by module name
        module_result = ComponentRegistry.register(:metric, metric)

        # Also register by atom alias for convenient usage
        alias_atom = get_metric_alias(metric)
        alias_result = ComponentRegistry.register(:metric, alias_atom, metric)

        case {module_result, alias_result} do
          {:ok, :ok} ->
            Logger.debug("Registered metric: #{metric.name()} (#{metric}, :#{alias_atom})")
            :ok

          {{:error, reason}, _} ->
            Logger.warning("Failed to register metric #{metric}: #{inspect(reason)}")
            {:error, {metric, reason}}

          {_, {:error, reason}} ->
            Logger.warning("Failed to register metric alias #{alias_atom}: #{inspect(reason)}")
            {:error, {alias_atom, reason}}
        end
      end)

    case Enum.find(results, &match?({:error, _}, &1)) do
      nil ->
        Logger.info("Successfully registered #{length(@built_in_metrics)} built-in metrics")
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  List all available registered metrics.

  ## Returns

  - `[module()]` - List of registered metric modules

  ## Examples

      metrics = Jido.Eval.Metrics.list_available()
      # => [Jido.Eval.Metrics.Faithfulness, Jido.Eval.Metrics.ContextPrecision]
  """
  @spec list_available() :: [module()]
  def list_available do
    ComponentRegistry.list(:metric)
  end

  @doc """
  Get detailed information about a metric.

  ## Parameters

  - `metric` - Metric module

  ## Returns

  - `{:ok, info}` - Metric information map
  - `{:error, reason}` - Failed to get info

  ## Examples

      {:ok, info} = Jido.Eval.Metrics.get_info(Jido.Eval.Metrics.Faithfulness)
      # => {:ok, %{
      #   name: "Faithfulness",
      #   description: "Measures how grounded...",
      #   required_fields: [:response, :retrieved_contexts],
      #   sample_types: [:single_turn],
      #   score_range: {0.0, 1.0}
      # }}
  """
  @spec get_info(module()) :: {:ok, map()} | {:error, term()}
  def get_info(metric) when is_atom(metric) do
    try do
      info = %{
        name: metric.name(),
        description: metric.description(),
        required_fields: metric.required_fields(),
        sample_types: metric.sample_types(),
        score_range: metric.score_range()
      }

      {:ok, info}
    rescue
      exception ->
        {:error, {:metric_info_error, exception}}
    end
  end

  @doc """
  Check if a metric is compatible with a sample.

  ## Parameters

  - `metric` - Metric module  
  - `sample` - Sample to check

  ## Returns

  - `:ok` - Sample is compatible
  - `{:error, reason}` - Sample is not compatible

  ## Examples

      sample = %SingleTurn{response: "Hello", retrieved_contexts: ["Hi"]}
      :ok = Jido.Eval.Metrics.check_compatibility(Faithfulness, sample)
  """
  @spec check_compatibility(module(), Jido.Eval.Metric.sample()) :: :ok | {:error, term()}
  def check_compatibility(metric, sample) do
    Jido.Eval.Metric.validate_sample(sample, metric)
  end

  @doc """
  Find metrics compatible with a given sample.

  ## Parameters

  - `sample` - Sample to find metrics for

  ## Returns

  - `[module()]` - List of compatible metric modules

  ## Examples

      sample = %SingleTurn{response: "Hello", retrieved_contexts: ["Hi"]}
      metrics = Jido.Eval.Metrics.find_compatible(sample)
      # => [Jido.Eval.Metrics.Faithfulness]
  """
  @spec find_compatible(Jido.Eval.Metric.sample()) :: [module()]
  def find_compatible(sample) do
    list_available()
    |> Enum.filter(fn metric ->
      case check_compatibility(metric, sample) do
        :ok -> true
        {:error, _} -> false
      end
    end)
  end

  @doc """
  Get all built-in metric modules.

  Returns the list of metric modules that ship with Jido Eval.

  ## Returns

  - `[module()]` - List of built-in metric modules

  ## Examples

      built_ins = Jido.Eval.Metrics.built_in_metrics()
      # => [Jido.Eval.Metrics.Faithfulness, Jido.Eval.Metrics.ContextPrecision]
  """
  @spec built_in_metrics() :: [module()]
  def built_in_metrics do
    @built_in_metrics
  end

  # Helper function to get metric alias
  defp get_metric_alias(metric) do
    Map.get(@metric_aliases, metric, metric)
  end
end
