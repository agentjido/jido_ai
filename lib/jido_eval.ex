defmodule Jido.Eval do
  @moduledoc """
  Main public API for Jido Eval.

  Provides convenient functions for evaluating datasets using various metrics
  with both synchronous and asynchronous execution modes.

  ## Quick Start

      # Simple synchronous evaluation
      {:ok, result} = Jido.Eval.evaluate(dataset, metrics: [:faithfulness])

      # Asynchronous with monitoring
      {:ok, run_id} = Jido.Eval.evaluate_async(dataset, metrics: [:faithfulness])

  ## Configuration

  All evaluation options can be configured through the `Jido.Eval.Config` struct:

      config = %Jido.Eval.Config{
        model_spec: "openai:gpt-4o",
        run_config: %Jido.Eval.RunConfig{max_workers: 8}
      }

      {:ok, result} = Jido.Eval.evaluate(dataset, config: config, metrics: [:faithfulness])

  ## Examples

      # Basic evaluation with default config
      dataset = Jido.Eval.Dataset.from_list([
        %Jido.Eval.Sample.SingleTurn{
          user_input: "What is the capital of France?",
          response: "Paris is the capital of France.",
          retrieved_contexts: ["France's capital city is Paris."]
        }
      ])

      {:ok, result} = Jido.Eval.evaluate(dataset, metrics: [:faithfulness])
      IO.inspect(result.summary_stats)

      # Async evaluation with progress monitoring
      {:ok, run_id} = Jido.Eval.evaluate_async(dataset,
        metrics: [:faithfulness, :context_precision]
      )

      # Monitor progress
      {:ok, progress} = Jido.Eval.get_progress(run_id)

      # Wait for result
      {:ok, result} = Jido.Eval.await_result(run_id)
  """

  alias Jido.Eval.{Config, Engine, Dataset}

  @doc """
  Ensure components are bootstrapped before evaluation.

  Checks if ComponentRegistry is running and starts it if needed,
  then registers all built-in metrics.

  ## Returns

  - `:ok` - Bootstrap completed successfully
  - `{:error, reason}` - Bootstrap failed

  ## Examples

      iex> Jido.Eval.ensure_bootstrapped()
      :ok
  """
  @spec ensure_bootstrapped() :: :ok | {:error, term()}
  def ensure_bootstrapped do
    with :ok <- Jido.Eval.ComponentRegistry.start_link(),
         :ok <- Jido.Eval.Metrics.register_all() do
      :ok
    else
      {:error, reason} -> {:error, {:bootstrap_failed, reason}}
    end
  end

  @doc """
  Evaluate a dataset synchronously using specified metrics.

  ## Parameters

  - `dataset` - Dataset implementing the Dataset protocol
  - `opts` - Evaluation options:
    - `:metrics` - List of metric atoms (required)
    - `:config` - Evaluation configuration (optional)
    - `:llm` - LLM model specification (optional)
    - `:timeout` - Timeout for execution (optional)
    - `:run_config` - Execution configuration overrides (optional)
    - `:reporters`, `:stores`, `:broadcasters`, `:processors` - Component configs
    - `:tags` - Metadata tags for the run (optional)

  ## Returns

  - `{:ok, result}` - Evaluation completed successfully
  - `{:error, reason}` - Evaluation failed

  ## Examples

      # Basic synchronous evaluation
      {:ok, result} = Jido.Eval.evaluate(dataset, metrics: [:faithfulness])

      # Custom configuration
      {:ok, result} = Jido.Eval.evaluate(dataset,
        metrics: [:faithfulness, :context_precision],
        llm: "anthropic:claude-3-5-sonnet",
        run_config: %{max_workers: 4, timeout: 60_000},
        tags: %{"experiment" => "ablation_study"}
      )
  """
  @spec evaluate(Dataset.t(), keyword()) :: {:ok, Jido.Eval.Result.t()} | {:error, term()}
  def evaluate(dataset, opts) do
    with :ok <- ensure_bootstrapped() do
      metrics = Keyword.fetch!(opts, :metrics)
      config = build_config(opts)
      timeout = Keyword.get(opts, :timeout, config.run_config.timeout)
      Engine.evaluate_sync(dataset, config, metrics, timeout: timeout)
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Start an asynchronous evaluation of a dataset using specified metrics.

  ## Parameters

  - `dataset` - Dataset implementing the Dataset protocol
  - `opts` - Evaluation options:
    - `:metrics` - List of metric atoms (required)
    - `:config` - Evaluation configuration (optional)
    - `:llm` - LLM model specification (optional)
    - `:run_config` - Execution configuration overrides (optional)
    - `:reporters`, `:stores`, `:broadcasters`, `:processors` - Component configs
    - `:tags` - Metadata tags for the run (optional)

  ## Returns

  - `{:ok, run_id}` - Evaluation started successfully
  - `{:error, reason}` - Failed to start evaluation

  ## Examples

      # Asynchronous execution
      {:ok, run_id} = Jido.Eval.evaluate_async(dataset,
        metrics: [:faithfulness]
      )

      # Monitor progress and get results
      {:ok, progress} = Jido.Eval.get_progress(run_id)
      {:ok, result} = Jido.Eval.await_result(run_id)
  """
  @spec evaluate_async(Dataset.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def evaluate_async(dataset, opts) do
    with :ok <- ensure_bootstrapped() do
      metrics = Keyword.fetch!(opts, :metrics)
      config = build_config(opts)
      Engine.start_evaluation(dataset, config, metrics, opts)
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Get progress information for a running evaluation.

  ## Parameters

  - `run_id` - Evaluation run identifier

  ## Returns

  - `{:ok, progress}` - Current progress information
  - `{:error, reason}` - Run not found or error

  ## Examples

      {:ok, progress} = Jido.Eval.get_progress(run_id)
      IO.inspect(progress)
  """
  @spec get_progress(String.t()) :: {:ok, map()} | {:error, term()}
  defdelegate get_progress(run_id), to: Engine

  @doc """
  Wait for evaluation result with timeout.

  ## Parameters

  - `run_id` - Evaluation run identifier
  - `timeout` - Maximum wait time in milliseconds (default: 30 seconds)

  ## Returns

  - `{:ok, result}` - Evaluation completed successfully
  - `{:error, reason}` - Timeout or other error

  ## Examples

      {:ok, result} = Jido.Eval.await_result(run_id)
      {:ok, result} = Jido.Eval.await_result(run_id, 60_000)
  """
  @spec await_result(String.t(), non_neg_integer()) ::
          {:ok, Jido.Eval.Result.t()} | {:error, term()}
  def await_result(run_id, timeout \\ 30_000) do
    Engine.await_result(run_id, timeout)
  end

  @doc """
  Cancel a running evaluation.

  ## Parameters

  - `run_id` - Evaluation run identifier

  ## Returns

  - `:ok` - Cancellation initiated
  - `{:error, reason}` - Run not found

  ## Examples

      :ok = Jido.Eval.cancel(run_id)
  """
  @spec cancel(String.t()) :: :ok | {:error, term()}
  defdelegate cancel(run_id), to: Engine, as: :cancel_evaluation

  @doc """
  List currently running evaluations.

  ## Returns

  - `{:ok, runs}` - List of active runs with progress

  ## Examples

      {:ok, runs} = Jido.Eval.list_running()
      IO.inspect(length(runs))
  """
  @spec list_running() :: {:ok, [map()]}
  defdelegate list_running(), to: Engine

  @doc """
  Get available metrics.

  ## Returns

  - `{:ok, metrics}` - List of registered metrics

  ## Examples

      {:ok, metrics} = Jido.Eval.list_metrics()
      IO.inspect(length(metrics))
  """
  @spec list_metrics() :: {:ok, [module()]}
  def list_metrics do
    {:ok, Jido.Eval.Metrics.list_available()}
  end

  @doc """
  Quick evaluation with sensible defaults.

  Convenience function for simple evaluations without detailed configuration.

  ## Parameters

  - `dataset` - Dataset to evaluate
  - `metrics` - List of metric atoms (default: [:faithfulness])

  ## Returns

  - `{:ok, result}` - Evaluation completed successfully
  - `{:error, reason}` - Evaluation failed

  ## Examples

      {:ok, result} = Jido.Eval.quick(dataset)
      {:ok, result} = Jido.Eval.quick(dataset, [:faithfulness, :context_precision])
  """
  @spec quick(Dataset.t(), [atom()]) :: {:ok, Jido.Eval.Result.t()} | {:error, term()}
  def quick(dataset, metrics \\ [:faithfulness]) do
    evaluate(dataset, metrics: metrics)
  end

  # Private helper functions

  defp build_config(opts) do
    base_config = Keyword.get(opts, :config, %Config{})

    # Apply option overrides
    config =
      base_config
      |> maybe_update(:model_spec, Keyword.get(opts, :llm))
      |> maybe_update(:reporters, Keyword.get(opts, :reporters))
      |> maybe_update(:stores, Keyword.get(opts, :stores))
      |> maybe_update(:broadcasters, Keyword.get(opts, :broadcasters))
      |> maybe_update(:processors, Keyword.get(opts, :processors))
      |> maybe_update(:tags, Keyword.get(opts, :tags))
      |> maybe_update_run_config(Keyword.get(opts, :run_config))

    # Ensure run_id is set
    {:ok, updated_config} = Config.ensure_run_id(config)
    updated_config
  end

  defp maybe_update(config, _field, nil), do: config
  defp maybe_update(config, field, value), do: Map.put(config, field, value)

  defp maybe_update_run_config(config, nil), do: config

  defp maybe_update_run_config(config, run_config_updates) when is_map(run_config_updates) do
    updated_run_config = Map.merge(config.run_config, run_config_updates)
    Map.put(config, :run_config, updated_run_config)
  end

  defp maybe_update_run_config(config, run_config_updates) when is_list(run_config_updates) do
    updated_run_config = struct(config.run_config, run_config_updates)
    Map.put(config, :run_config, updated_run_config)
  end
end
