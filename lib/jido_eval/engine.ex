defmodule Jido.Eval.Engine do
  @moduledoc """
  Main execution coordinator for Jido Eval.

  Provides both synchronous and asynchronous evaluation execution with
  Task supervision and real-time monitoring capabilities.

  ## Architecture

  - **Synchronous Mode**: Direct evaluation with blocking execution
  - **Asynchronous Mode**: Task-supervised evaluation with progress tracking
  - **Task Concurrency**: Uses Task.async_stream for efficient parallel processing
  - **Registry Integration**: Real-time progress querying via Agent processes
  - **Telemetry Events**: Comprehensive monitoring support

  ## Examples

      # Synchronous evaluation
      {:ok, result} = Jido.Eval.Engine.evaluate_sync(dataset, config)

      # Asynchronous evaluation with monitoring
      {:ok, run_id} = Jido.Eval.Engine.start_evaluation(dataset, config)
      
      # Check progress
      {:ok, progress} = Jido.Eval.Engine.get_progress(run_id)

      # Wait for completion
      {:ok, result} = Jido.Eval.Engine.await_result(run_id, 30_000)
  """

  require Logger

  alias Jido.Eval.{Config, Result, Dataset}
  alias Jido.Eval.Engine.Run

  @registry_name Jido.Eval.Engine.Registry
  @task_supervisor_name Jido.Eval.Engine.TaskSupervisor

  @doc """
  Start an asynchronous evaluation run with Task supervision.

  Creates a supervised Task and starts evaluation in the background.
  Returns immediately with a run ID for progress tracking.

  ## Parameters

  - `dataset` - Dataset implementing the Dataset protocol
  - `config` - Evaluation configuration
  - `metrics` - List of metric atoms or modules
  - `opts` - Additional options

  ## Returns

  - `{:ok, run_id}` - Evaluation started successfully
  - `{:error, reason}` - Failed to start evaluation

  ## Examples

      {:ok, run_id} = Jido.Eval.Engine.start_evaluation(
        dataset,
        %Jido.Eval.Config{},
        [:faithfulness, :context_precision]
      )

      # Monitor progress
      :telemetry.attach([:jido, :eval, :progress], handler_fn, nil)
  """
  @spec start_evaluation(Dataset.t(), Config.t(), [atom()], keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def start_evaluation(dataset, config, metrics, _opts \\ []) do
    with {:ok, config} <- Config.ensure_run_id(config) do
      # Create Agent for progress tracking
      start_time = DateTime.utc_now()

      {:ok, agent} =
        Agent.start_link(fn ->
          %{
            run_id: config.run_id,
            completed: 0,
            total: Dataset.count(dataset),
            started_at: start_time
          }
        end)

      # Start evaluation task
      task =
        Task.Supervisor.async_nolink(
          @task_supervisor_name,
          fn -> Run.execute(dataset, config, metrics, agent) end
        )

      # Register the run
      Registry.register(@registry_name, config.run_id, %{task: task, agent: agent})

      {:ok, config.run_id}
    end
  end

  @doc """
  Execute evaluation synchronously.

  Blocks until evaluation completes and returns the final result.
  Uses the same Task architecture but waits for completion.

  ## Parameters

  - `dataset` - Dataset implementing the Dataset protocol
  - `config` - Evaluation configuration
  - `metrics` - List of metric atoms or modules
  - `opts` - Additional options (timeout, etc.)

  ## Returns

  - `{:ok, result}` - Evaluation completed successfully
  - `{:error, reason}` - Evaluation failed

  ## Examples

      {:ok, result} = Jido.Eval.Engine.evaluate_sync(
        dataset,
        config,
        [:faithfulness, :context_precision],
        timeout: 30_000
      )

      IO.inspect(result.summary_stats)
  """
  @spec evaluate_sync(Dataset.t(), Config.t(), [atom()], keyword()) ::
          {:ok, Result.t()} | {:error, term()}
  def evaluate_sync(dataset, config, metrics, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, config.run_config.timeout)

    with {:ok, run_id} <- start_evaluation(dataset, config, metrics, opts),
         {:ok, result} <- await_result(run_id, timeout) do
      {:ok, result}
    end
  end

  @doc """
  Get current progress for a running evaluation.

  ## Parameters

  - `run_id` - Evaluation run identifier

  ## Returns

  - `{:ok, progress}` - Current progress information
  - `{:error, :not_found}` - Run not found or completed
  - `{:error, reason}` - Other error

  ## Examples

      {:ok, current_progress} = Jido.Eval.Engine.get_progress(run_id)
      IO.inspect(current_progress)
  """
  @spec get_progress(String.t()) :: {:ok, map()} | {:error, term()}
  def get_progress(run_id) do
    case Registry.lookup(@registry_name, run_id) do
      [{_pid, %{agent: agent}}] ->
        try do
          progress =
            Agent.get(agent, fn state ->
              elapsed_ms = DateTime.diff(DateTime.utc_now(), state.started_at, :millisecond)
              Map.put(state, :elapsed_ms, elapsed_ms)
            end)

          {:ok, progress}
        catch
          :exit, _ -> {:error, :process_unavailable}
        end

      [] ->
        {:error, :not_found}
    end
  end

  @doc """
  Wait for evaluation result with timeout.

  ## Parameters

  - `run_id` - Evaluation run identifier
  - `timeout` - Maximum wait time in milliseconds

  ## Returns

  - `{:ok, result}` - Evaluation completed
  - `{:error, :timeout}` - Evaluation timed out
  - `{:error, reason}` - Other error

  ## Examples

      {:ok, result} = Jido.Eval.Engine.await_result(run_id, 30_000)
  """
  @spec await_result(String.t(), non_neg_integer()) :: {:ok, Result.t()} | {:error, term()}
  def await_result(run_id, timeout) do
    case Registry.lookup(@registry_name, run_id) do
      [{_pid, %{task: task, agent: agent}}] ->
        case Task.yield(task, timeout) do
          {:ok, result} ->
            # Clean up agent
            Agent.stop(agent)
            {:ok, result}

          nil ->
            # Task didn't complete within timeout
            Task.shutdown(task, :brutal_kill)
            Agent.stop(agent)
            {:error, :timeout}

          {:exit, reason} ->
            Agent.stop(agent)
            {:error, {:task_failed, reason}}
        end

      [] ->
        {:error, :not_found}
    end
  end

  @doc """
  Cancel a running evaluation.

  ## Parameters

  - `run_id` - Evaluation run identifier

  ## Returns

  - `:ok` - Cancellation initiated
  - `{:error, :not_found}` - Run not found

  ## Examples

      :ok = Jido.Eval.Engine.cancel_evaluation(run_id)
  """
  @spec cancel_evaluation(String.t()) :: :ok | {:error, term()}
  def cancel_evaluation(run_id) do
    case Registry.lookup(@registry_name, run_id) do
      [{_pid, %{task: task, agent: agent}}] ->
        # Mark as cancelled in progress  
        Agent.update(agent, &Map.put(&1, :cancelled, true))
        Task.shutdown(task, :brutal_kill)
        :ok

      [] ->
        {:error, :not_found}
    end
  end

  @doc """
  List currently running evaluations.

  ## Returns

  - `{:ok, runs}` - List of active run information

  ## Examples

      {:ok, runs} = Jido.Eval.Engine.list_running()
      IO.inspect(length(runs))
  """
  @spec list_running() :: {:ok, [map()]}
  def list_running do
    runs =
      Registry.select(@registry_name, [{{:"$1", :"$2", :"$3"}, [], [{{:"$1", :"$2", :"$3"}}]}])
      |> Enum.map(fn {run_id, _pid, %{task: task, agent: agent}} ->
        try do
          progress = Agent.get(agent, & &1)
          %{run_id: run_id, task_pid: task.pid, progress: progress}
        catch
          :exit, _ -> %{run_id: run_id, task_pid: task.pid, progress: :unavailable}
        end
      end)

    {:ok, runs}
  end
end
