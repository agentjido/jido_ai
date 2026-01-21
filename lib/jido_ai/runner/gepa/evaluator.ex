defmodule Jido.AI.Runner.GEPA.Evaluator do
  @moduledoc """
  Evaluation agent spawning system for GEPA prompt optimization.

  This module implements Section 1.2.1 of the GEPA implementation plan, providing
  parallel prompt evaluation through spawned Jido agents. Each prompt candidate is
  evaluated in an isolated agent process, enabling concurrent testing of multiple
  prompt variants while capturing comprehensive execution data.

  ## Key Features

  - **Agent Spawning**: Creates isolated Jido.AI.Agent processes for evaluation
  - **Prompt Injection**: Merges prompt candidates with base task configuration
  - **Timeout Enforcement**: Prevents runaway evaluations with configurable timeouts
  - **Concurrent Execution**: Parallel evaluation with configurable parallelism limits
  - **Trajectory Collection**: Captures execution paths, metrics, and results (placeholder for Section 1.2.2)

  ## Architecture

  The evaluator spawns a separate Jido agent for each prompt candidate to be evaluated:

  1. Merge prompt candidate with base agent configuration
  2. Spawn agent process with merged configuration
  3. Execute task with timeout enforcement
  4. Collect results including metrics and trajectory
  5. Terminate agent process and cleanup resources

  ## Configuration

  - `:task` - Task definition for evaluation (required)
  - `:parallelism` - Maximum concurrent evaluations (default: 5)
  - `:timeout` - Evaluation timeout in milliseconds (default: 30_000)
  - `:agent_opts` - Base agent configuration options (default: [])

  ## Usage

      # Evaluate a single prompt
      {:ok, result} = Evaluator.evaluate_prompt(
        "Solve this step by step",
        task: %{type: :reasoning, benchmark: "GSM8K"},
        timeout: 30_000
      )

      # Evaluate multiple prompts concurrently
      prompts = ["Prompt 1", "Prompt 2", "Prompt 3"]
      results = Evaluator.evaluate_batch(prompts,
        task: %{type: :reasoning},
        parallelism: 2,
        timeout: 30_000
      )

  ## Result Structure

  Each evaluation returns:
  ```elixir
  %{
    prompt: "evaluated prompt text",
    fitness: 0.85,  # Fitness score (0.0-1.0)
    metrics: %{
      duration_ms: 1234,
      success: true,
      # Additional task-specific metrics
    },
    trajectory: %{
      # Execution path data (Section 1.2.2)
    },
    error: nil  # Error information if evaluation failed
  }
  ```

  ## Error Handling

  - **Timeout**: Returns result with `:timeout` error
  - **Agent Crash**: Returns result with `:agent_crashed` error
  - **Evaluation Failure**: Returns result with specific error reason
  - All errors preserve partial results when available

  ## Implementation Status

  - [x] 1.2.1.1 Agent spawning using Jido's agent factory with prompt injection
  - [x] 1.2.1.2 Configuration merging for prompt candidates
  - [x] 1.2.1.3 Timeout enforcement
  - [x] 1.2.1.4 Concurrent execution with parallelism control
  """

  use TypedStruct
  require Logger

  alias Jido.Agent.Server
  alias Jido.AI.Agent
  alias Jido.AI.Runner.GEPA.Metrics
  alias Jido.AI.Runner.GEPA.Trajectory
  alias Jido.Signal

  # Type definitions

  typedstruct module: EvaluationConfig do
    @moduledoc """
    Configuration for prompt evaluation.
    """
    field(:task, map(), enforce: true)
    field(:parallelism, pos_integer(), default: 5)
    field(:timeout, pos_integer(), default: 30_000)
    field(:agent_opts, keyword(), default: [])
  end

  typedstruct module: EvaluationResult do
    @moduledoc """
    Result of a single prompt evaluation.
    """
    field(:prompt, String.t(), enforce: true)
    field(:fitness, float() | nil, default: nil)
    field(:metrics, map(), default: %{})
    field(:trajectory, Trajectory.t() | nil)
    field(:error, term() | nil, default: nil)
  end

  @type prompt :: String.t()
  @type evaluation_opts :: keyword()

  # Public API

  @doc """
  Evaluates a single prompt candidate.

  ## Options

  - `:task` - Task definition (required)
  - `:timeout` - Evaluation timeout in ms (default: 30_000)
  - `:agent_opts` - Additional agent configuration (default: [])

  ## Examples

      {:ok, result} = Evaluator.evaluate_prompt(
        "Think step by step",
        task: %{type: :reasoning},
        timeout: 30_000
      )
  """
  @spec evaluate_prompt(prompt(), evaluation_opts()) ::
          {:ok, EvaluationResult.t()} | {:error, term()}
  def evaluate_prompt(prompt, opts) when is_binary(prompt) and is_list(opts) do
    config = build_config!(opts)

    Logger.debug(
      "Evaluating prompt (length: #{String.length(prompt)}, timeout: #{config.timeout})"
    )

    case spawn_and_evaluate(prompt, config) do
      {:ok, result} ->
        Logger.debug(
          "Prompt evaluation succeeded (fitness: #{result.fitness}, duration: #{result.metrics[:duration_ms]}ms)"
        )

        {:ok, result}

      {:error, reason} = error ->
        Logger.warning(
          "Prompt evaluation failed: #{inspect(reason)} - #{String.slice(prompt, 0..50)}"
        )

        error
    end
  end

  @doc """
  Evaluates multiple prompts concurrently with parallelism control.

  ## Options

  - `:task` - Task definition (required)
  - `:parallelism` - Maximum concurrent evaluations (default: 5)
  - `:timeout` - Evaluation timeout in ms (default: 30_000)
  - `:agent_opts` - Additional agent configuration (default: [])

  ## Examples

      results = Evaluator.evaluate_batch(
        ["Prompt 1", "Prompt 2", "Prompt 3"],
        task: %{type: :reasoning},
        parallelism: 2,
        timeout: 30_000
      )

      # Returns list of results in same order as input prompts
  """
  @spec evaluate_batch(list(prompt()), evaluation_opts()) :: list(EvaluationResult.t())
  def evaluate_batch(prompts, opts) when is_list(prompts) and is_list(opts) do
    config = build_config!(opts)

    Logger.info(
      "Starting batch evaluation (#{length(prompts)} prompts, parallelism: #{config.parallelism}, timeout: #{config.timeout})"
    )

    start_time = System.monotonic_time(:millisecond)

    # Use Task.async_stream for controlled concurrency
    # Zip with prompts to preserve prompt on task exit
    results =
      prompts
      |> Task.async_stream(
        fn prompt -> evaluate_prompt_internal(prompt, config) end,
        max_concurrency: config.parallelism,
        timeout: config.timeout + 5_000,
        # Extra buffer for cleanup
        ordered: true,
        on_timeout: :kill_task
      )
      |> Enum.zip(prompts)
      |> Enum.map(fn
        {{:ok, result}, _prompt} -> result
        {{:exit, reason}, prompt} -> build_error_result(prompt, {:agent_crashed, reason})
      end)

    duration_ms = System.monotonic_time(:millisecond) - start_time
    successful = Enum.count(results, &is_nil(&1.error))
    failed = Enum.count(results, &(not is_nil(&1.error)))

    Logger.info(
      "Batch evaluation complete (#{length(prompts)} total, #{successful} successful, #{failed} failed, #{duration_ms}ms)"
    )

    results
  end

  # Private Functions

  @doc false
  @spec build_config!(evaluation_opts()) :: EvaluationConfig.t()
  defp build_config!(opts) do
    unless Keyword.has_key?(opts, :task) do
      raise ArgumentError, "task configuration is required for evaluation"
    end

    %EvaluationConfig{
      task: Keyword.fetch!(opts, :task),
      parallelism: Keyword.get(opts, :parallelism, 5),
      timeout: Keyword.get(opts, :timeout, 30_000),
      agent_opts: Keyword.get(opts, :agent_opts, [])
    }
  end

  @doc false
  @spec spawn_and_evaluate(prompt(), EvaluationConfig.t()) ::
          {:ok, EvaluationResult.t()} | {:error, term()}
  defp spawn_and_evaluate(prompt, %EvaluationConfig{} = config) do
    start_time = System.monotonic_time(:millisecond)

    # Build agent configuration with prompt injection
    agent_config = build_agent_config(prompt, config)

    # Spawn agent process
    case spawn_evaluation_agent(agent_config) do
      {:ok, agent_pid} ->
        try do
          # Execute evaluation with timeout
          result = execute_evaluation(agent_pid, prompt, config)

          # Calculate duration
          duration_ms = System.monotonic_time(:millisecond) - start_time

          # Add duration to metrics
          updated_result = %{
            result
            | metrics: Map.put(result.metrics, :duration_ms, duration_ms)
          }

          {:ok, updated_result}
        after
          # Ensure agent cleanup
          cleanup_agent(agent_pid)
        end

      {:error, reason} ->
        {:error, {:agent_spawn_failed, reason}}
    end
  end

  @doc false
  @spec evaluate_prompt_internal(prompt(), EvaluationConfig.t()) :: EvaluationResult.t()
  defp evaluate_prompt_internal(prompt, %EvaluationConfig{} = config) do
    case spawn_and_evaluate(prompt, config) do
      {:ok, result} ->
        result

      {:error, reason} ->
        build_error_result(prompt, reason)
    end
  end

  @doc false
  @spec build_agent_config(prompt(), EvaluationConfig.t()) :: keyword()
  defp build_agent_config(prompt, %EvaluationConfig{} = config) do
    # Merge prompt with base agent configuration
    base_opts = config.agent_opts

    # For now, use basic AI agent configuration
    # Section 1.2.2 will add comprehensive configuration for trajectory collection
    agent_opts =
      base_opts
      |> Keyword.put(:agent, Agent)
      |> Keyword.put_new(:skills, [Jido.AI.Skill])
      |> Keyword.put_new(:ai, build_ai_config(prompt, config))

    agent_opts
  end

  @doc false
  @spec build_ai_config(prompt(), EvaluationConfig.t()) :: keyword()
  defp build_ai_config(prompt, %EvaluationConfig{} = _config) do
    # Build AI skill configuration with prompt injection
    [
      # Model should be specified as {provider, opts} tuple
      model: {:openai, model: "gpt-4"},
      # Use injected prompt
      prompt: prompt,
      verbose: false
    ]
  end

  @doc false
  @spec spawn_evaluation_agent(keyword()) :: {:ok, pid()} | {:error, term()}
  defp spawn_evaluation_agent(agent_config) do
    Logger.debug("Spawning evaluation agent")

    case Server.start_link(agent_config) do
      {:ok, pid} ->
        Logger.debug("Evaluation agent spawned: #{inspect(pid)}")
        {:ok, pid}

      {:error, reason} = error ->
        Logger.error("Failed to spawn evaluation agent: #{inspect(reason)}")
        error
    end
  end

  @doc false
  @spec execute_evaluation(pid(), prompt(), EvaluationConfig.t()) :: EvaluationResult.t()
  defp execute_evaluation(agent_pid, prompt, %EvaluationConfig{} = config) do
    Logger.debug(
      "Executing evaluation (agent: #{inspect(agent_pid)}, timeout: #{config.timeout})"
    )

    # Start trajectory collection
    trajectory =
      Trajectory.new(
        metadata: %{
          prompt: prompt,
          task_type: config.task[:type],
          agent_pid: inspect(agent_pid),
          timeout: config.timeout
        }
      )

    # Record evaluation start
    trajectory =
      Trajectory.add_step(trajectory,
        type: :state_change,
        content: "Evaluation started",
        importance: :high,
        metadata: %{phase: :start}
      )

    # Build task signal
    signal = build_task_signal(config.task)

    # Record signal preparation
    trajectory =
      Trajectory.add_step(trajectory,
        type: :action,
        content: "Sending task signal to agent",
        importance: :medium,
        metadata: %{
          signal_type: signal.type,
          task: config.task
        }
      )

    # Execute with timeout
    case Server.call(agent_pid, signal, config.timeout) do
      {:ok, response} ->
        # Record successful response
        trajectory =
          Trajectory.add_step(trajectory,
            type: :observation,
            content: "Received agent response",
            importance: :high,
            metadata: %{
              response_type: response.type,
              has_data: response.data != nil
            }
          )

        # Parse response and calculate fitness
        parse_evaluation_response(prompt, response, config, trajectory)

      {:error, :timeout} ->
        Logger.warning("Evaluation timeout (agent: #{inspect(agent_pid)})")

        # Record timeout
        trajectory =
          Trajectory.add_step(trajectory,
            type: :observation,
            content: "Evaluation timeout",
            importance: :critical,
            metadata: %{error: :timeout}
          )

        trajectory = Trajectory.complete(trajectory, outcome: :timeout, error: :timeout)

        %EvaluationResult{
          prompt: prompt,
          fitness: nil,
          metrics: %{
            success: false,
            timeout: true,
            duration_ms: trajectory.duration_ms || 0
          },
          trajectory: trajectory,
          error: :timeout
        }

      {:error, reason} ->
        Logger.warning(
          "Evaluation failed (agent: #{inspect(agent_pid)}, reason: #{inspect(reason)})"
        )

        # Record failure
        trajectory =
          Trajectory.add_step(trajectory,
            type: :observation,
            content: "Evaluation failed",
            importance: :critical,
            metadata: %{error: reason}
          )

        trajectory = Trajectory.complete(trajectory, outcome: :error, error: reason)

        %EvaluationResult{
          prompt: prompt,
          fitness: nil,
          metrics: %{
            success: false,
            timeout: false,
            duration_ms: trajectory.duration_ms || 0
          },
          trajectory: trajectory,
          error: reason
        }
    end
  end

  @doc false
  @spec build_task_signal(map()) :: Signal.t()
  defp build_task_signal(task) do
    # Build signal based on task type
    # For now, use a simple chat response signal
    # Section 1.2.2 will implement task-specific signal construction
    {:ok, signal} =
      Signal.new(%{
        type: "jido.ai.chat.response",
        data: %{message: task[:prompt] || "Evaluate this task"}
      })

    signal
  end

  @doc false
  @spec parse_evaluation_response(prompt(), Signal.t(), EvaluationConfig.t(), Trajectory.t()) ::
          EvaluationResult.t()
  defp parse_evaluation_response(prompt, response, %EvaluationConfig{} = config, trajectory) do
    # Complete trajectory to calculate final duration
    trajectory = Trajectory.complete(trajectory, outcome: :success)

    # Collect metrics from trajectory and response
    metrics_collection = collect_metrics_from_evaluation(trajectory, response, config)

    # Calculate fitness from aggregated metrics
    fitness = Metrics.calculate_fitness(metrics_collection)

    # Get aggregated statistics
    aggregated_metrics = Metrics.aggregate(metrics_collection)

    # Record fitness calculation
    trajectory =
      Trajectory.add_step(trajectory,
        type: :reasoning,
        content: "Calculated fitness score from metrics",
        importance: :high,
        metadata: %{
          fitness: fitness,
          calculation_method: :metrics_aggregation,
          metrics_summary: aggregated_metrics
        }
      )

    # Add snapshot of final state
    trajectory =
      Trajectory.add_snapshot(trajectory,
        state: %{
          fitness: fitness,
          metrics: aggregated_metrics,
          response: response.data,
          response_type: response.type
        },
        reason: :evaluation_complete,
        metadata: %{final: true}
      )

    # Record completion
    trajectory =
      Trajectory.add_step(trajectory,
        type: :state_change,
        content: "Evaluation completed successfully",
        importance: :high,
        metadata: %{
          fitness: fitness,
          phase: :complete
        }
      )

    %EvaluationResult{
      prompt: prompt,
      fitness: fitness,
      metrics: %{
        success: true,
        timeout: false,
        duration_ms: trajectory.duration_ms || 0,
        response_type: response.type,
        trajectory_steps: length(trajectory.steps),
        trajectory_snapshots: length(trajectory.state_snapshots),
        aggregated: aggregated_metrics
      },
      trajectory: trajectory,
      error: nil
    }
  end

  @doc false
  @spec collect_metrics_from_evaluation(Trajectory.t(), Signal.t(), EvaluationConfig.t()) ::
          Metrics.t()
  defp collect_metrics_from_evaluation(
         %Trajectory{} = trajectory,
         %Signal{} = response,
         %EvaluationConfig{} = config
       ) do
    task_id = config.task[:id] || "default_task"

    metrics =
      Metrics.new(
        metadata: %{
          prompt: trajectory.metadata[:prompt],
          task_type: config.task[:type],
          trajectory_id: trajectory.id
        }
      )

    # Success rate: 1.0 for successful completion, 0.0 for failure
    success_rate = if trajectory.outcome == :success, do: 1.0, else: 0.0

    metrics =
      Metrics.add_metric(metrics, :success_rate, success_rate,
        task_id: task_id,
        metadata: %{outcome: trajectory.outcome}
      )

    # Latency: execution duration in milliseconds
    metrics =
      if trajectory.duration_ms do
        Metrics.add_metric(metrics, :latency, trajectory.duration_ms,
          task_id: task_id,
          metadata: %{started_at: trajectory.started_at, completed_at: trajectory.completed_at}
        )
      else
        metrics
      end

    # Quality score: based on trajectory characteristics
    quality_score = calculate_quality_score(trajectory, response)

    metrics =
      Metrics.add_metric(metrics, :quality_score, quality_score,
        task_id: task_id,
        metadata: %{
          step_count: length(trajectory.steps),
          snapshot_count: length(trajectory.state_snapshots),
          response_type: response.type
        }
      )

    # Accuracy: placeholder for task-specific accuracy measurement
    # In a real implementation, this would be based on comparing output to expected result
    accuracy = calculate_accuracy_score(trajectory, response, config)

    metrics =
      Metrics.add_metric(metrics, :accuracy, accuracy,
        task_id: task_id,
        metadata: %{
          has_response_data: response.data != nil,
          critical_steps: count_critical_steps(trajectory)
        }
      )

    Logger.debug(
      "Collected evaluation metrics (#{trajectory.id}: success_rate=#{success_rate}, quality=#{quality_score}, accuracy=#{accuracy}, duration=#{trajectory.duration_ms}ms)"
    )

    metrics
  end

  @doc false
  @spec calculate_quality_score(Trajectory.t(), Signal.t()) :: float()
  defp calculate_quality_score(%Trajectory{} = trajectory, %Signal{} = _response) do
    # Quality score based on trajectory characteristics
    base_score = 0.5

    # Bonus for having reasonable step count (not too few, not too many)
    step_count = length(trajectory.steps)

    step_score =
      cond do
        step_count >= 5 and step_count <= 20 -> 0.3
        step_count > 20 -> 0.2
        true -> 0.1
      end

    # Bonus for having state snapshots
    snapshot_score = if length(trajectory.state_snapshots) > 0, do: 0.1, else: 0.0

    # Bonus for completing without errors
    completion_score = if trajectory.outcome == :success, do: 0.1, else: -0.2

    (base_score + step_score + snapshot_score + completion_score)
    |> max(0.0)
    |> min(1.0)
  end

  @doc false
  @spec calculate_accuracy_score(Trajectory.t(), Signal.t(), EvaluationConfig.t()) :: float()
  defp calculate_accuracy_score(
         %Trajectory{} = trajectory,
         %Signal{} = response,
         %EvaluationConfig{} = _config
       ) do
    # Placeholder accuracy calculation
    # In a real implementation, this would compare the agent's output to expected results
    # For now, base it on response presence and trajectory completion
    base_accuracy = 0.5

    response_bonus = if response.data != nil, do: 0.3, else: 0.0
    completion_bonus = if trajectory.outcome == :success, do: 0.2, else: 0.0

    (base_accuracy + response_bonus + completion_bonus)
    |> max(0.0)
    |> min(1.0)
  end

  @doc false
  @spec count_critical_steps(Trajectory.t()) :: non_neg_integer()
  defp count_critical_steps(%Trajectory{} = trajectory) do
    trajectory.steps
    |> Enum.count(fn step -> step.importance == :critical or step.importance == :high end)
  end

  @doc false
  @spec cleanup_agent(pid()) :: :ok
  defp cleanup_agent(agent_pid) do
    if Process.alive?(agent_pid) do
      Logger.debug("Cleaning up evaluation agent: #{inspect(agent_pid)}")

      try do
        # Unlink before stopping to prevent EXIT signal from killing calling process
        # This is important for batch evaluations using Task.async_stream
        Process.unlink(agent_pid)
        GenServer.stop(agent_pid, :normal, 1_000)
      catch
        :exit, reason ->
          Logger.debug("Agent cleanup exit: #{inspect(reason)}")
          :ok
      end
    end

    :ok
  end

  @doc false
  @spec build_error_result(prompt(), term()) :: EvaluationResult.t()
  defp build_error_result(prompt, error) do
    # Create a minimal trajectory for error case
    trajectory =
      Trajectory.new(metadata: %{prompt: prompt, error: error})
      |> Trajectory.add_step(
        type: :observation,
        content: "Evaluation failed",
        importance: :critical,
        metadata: %{error: error}
      )
      |> Trajectory.complete(outcome: :error, error: error)

    %EvaluationResult{
      prompt: prompt,
      fitness: nil,
      metrics: %{
        success: false,
        timeout: false,
        duration_ms: trajectory.duration_ms || 0
      },
      trajectory: trajectory,
      error: error
    }
  end
end
