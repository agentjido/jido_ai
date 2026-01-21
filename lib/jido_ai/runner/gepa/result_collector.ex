defmodule Jido.AI.Runner.GEPA.ResultCollector do
  @moduledoc """
  Result synchronization system collecting evaluation outcomes from concurrent agents.

  This module implements Section 1.2.4 of the GEPA implementation plan, providing
  asynchronous result collection from parallel prompt evaluations with batching,
  failure handling, and partial result support.

  ## Key Features

  - **Async Updates**: Non-blocking result submission via GenServer callbacks
  - **Result Batching**: Aggregates results to reduce message overhead
  - **Failure Handling**: Monitors evaluation processes and handles crashes gracefully
  - **Partial Results**: Supports collecting incomplete results when evaluations timeout
  - **Batch Notifications**: Optional callbacks when result batches complete

  ## Architecture

  The result collector operates as a GenServer that:

  1. Registers expected evaluation tasks with process monitoring
  2. Receives async result submissions via `handle_cast/2`
  3. Monitors evaluation processes for crashes
  4. Batches results periodically to reduce overhead
  5. Provides synchronous and asynchronous result retrieval
  6. Supports partial collection when timeouts occur

  ## Configuration

  - `:batch_size` - Results to accumulate before notification (default: 10)
  - `:batch_timeout` - Maximum time to hold batch in ms (default: 5_000)
  - `:on_batch` - Optional callback when batch completes: `(list(result)) -> any()`
  - `:expected_count` - Expected number of results (optional, for completion detection)
  - `:timeout` - Global timeout for all evaluations in ms (default: 60_000)

  ## Usage

      # Start collector
      {:ok, collector} = ResultCollector.start_link(
        batch_size: 5,
        batch_timeout: 2_000,
        expected_count: 10
      )

      # Register evaluations with monitoring
      task_refs = for prompt <- prompts do
        task = Task.async(fn -> evaluate_prompt(prompt) end)
        ResultCollector.register_evaluation(collector, task.ref, task.pid)
        task.ref
      end

      # Submit results asynchronously (typically done by evaluation tasks)
      ResultCollector.submit_result(collector, task_ref, result)

      # Await all results with timeout
      {:ok, results} = ResultCollector.await_completion(collector, timeout: 30_000)

      # Or retrieve results synchronously at any time
      {:ok, results} = ResultCollector.get_results(collector)

  ## Failure Handling

  - **Process Crash**: Collector monitors registered PIDs and creates error results
  - **Timeout**: Partial results returned when global or per-evaluation timeout expires
  - **Duplicate Submission**: Later submissions ignored, warning logged
  - **Missing Registration**: Submissions for unregistered tasks accepted with warning

  ## Batching Behavior

  Results are batched to reduce message overhead. A batch is flushed when:
  - Batch size reaches configured threshold
  - Batch timeout expires since first result in batch
  - All expected results received
  - Explicit flush requested via `flush_batch/1`

  ## Implementation Status

  - [x] 1.2.4.1 GenServer with async result submission via callbacks
  - [x] 1.2.4.2 Result batching with configurable size and timeout
  - [x] 1.2.4.3 Failure handling via process monitoring
  - [x] 1.2.4.4 Partial result collection on timeout
  """

  use GenServer
  use TypedStruct
  require Logger

  alias Jido.AI.Runner.GEPA.Evaluator.EvaluationResult

  # Type definitions

  typedstruct module: Config do
    @moduledoc """
    Configuration for result collector.
    """
    field(:batch_size, pos_integer(), default: 10)
    field(:batch_timeout, pos_integer(), default: 5_000)
    field(:on_batch, (list(EvaluationResult.t()) -> any()) | nil, default: nil)
    field(:expected_count, pos_integer() | nil, default: nil)
    field(:timeout, pos_integer(), default: 60_000)
  end

  typedstruct module: State do
    @moduledoc """
    Internal state of result collector.
    """
    field(:config, Config.t(), enforce: true)
    field(:pending, %{reference() => pid()}, default: %{})
    field(:results, %{reference() => EvaluationResult.t()}, default: %{})
    field(:current_batch, list(EvaluationResult.t()), default: [])
    field(:batch_started_at, integer() | nil, default: nil)
    field(:batch_timer_ref, reference() | nil, default: nil)
    field(:completion_waiters, list({pid(), reference()}), default: [])
    field(:started_at, integer(), enforce: true)
    field(:global_timeout_ref, reference() | nil, default: nil)
  end

  @type collector_opts :: keyword()
  @type result_ref :: reference()

  # Public API

  @doc """
  Starts a result collector GenServer.

  ## Options

  - `:batch_size` - Results per batch (default: 10)
  - `:batch_timeout` - Max batch hold time in ms (default: 5_000)
  - `:on_batch` - Batch completion callback (optional)
  - `:expected_count` - Expected result count (optional)
  - `:timeout` - Global timeout in ms (default: 60_000)
  - `:name` - GenServer name (optional)

  ## Examples

      {:ok, collector} = ResultCollector.start_link(batch_size: 5)

      {:ok, collector} = ResultCollector.start_link(
        expected_count: 100,
        timeout: 120_000
      )
  """
  @spec start_link(collector_opts()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {gen_opts, collector_opts} = Keyword.split(opts, [:name])
    GenServer.start_link(__MODULE__, collector_opts, gen_opts)
  end

  @doc """
  Registers an evaluation task for result collection with process monitoring.

  The collector will monitor the given PID and create an error result if the
  process crashes before submitting a result.

  ## Parameters

  - `collector` - Collector PID or name
  - `ref` - Unique reference for this evaluation (typically `Task.ref`)
  - `pid` - PID to monitor (typically `Task.pid`)

  ## Examples

      task = Task.async(fn -> evaluate_prompt("prompt") end)
      :ok = ResultCollector.register_evaluation(collector, task.ref, task.pid)
  """
  @spec register_evaluation(GenServer.server(), result_ref(), pid()) :: :ok
  def register_evaluation(collector, ref, pid) when is_reference(ref) and is_pid(pid) do
    GenServer.cast(collector, {:register, ref, pid})
  end

  @doc """
  Submits a result asynchronously.

  Results are submitted via `cast` for non-blocking operation. The collector
  will add the result to the current batch and trigger batch processing if
  thresholds are met.

  ## Parameters

  - `collector` - Collector PID or name
  - `ref` - Reference for this evaluation
  - `result` - EvaluationResult struct

  ## Examples

      ResultCollector.submit_result(collector, task.ref, result)
  """
  @spec submit_result(GenServer.server(), result_ref(), EvaluationResult.t()) :: :ok
  def submit_result(collector, ref, %EvaluationResult{} = result) when is_reference(ref) do
    GenServer.cast(collector, {:submit_result, ref, result})
  end

  @doc """
  Retrieves all collected results synchronously.

  Returns immediately with currently collected results, including any results
  from crashed or timed-out evaluations.

  ## Parameters

  - `collector` - Collector PID or name
  - `opts` - Options (reserved for future use)

  ## Returns

  - `{:ok, results}` - List of collected EvaluationResult structs

  ## Examples

      {:ok, results} = ResultCollector.get_results(collector)
  """
  @spec get_results(GenServer.server(), keyword()) :: {:ok, list(EvaluationResult.t())}
  def get_results(collector, _opts \\ []) do
    GenServer.call(collector, :get_results)
  end

  @doc """
  Awaits completion of all expected evaluations with timeout.

  Blocks until:
  - All expected results are collected, OR
  - The timeout expires, OR
  - The global timeout expires

  When timeout expires, returns partial results collected so far.

  ## Parameters

  - `collector` - Collector PID or name
  - `opts` - Options
    - `:timeout` - Maximum wait time in ms (default: 60_000)

  ## Returns

  - `{:ok, results}` - All expected results collected
  - `{:partial, results}` - Timeout expired, returning partial results
  - `{:error, reason}` - Await failed

  ## Examples

      # Wait up to 30 seconds for all results
      case ResultCollector.await_completion(collector, timeout: 30_000) do
        {:ok, results} ->
          # All results collected successfully
          process_results(results)

        {:partial, results} ->
          # Timeout expired, handle partial results
          handle_partial_results(results)
      end
  """
  @spec await_completion(GenServer.server(), keyword()) ::
          {:ok, list(EvaluationResult.t())}
          | {:partial, list(EvaluationResult.t())}
          | {:error, term()}
  def await_completion(collector, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 60_000)

    try do
      GenServer.call(collector, :await_completion, timeout)
    catch
      :exit, {:timeout, _} ->
        # Timeout expired, get partial results
        {:ok, results} = get_results(collector)
        {:partial, results}
    end
  end

  @doc """
  Flushes the current batch immediately.

  Forces processing of the current batch regardless of batch size or timeout.
  Useful for ensuring all results are processed before shutdown.

  ## Examples

      :ok = ResultCollector.flush_batch(collector)
  """
  @spec flush_batch(GenServer.server()) :: :ok
  def flush_batch(collector) do
    GenServer.cast(collector, :flush_batch)
  end

  @doc """
  Returns statistics about the collector state.

  ## Returns

  Map with keys:
  - `:pending_count` - Number of pending evaluations
  - `:completed_count` - Number of collected results
  - `:batch_count` - Number of results in current batch
  - `:expected_count` - Expected total results (if configured)
  - `:uptime_ms` - Time since collector started

  ## Examples

      stats = ResultCollector.get_stats(collector)
      IO.inspect(stats)
  """
  @spec get_stats(GenServer.server()) :: map()
  def get_stats(collector) do
    GenServer.call(collector, :get_stats)
  end

  # GenServer Callbacks

  @impl GenServer
  def init(opts) do
    config = build_config(opts)

    state = %State{
      config: config,
      started_at: System.monotonic_time(:millisecond)
    }

    # Set global timeout if configured
    state =
      if config.timeout > 0 do
        ref = Process.send_after(self(), :global_timeout, config.timeout)
        %{state | global_timeout_ref: ref}
      else
        state
      end

    Logger.debug(
      "ResultCollector started (batch_size: #{config.batch_size}, batch_timeout: #{config.batch_timeout}, expected_count: #{inspect(config.expected_count)}, timeout: #{config.timeout})"
    )

    {:ok, state}
  end

  @impl GenServer
  def handle_cast({:register, ref, pid}, state) do
    # Monitor the process
    Process.monitor(pid)

    state = %{state | pending: Map.put(state.pending, ref, pid)}

    Logger.debug(
      "Registered evaluation (ref: #{inspect(ref)}, pid: #{inspect(pid)}, pending_count: #{map_size(state.pending)})"
    )

    {:noreply, state}
  end

  @impl GenServer
  def handle_cast({:submit_result, ref, result}, state) do
    cond do
      # Already have this result
      Map.has_key?(state.results, ref) ->
        Logger.warning("Duplicate result submission ignored (ref: #{inspect(ref)})")
        {:noreply, state}

      # Expected result
      Map.has_key?(state.pending, ref) ->
        # Remove from pending
        state = %{state | pending: Map.delete(state.pending, ref)}

        # Add to results
        state = %{state | results: Map.put(state.results, ref, result)}

        # Add to current batch
        state = add_to_batch(state, result)

        Logger.debug(
          "Result submitted (ref: #{inspect(ref)}, fitness: #{inspect(result.fitness)}, pending_count: #{map_size(state.pending)}, completed_count: #{map_size(state.results)})"
        )

        # Check if batch should be flushed
        state = maybe_flush_batch(state)

        # Check if all results collected
        state = maybe_notify_completion(state)

        {:noreply, state}

      # Unexpected result (not registered)
      true ->
        Logger.warning("Result submitted for unregistered evaluation (ref: #{inspect(ref)})")

        # Accept it anyway
        state = %{state | results: Map.put(state.results, ref, result)}
        state = add_to_batch(state, result)
        state = maybe_flush_batch(state)
        state = maybe_notify_completion(state)

        {:noreply, state}
    end
  end

  @impl GenServer
  def handle_cast(:flush_batch, state) do
    state = flush_batch_internal(state)
    {:noreply, state}
  end

  @impl GenServer
  def handle_call(:get_results, _from, state) do
    # Return all collected results as list
    results = Map.values(state.results)
    {:reply, {:ok, results}, state}
  end

  @impl GenServer
  def handle_call(:await_completion, from, state) do
    if complete?(state) do
      # Already complete
      results = Map.values(state.results)
      {:reply, {:ok, results}, state}
    else
      # Not complete, add to waiters
      state = %{state | completion_waiters: [from | state.completion_waiters]}
      {:noreply, state}
    end
  end

  @impl GenServer
  def handle_call(:get_stats, _from, state) do
    uptime_ms = System.monotonic_time(:millisecond) - state.started_at

    stats = %{
      pending_count: map_size(state.pending),
      completed_count: map_size(state.results),
      batch_count: length(state.current_batch),
      expected_count: state.config.expected_count,
      uptime_ms: uptime_ms
    }

    {:reply, stats, state}
  end

  @impl GenServer
  def handle_info({:DOWN, _ref, :process, pid, reason}, state) do
    # Find the evaluation ref for this PID
    case Enum.find(state.pending, fn {_ref, p} -> p == pid end) do
      {eval_ref, ^pid} ->
        Logger.warning(
          "Evaluation process crashed (pid: #{inspect(pid)}, reason: #{inspect(reason)}, ref: #{inspect(eval_ref)})"
        )

        # Create error result
        error_result = %EvaluationResult{
          prompt: "",
          fitness: nil,
          metrics: %{success: false, crashed: true},
          trajectory: nil,
          error: {:agent_crashed, reason}
        }

        # Remove from pending
        state = %{state | pending: Map.delete(state.pending, eval_ref)}

        # Add error result
        state = %{state | results: Map.put(state.results, eval_ref, error_result)}

        # Add to batch
        state = add_to_batch(state, error_result)
        state = maybe_flush_batch(state)
        state = maybe_notify_completion(state)

        {:noreply, state}

      nil ->
        # Process not tracked, ignore
        {:noreply, state}
    end
  end

  @impl GenServer
  def handle_info(:batch_timeout, state) do
    Logger.debug("Batch timeout triggered, flushing batch")
    state = flush_batch_internal(state)
    {:noreply, state}
  end

  @impl GenServer
  def handle_info(:global_timeout, state) do
    Logger.warning(
      "Global timeout reached (pending_count: #{map_size(state.pending)}, completed_count: #{map_size(state.results)})"
    )

    # Flush current batch
    state = flush_batch_internal(state)

    # Create timeout results for all pending evaluations
    state = create_timeout_results(state)

    # Notify all waiters with partial results
    state = notify_waiters(state, :partial)

    {:noreply, state}
  end

  # Private Functions

  @spec build_config(collector_opts()) :: Config.t()
  defp build_config(opts) do
    %Config{
      batch_size: Keyword.get(opts, :batch_size, 10),
      batch_timeout: Keyword.get(opts, :batch_timeout, 5_000),
      on_batch: Keyword.get(opts, :on_batch),
      expected_count: Keyword.get(opts, :expected_count),
      timeout: Keyword.get(opts, :timeout, 60_000)
    }
  end

  @spec add_to_batch(State.t(), EvaluationResult.t()) :: State.t()
  defp add_to_batch(state, result) do
    batch = [result | state.current_batch]

    # Start batch timer if this is the first result in batch
    {state, batch_timer_ref} =
      if state.batch_started_at == nil do
        timer_ref = Process.send_after(self(), :batch_timeout, state.config.batch_timeout)
        started_at = System.monotonic_time(:millisecond)
        {%{state | batch_started_at: started_at}, timer_ref}
      else
        {state, state.batch_timer_ref}
      end

    %{state | current_batch: batch, batch_timer_ref: batch_timer_ref}
  end

  @spec maybe_flush_batch(State.t()) :: State.t()
  defp maybe_flush_batch(state) do
    if length(state.current_batch) >= state.config.batch_size do
      flush_batch_internal(state)
    else
      state
    end
  end

  @spec flush_batch_internal(State.t()) :: State.t()
  defp flush_batch_internal(state) do
    if length(state.current_batch) > 0 do
      # Cancel batch timer if active
      if state.batch_timer_ref do
        Process.cancel_timer(state.batch_timer_ref)
      end

      # Invoke batch callback if configured
      if state.config.on_batch do
        try do
          _ = state.config.on_batch.(Enum.reverse(state.current_batch))
          :ok
        rescue
          error ->
            Logger.error(
              "Batch callback failed (error: #{inspect(error)}, batch_size: #{length(state.current_batch)})"
            )
        end
      end

      Logger.debug("Batch flushed (size: #{length(state.current_batch)})")

      # Clear batch
      %{state | current_batch: [], batch_started_at: nil, batch_timer_ref: nil}
    else
      state
    end
  end

  @spec complete?(State.t()) :: boolean()
  defp complete?(state) do
    expected = state.config.expected_count
    completed = map_size(state.results)

    expected != nil and completed >= expected and map_size(state.pending) == 0
  end

  @spec maybe_notify_completion(State.t()) :: State.t()
  defp maybe_notify_completion(state) do
    if complete?(state) do
      Logger.info(
        "All expected results collected (count: #{map_size(state.results)}, expected: #{state.config.expected_count})"
      )

      notify_waiters(state, :complete)
    else
      state
    end
  end

  @spec notify_waiters(State.t(), :complete | :partial) :: State.t()
  defp notify_waiters(state, status) do
    results = Map.values(state.results)

    reply =
      case status do
        :complete -> {:ok, results}
        :partial -> {:partial, results}
      end

    for waiter <- state.completion_waiters do
      GenServer.reply(waiter, reply)
    end

    %{state | completion_waiters: []}
  end

  @spec create_timeout_results(State.t()) :: State.t()
  defp create_timeout_results(state) do
    # Create timeout results for all pending evaluations
    timeout_results =
      for {ref, _pid} <- state.pending, into: %{} do
        result = %EvaluationResult{
          prompt: "",
          fitness: nil,
          metrics: %{success: false, timeout: true},
          trajectory: nil,
          error: :timeout
        }

        {ref, result}
      end

    # Merge with existing results
    results = Map.merge(state.results, timeout_results)

    # Clear pending
    %{state | pending: %{}, results: results}
  end
end
