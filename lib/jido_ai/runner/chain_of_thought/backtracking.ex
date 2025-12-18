defmodule Jido.AI.Runner.ChainOfThought.Backtracking do
  @moduledoc """
  Backtracking capabilities for Chain-of-Thought reasoning.

  This module provides comprehensive backtracking functionality including:
  - Reasoning state management and history tracking
  - Dead-end detection and recovery
  - Alternative path exploration
  - Backtrack budget management

  ## Usage

      # Execute reasoning with backtracking
      {:ok, result} = Backtracking.execute_with_backtracking(
        reasoning_fn,
        validator: &validate/1,
        max_backtracks: 3
      )

      # Create state snapshot
      snapshot = Backtracking.capture_state(current_state)

      # Detect dead-ends
      if Backtracking.dead_end?(result, history) do
        {:ok, alternative} = Backtracking.explore_alternative(state, history)
      end
  """

  alias Jido.AI.Runner.ChainOfThought.Backtracking.{
    BudgetManager,
    DeadEndDetector,
    PathExplorer,
    StateManager
  }

  @doc """
  Executes reasoning with backtracking support.

  ## Parameters

  - `reasoning_fn` - Function that performs reasoning
  - `opts` - Options:
    - `:validator` - Function to validate results
    - `:max_backtracks` - Maximum backtrack attempts (default: 3)
    - `:backtrack_budget` - Budget for exploration (default: 10)
    - `:on_backtrack` - Callback for backtrack events

  ## Returns

  - `{:ok, result}` - Successful result found
  - `{:ok, result, :partial}` - Partial success after budget exhausted
  - `{:error, reason}` - Failed to find valid result

  ## Examples

      {:ok, result} = Backtracking.execute_with_backtracking(
        fn state -> reason_about(state) end,
        validator: &valid?/1,
        max_backtracks: 5
      )
  """
  @spec execute_with_backtracking(fun(), keyword()) ::
          {:ok, term()} | {:ok, term(), :partial} | {:error, term()}
  def execute_with_backtracking(reasoning_fn, opts \\ []) do
    validator = Keyword.get(opts, :validator)
    max_backtracks = Keyword.get(opts, :max_backtracks, 3)
    backtrack_budget = Keyword.get(opts, :backtrack_budget, 10)
    on_backtrack = Keyword.get(opts, :on_backtrack)

    initial_state = %{
      reasoning_fn: reasoning_fn,
      validator: validator,
      history: [],
      failed_paths: MapSet.new(),
      backtrack_count: 0,
      budget: BudgetManager.init_budget(backtrack_budget)
    }

    do_execute_with_backtracking(initial_state, max_backtracks, on_backtrack)
  end

  @doc """
  Captures current reasoning state as snapshot.

  ## Parameters

  - `state` - Current state to snapshot

  ## Returns

  State snapshot map
  """
  @spec capture_state(map()) :: map()
  def capture_state(state) do
    StateManager.capture_snapshot(state)
  end

  @doc """
  Restores reasoning state from snapshot.

  ## Parameters

  - `snapshot` - State snapshot to restore

  ## Returns

  Restored state map
  """
  @spec restore_state(map()) :: map()
  def restore_state(snapshot) do
    StateManager.restore_snapshot(snapshot)
  end

  @doc """
  Checks if current state is a dead-end.

  ## Parameters

  - `result` - Current reasoning result
  - `history` - Reasoning history
  - `opts` - Options for detection

  ## Returns

  Boolean indicating if dead-end detected
  """
  @spec dead_end?(term(), list(), keyword()) :: boolean()
  def dead_end?(result, history, opts \\ []) do
    DeadEndDetector.detect(result, history, opts)
  end

  @doc """
  Explores alternative reasoning path.

  ## Parameters

  - `state` - Current state
  - `history` - Reasoning history

  ## Returns

  - `{:ok, alternative_state}` - Alternative found
  - `{:error, :no_alternatives}` - No alternatives available
  """
  @spec explore_alternative(map(), list()) :: {:ok, map()} | {:error, term()}
  def explore_alternative(state, history) do
    PathExplorer.generate_alternative(state, history)
  end

  # Private functions

  defp do_execute_with_backtracking(state, max_backtracks, on_backtrack) do
    if state.backtrack_count >= max_backtracks do
      {:error, :max_backtracks_exceeded}
    else
      # Execute reasoning
      result = state.reasoning_fn.()

      # Validate result
      case validate_result(result, state.validator) do
        {:ok, validated_result} ->
          {:ok, validated_result}

        {:error, reason} ->
          # Validation failures trigger backtracking attempts
          # The max_backtracks check at the start of this function will terminate recursion
          attempt_backtrack(state, reason, max_backtracks, on_backtrack)
      end
    end
  end

  defp attempt_backtrack(state, reason, max_backtracks, on_backtrack) do
    # Check budget
    if BudgetManager.has_budget?(state.budget) do
      # Generate alternative
      case explore_alternative(state, state.history) do
        {:ok, alternative_state} ->
          # Update state
          new_state = %{
            alternative_state
            | backtrack_count: state.backtrack_count + 1,
              history: [reason | state.history],
              failed_paths: MapSet.put(state.failed_paths, hash_state(state)),
              budget: BudgetManager.consume_budget(state.budget, 1)
          }

          # Invoke callback
          if on_backtrack do
            on_backtrack.({:backtrack, state.backtrack_count + 1, reason})
          end

          # Retry with alternative
          do_execute_with_backtracking(new_state, max_backtracks, on_backtrack)

        {:error, :no_alternatives} ->
          {:error, {:no_alternatives, reason}}
      end
    else
      {:error, {:budget_exhausted, reason}}
    end
  end

  defp validate_result(result, nil), do: {:ok, result}

  defp validate_result(result, validator) when is_function(validator, 1) do
    case validator.(result) do
      true -> {:ok, result}
      false -> {:error, :validation_failed}
      {:ok, validated} -> {:ok, validated}
      {:error, reason} -> {:error, reason}
      other -> {:error, {:invalid_validator_result, other}}
    end
  end

  defp hash_state(state) do
    # Simple hash of state for tracking failed paths
    :erlang.phash2(state)
  end
end
