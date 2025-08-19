defmodule Jido.Eval.Engine.Sample do
  @moduledoc """
  Sample processing logic for individual evaluation samples.

  Handles the evaluation of a single sample against multiple metrics,
  collecting scores and building structured results.
  """

  require Logger

  alias Jido.Eval.{Config, ComponentRegistry}

  @doc """
  Process a single sample with the given metrics.

  Takes a sample and runs all metrics against it, collecting scores
  and building a structured sample result.

  ## Parameters

  - `sample` - The sample to evaluate
  - `metrics` - List of metric atoms or modules to apply
  - `config` - Evaluation configuration

  ## Returns

  Returns a map containing the sample result with scores for each metric.
  """
  @spec process(term(), [atom()], Config.t()) :: map()
  def process(sample, metrics, config) do
    start_time = System.monotonic_time(:millisecond)

    # Process each metric
    scores =
      metrics
      |> Enum.map(&evaluate_metric(&1, sample, config))
      |> Map.new()

    end_time = System.monotonic_time(:millisecond)
    processing_time = end_time - start_time

    # Extract sample ID and tags
    sample_id = Map.get(sample, :id, nil)
    sample_tags = Map.get(sample, :tags, %{})

    # Build sample result matching expected structure
    %{
      sample_id: sample_id,
      scores:
        scores
        |> Map.new(fn {metric, result} ->
          case result do
            {:error, _} -> {metric, nil}
            score -> {metric, score}
          end
        end),
      latency_ms: processing_time,
      error: extract_error(scores),
      tags: sample_tags,
      metadata: %{}
    }
  end

  # Evaluate a single metric against a sample
  defp evaluate_metric(metric, sample, config) do
    # Resolve metric atom to module
    metric_module =
      case ComponentRegistry.lookup(:metric, metric) do
        {:ok, module} -> module
        # Assume it's already a module
        {:error, _} -> metric
      end

    try do
      case metric_module.evaluate(sample, config, []) do
        {:ok, score} ->
          {metric, score}

        {:error, reason} ->
          Logger.warning("Metric #{metric} failed for sample: #{inspect(reason)}")
          {metric, {:error, reason}}
      end
    rescue
      error ->
        Logger.error("Metric #{metric} crashed: #{inspect(error)}")
        {metric, {:error, {:exception, error}}}
    end
  end

  # Extract first error from scores map, if any
  defp extract_error(scores) do
    scores
    |> Enum.find_value(fn {_metric, result} ->
      case result do
        {:error, reason} -> inspect(reason)
        _ -> nil
      end
    end)
  end
end
