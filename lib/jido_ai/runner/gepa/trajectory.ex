defmodule Jido.AI.Runner.GEPA.Trajectory do
  @moduledoc """
  Trajectory collection system for GEPA prompt evaluation.

  This module implements Section 1.2.2 of the GEPA implementation plan, providing
  comprehensive execution path capture for LLM-guided reflection. It records the
  complete sequence of reasoning steps, actions, observations, and state transitions
  during prompt evaluation.

  ## Key Features

  - **Step Recording**: Captures CoT reasoning steps, tool calls, and observations
  - **Structured Logging**: Timestamps and context preservation for all events
  - **State Snapshots**: Intermediate state captures for failure analysis
  - **Trajectory Filtering**: Removes noise while preserving critical information

  ## Architecture

  A trajectory consists of:
  1. **Steps**: Sequential execution events (reasoning, actions, observations)
  2. **State Snapshots**: Periodic captures of agent state
  3. **Metadata**: Context, configuration, and outcome information
  4. **Timing Data**: Start/end times and duration for analysis

  ## Trajectory Structure

  ```elixir
  %Trajectory{
    id: "traj_123",
    steps: [%Step{...}, %Step{...}],
    state_snapshots: [%StateSnapshot{...}],
    started_at: DateTime.utc_now(),
    completed_at: DateTime.utc_now(),
    duration_ms: 1234,
    metadata: %{prompt: "...", task_type: :reasoning},
    outcome: :success,
    error: nil
  }
  ```

  ## Step Types

  - `:reasoning` - Chain-of-thought reasoning steps
  - `:action` - Actions taken by the agent (tool calls, commands)
  - `:observation` - Results observed from actions
  - `:tool_call` - Specific tool invocations
  - `:state_change` - State transitions in the agent

  ## Usage

      # Start a new trajectory
      trajectory = Trajectory.new(prompt: "Solve this problem", task_type: :reasoning)

      # Record reasoning step
      trajectory = Trajectory.add_step(trajectory,
        type: :reasoning,
        content: "Let me break this down step by step...",
        metadata: %{cot_depth: 1}
      )

      # Record action
      trajectory = Trajectory.add_step(trajectory,
        type: :action,
        content: "Calling calculator tool",
        metadata: %{tool: "calculator", args: [2, 2]}
      )

      # Capture state snapshot
      trajectory = Trajectory.add_snapshot(trajectory,
        state: %{variables: %{x: 42}},
        reason: :checkpoint
      )

      # Complete trajectory
      trajectory = Trajectory.complete(trajectory, outcome: :success)

      # Filter for important steps
      filtered = Trajectory.filter(trajectory, min_importance: :medium)

  ## Implementation Status

  - [x] 1.2.2.1 Trajectory collector capturing CoT steps, actions, and observations
  - [x] 1.2.2.2 Structured logging with timestamps and context preservation
  - [x] 1.2.2.3 Intermediate state snapshots enabling detailed failure analysis
  - [x] 1.2.2.4 Trajectory filtering removing irrelevant details
  """

  use TypedStruct
  require Logger

  # Type definitions

  @type step_type :: :reasoning | :action | :observation | :tool_call | :state_change
  @type importance :: :low | :medium | :high | :critical
  @type outcome :: :success | :failure | :timeout | :error | :partial

  typedstruct module: Step do
    @moduledoc """
    Individual execution step in a trajectory.

    Represents a single event in the agent's execution path, such as
    a reasoning step, action taken, or observation made.
    """

    field(:id, String.t(), enforce: true)
    field(:type, Jido.AI.Runner.GEPA.Trajectory.step_type(), enforce: true)
    field(:content, term(), enforce: true)
    field(:timestamp, DateTime.t(), enforce: true)
    field(:duration_ms, non_neg_integer() | nil)
    field(:metadata, map(), default: %{})
    field(:context, map(), default: %{})
    field(:importance, Jido.AI.Runner.GEPA.Trajectory.importance(), default: :medium)
    field(:parent_step_id, String.t() | nil)
  end

  typedstruct module: StateSnapshot do
    @moduledoc """
    Point-in-time capture of agent state.

    Enables detailed failure analysis by preserving agent state at
    critical points during execution.
    """

    field(:id, String.t(), enforce: true)
    field(:timestamp, DateTime.t(), enforce: true)
    field(:state, map(), default: %{})
    field(:reason, atom(), default: :checkpoint)
    field(:step_id, String.t() | nil)
    field(:metadata, map(), default: %{})
  end

  typedstruct do
    # Complete execution trajectory for a prompt evaluation.
    # Contains the full sequence of steps, state snapshots, timing data,
    # and outcome information for reflection analysis.

    field(:id, String.t(), enforce: true)
    field(:steps, list(Step.t()), default: [])
    field(:state_snapshots, list(StateSnapshot.t()), default: [])
    field(:started_at, DateTime.t(), enforce: true)
    field(:completed_at, DateTime.t() | nil)
    field(:duration_ms, non_neg_integer() | nil)
    field(:metadata, map(), default: %{})
    field(:outcome, Jido.AI.Runner.GEPA.Trajectory.outcome() | nil)
    field(:error, term() | nil)
    field(:filtered, boolean(), default: false)
  end

  # Public API

  @doc """
  Creates a new trajectory for tracking execution.

  ## Options

  - `:metadata` - Additional context information (default: %{})
  - `:id` - Custom trajectory ID (default: auto-generated)

  ## Examples

      trajectory = Trajectory.new(
        metadata: %{prompt: "Solve this", task_type: :reasoning}
      )
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    id = Keyword.get(opts, :id, generate_trajectory_id())
    metadata = Keyword.get(opts, :metadata, %{})

    %__MODULE__{
      id: id,
      steps: [],
      state_snapshots: [],
      started_at: DateTime.utc_now(),
      completed_at: nil,
      duration_ms: nil,
      metadata: metadata,
      outcome: nil,
      error: nil,
      filtered: false
    }
  end

  @doc """
  Adds an execution step to the trajectory.

  ## Options

  - `:type` - Step type (required): :reasoning, :action, :observation, :tool_call, :state_change
  - `:content` - Step content (required)
  - `:metadata` - Additional step metadata (default: %{})
  - `:context` - Execution context at this step (default: %{})
  - `:importance` - Step importance level (default: :medium)
  - `:parent_step_id` - Parent step ID for nested steps (default: nil)
  - `:duration_ms` - Step duration in milliseconds (default: nil)

  ## Examples

      trajectory = Trajectory.add_step(trajectory,
        type: :reasoning,
        content: "Let me think step by step...",
        importance: :high,
        metadata: %{cot_depth: 1}
      )

      trajectory = Trajectory.add_step(trajectory,
        type: :tool_call,
        content: %{tool: "calculator", args: [2, 2], result: 4},
        importance: :critical,
        metadata: %{tool_name: "calculator"}
      )
  """
  @spec add_step(t(), keyword()) :: t()
  def add_step(%__MODULE__{} = trajectory, opts) do
    unless Keyword.has_key?(opts, :type) and Keyword.has_key?(opts, :content) do
      raise ArgumentError, "add_step/2 requires :type and :content options"
    end

    step = %Step{
      id: generate_step_id(),
      type: Keyword.fetch!(opts, :type),
      content: Keyword.fetch!(opts, :content),
      timestamp: DateTime.utc_now(),
      duration_ms: Keyword.get(opts, :duration_ms),
      metadata: Keyword.get(opts, :metadata, %{}),
      context: Keyword.get(opts, :context, %{}),
      importance: Keyword.get(opts, :importance, :medium),
      parent_step_id: Keyword.get(opts, :parent_step_id)
    }

    Logger.debug(
      "Recording trajectory step (trajectory_id: #{trajectory.id}, step_type: #{step.type}, importance: #{step.importance})"
    )

    %{trajectory | steps: trajectory.steps ++ [step]}
  end

  @doc """
  Adds a state snapshot to the trajectory.

  ## Options

  - `:state` - State data to capture (required)
  - `:reason` - Reason for snapshot (default: :checkpoint)
  - `:step_id` - Associated step ID (default: nil)
  - `:metadata` - Additional snapshot metadata (default: %{})

  ## Examples

      trajectory = Trajectory.add_snapshot(trajectory,
        state: %{variables: %{x: 42, y: 10}},
        reason: :before_action,
        metadata: %{checkpoint: true}
      )
  """
  @spec add_snapshot(t(), keyword()) :: t()
  def add_snapshot(%__MODULE__{} = trajectory, opts) do
    unless Keyword.has_key?(opts, :state) do
      raise ArgumentError, "add_snapshot/2 requires :state option"
    end

    snapshot = %StateSnapshot{
      id: generate_snapshot_id(),
      timestamp: DateTime.utc_now(),
      state: Keyword.fetch!(opts, :state),
      reason: Keyword.get(opts, :reason, :checkpoint),
      step_id: Keyword.get(opts, :step_id),
      metadata: Keyword.get(opts, :metadata, %{})
    }

    Logger.debug(
      "Recording state snapshot (trajectory_id: #{trajectory.id}, reason: #{snapshot.reason}, step_id: #{inspect(snapshot.step_id)})"
    )

    %{trajectory | state_snapshots: trajectory.state_snapshots ++ [snapshot]}
  end

  @doc """
  Marks the trajectory as complete and calculates final metrics.

  ## Options

  - `:outcome` - Final outcome (default: :success)
  - `:error` - Error information if failed (default: nil)
  - `:completed_at` - Completion time (default: DateTime.utc_now())

  ## Examples

      trajectory = Trajectory.complete(trajectory, outcome: :success)
      trajectory = Trajectory.complete(trajectory, outcome: :failure, error: :timeout)
  """
  @spec complete(t(), keyword()) :: t()
  def complete(%__MODULE__{} = trajectory, opts \\ []) do
    completed_at = Keyword.get(opts, :completed_at, DateTime.utc_now())
    duration_ms = DateTime.diff(completed_at, trajectory.started_at, :millisecond)

    outcome = Keyword.get(opts, :outcome, :success)
    error = Keyword.get(opts, :error)

    Logger.info(
      "Trajectory completed (trajectory_id: #{trajectory.id}, duration_ms: #{duration_ms}, steps: #{length(trajectory.steps)}, snapshots: #{length(trajectory.state_snapshots)}, outcome: #{outcome})"
    )

    %{
      trajectory
      | completed_at: completed_at,
        duration_ms: duration_ms,
        outcome: outcome,
        error: error
    }
  end

  @doc """
  Filters trajectory steps based on importance level.

  Removes low-importance steps while preserving critical execution information
  for reflection analysis. Marks the trajectory as filtered.

  ## Options

  - `:min_importance` - Minimum importance level to retain (default: :medium)
    Values: :low, :medium, :high, :critical
  - `:keep_snapshots` - Whether to keep state snapshots (default: true)
  - `:preserve_first_last` - Always keep first and last steps (default: true)

  ## Examples

      # Keep only high and critical steps
      filtered = Trajectory.filter(trajectory, min_importance: :high)

      # Keep medium+ steps but remove snapshots
      filtered = Trajectory.filter(trajectory,
        min_importance: :medium,
        keep_snapshots: false
      )
  """
  @spec filter(t(), keyword()) :: t()
  def filter(%__MODULE__{} = trajectory, opts \\ []) do
    min_importance = Keyword.get(opts, :min_importance, :medium)
    keep_snapshots = Keyword.get(opts, :keep_snapshots, true)
    preserve_first_last = Keyword.get(opts, :preserve_first_last, true)

    importance_threshold = importance_to_level(min_importance)

    filtered_steps =
      trajectory.steps
      |> Enum.with_index()
      |> Enum.filter(fn {step, index} ->
        step_level = importance_to_level(step.importance)

        # Always keep first and last if requested
        is_boundary =
          preserve_first_last and (index == 0 or index == length(trajectory.steps) - 1)

        is_boundary or step_level >= importance_threshold
      end)
      |> Enum.map(fn {step, _index} -> step end)

    filtered_snapshots =
      if keep_snapshots do
        trajectory.state_snapshots
      else
        []
      end

    original_steps = length(trajectory.steps)
    filtered_step_count = length(filtered_steps)

    Logger.debug(
      "Filtered trajectory (trajectory_id: #{trajectory.id}, original_steps: #{original_steps}, filtered_steps: #{filtered_step_count}, removed: #{original_steps - filtered_step_count}, min_importance: #{min_importance})"
    )

    %{
      trajectory
      | steps: filtered_steps,
        state_snapshots: filtered_snapshots,
        filtered: true,
        metadata: Map.put(trajectory.metadata, :filter_settings, opts)
    }
  end

  @doc """
  Converts a trajectory to a map representation suitable for storage or serialization.

  ## Examples

      map = Trajectory.to_map(trajectory)
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = trajectory) do
    %{
      id: trajectory.id,
      steps:
        Enum.map(trajectory.steps, fn step ->
          %{
            id: step.id,
            type: step.type,
            content: step.content,
            timestamp: DateTime.to_iso8601(step.timestamp),
            duration_ms: step.duration_ms,
            metadata: step.metadata,
            context: step.context,
            importance: step.importance,
            parent_step_id: step.parent_step_id
          }
        end),
      state_snapshots:
        Enum.map(trajectory.state_snapshots, fn snapshot ->
          %{
            id: snapshot.id,
            timestamp: DateTime.to_iso8601(snapshot.timestamp),
            state: snapshot.state,
            reason: snapshot.reason,
            step_id: snapshot.step_id,
            metadata: snapshot.metadata
          }
        end),
      started_at: DateTime.to_iso8601(trajectory.started_at),
      completed_at: if(trajectory.completed_at, do: DateTime.to_iso8601(trajectory.completed_at)),
      duration_ms: trajectory.duration_ms,
      metadata: trajectory.metadata,
      outcome: trajectory.outcome,
      error: trajectory.error,
      filtered: trajectory.filtered
    }
  end

  @doc """
  Returns statistics about the trajectory.

  ## Examples

      stats = Trajectory.statistics(trajectory)
      # => %{
      #   total_steps: 15,
      #   reasoning_steps: 8,
      #   action_steps: 4,
      #   ...
      # }
  """
  @spec statistics(t()) :: map()
  def statistics(%__MODULE__{} = trajectory) do
    step_counts_by_type =
      trajectory.steps
      |> Enum.group_by(& &1.type)
      |> Enum.map(fn {type, steps} -> {type, length(steps)} end)
      |> Enum.into(%{})

    importance_counts =
      trajectory.steps
      |> Enum.group_by(& &1.importance)
      |> Enum.map(fn {importance, steps} -> {importance, length(steps)} end)
      |> Enum.into(%{})

    %{
      total_steps: length(trajectory.steps),
      step_types: step_counts_by_type,
      importance_distribution: importance_counts,
      total_snapshots: length(trajectory.state_snapshots),
      duration_ms: trajectory.duration_ms,
      outcome: trajectory.outcome,
      filtered: trajectory.filtered
    }
  end

  # Private Functions

  @doc false
  @spec generate_trajectory_id() :: String.t()
  defp generate_trajectory_id do
    "traj_#{:erlang.unique_integer([:positive, :monotonic])}"
  end

  @doc false
  @spec generate_step_id() :: String.t()
  defp generate_step_id do
    "step_#{:erlang.unique_integer([:positive, :monotonic])}"
  end

  @doc false
  @spec generate_snapshot_id() :: String.t()
  defp generate_snapshot_id do
    "snap_#{:erlang.unique_integer([:positive, :monotonic])}"
  end

  @doc false
  @spec importance_to_level(Jido.AI.Runner.GEPA.Trajectory.importance()) :: non_neg_integer()
  defp importance_to_level(:low), do: 0
  defp importance_to_level(:medium), do: 1
  defp importance_to_level(:high), do: 2
  defp importance_to_level(:critical), do: 3
end
