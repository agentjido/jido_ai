defmodule Jido.Eval.Engine.Run do
  @moduledoc """
  Task-based evaluation run execution.

  Executes evaluation runs using Task.async_stream for simplified supervision
  and better resource efficiency compared to the previous GenServer-based approach.
  """

  require Logger

  alias Jido.Eval.{Config, Result, Dataset}
  alias Jido.Eval.Engine.Sample

  @doc """
  Execute an evaluation run using Task.async_stream.

  This function processes all samples in the dataset concurrently using
  Task.async_stream, updating progress through an Agent process.

  ## Parameters

  - `dataset` - Dataset implementing the Dataset protocol
  - `config` - Evaluation configuration
  - `metrics` - List of metric atoms or modules
  - `agent` - Agent process for tracking progress

  ## Returns

  Returns the final Result struct after processing all samples.
  """
  @spec execute(Dataset.t(), Config.t(), [atom()], pid()) :: Result.t()
  def execute(dataset, config, metrics, agent) do
    Logger.info("Starting evaluation run #{config.run_id}")

    # Emit start event
    emit_started(config, Dataset.count(dataset))

    # Configure async stream options
    stream_opts = [
      max_concurrency: config.run_config.max_workers,
      timeout: config.run_config.timeout,
      on_timeout: :kill_task
    ]

    # Process samples with concurrent tasks
    result =
      dataset
      |> Dataset.to_stream()
      |> Task.async_stream(&process_sample(&1, metrics, config, agent), stream_opts)
      |> Enum.reduce(Result.new(config.run_id, config), fn
        {:ok, sample_result}, acc ->
          # Update progress
          Agent.update(agent, &Map.update!(&1, :completed, fn x -> x + 1 end))

          # Emit progress event
          progress = Agent.get(agent, & &1)
          emit_progress(config, progress)

          # Add sample result to accumulator
          Result.add_sample_result(acc, sample_result)

        {:exit, reason}, acc ->
          Logger.warning("Sample processing failed: #{inspect(reason)}")

          # Update progress for failed sample
          Agent.update(agent, &Map.update!(&1, :completed, fn x -> x + 1 end))

          # Continue with accumulator (skip failed sample)
          acc
      end)

    # Finalize and emit completion
    final_result = Result.finalize(result)
    emit_completed(config, final_result)

    Logger.info("Completed evaluation run #{config.run_id}")
    final_result
  end

  # Process a single sample with metrics
  defp process_sample(sample, metrics, config, _agent) do
    Sample.process(sample, metrics, config)
  end

  # Telemetry emission helpers
  defp emit_started(config, total_samples) do
    :telemetry.execute(
      [:jido, :eval, :started],
      %{total_samples: total_samples},
      %{run_id: config.run_id, config: config}
    )
  end

  defp emit_progress(config, progress) do
    :telemetry.execute(
      [:jido, :eval, :progress],
      %{completed: progress.completed, total: progress.total},
      %{run_id: config.run_id, progress: progress}
    )
  end

  defp emit_completed(config, result) do
    :telemetry.execute(
      [:jido, :eval, :completed],
      %{total_samples: length(result.sample_results)},
      %{run_id: config.run_id, result: result}
    )
  end
end
