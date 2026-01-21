defmodule Jido.AI.Runner.ChainOfThought.Backtracking.PathExplorer do
  @moduledoc """
  Explores alternative reasoning paths when backtracking occurs.

  Provides:
  - Alternative approach generation using reasoning variation
  - Failed path avoidance tracking attempted approaches
  - Diversity mechanisms encouraging different reasoning strategies
  - Exhaustive search with beam width limits for breadth control
  """

  require Logger

  @default_beam_width 3
  @default_diversity_factor 0.5

  @type exploration_strategy :: :breadth_first | :depth_first | :best_first | :random

  @doc """
  Generates alternative reasoning approach.

  ## Parameters

  - `state` - Current state
  - `history` - Reasoning history
  - `opts` - Options:
    - `:strategy` - Exploration strategy (default: :best_first)
    - `:diversity_factor` - How different alternatives should be (0.0-1.0, default: 0.5)
    - `:beam_width` - Max alternatives to explore (default: 3)

  ## Returns

  - `{:ok, alternative_state}` - Alternative generated
  - `{:error, :no_alternatives}` - No valid alternatives

  ## Examples

      {:ok, alt_state} = PathExplorer.generate_alternative(state, history)
  """
  @spec generate_alternative(map(), list(), keyword()) :: {:ok, map()} | {:error, term()}
  def generate_alternative(state, history, opts \\ []) do
    strategy = Keyword.get(opts, :strategy, :best_first)
    diversity_factor = Keyword.get(opts, :diversity_factor, @default_diversity_factor)
    beam_width = Keyword.get(opts, :beam_width, @default_beam_width)

    failed_paths = Map.get(state, :failed_paths, MapSet.new())

    # Generate candidate alternatives
    candidates = generate_candidates(state, history, diversity_factor, beam_width)

    # Filter out failed paths
    valid_candidates = filter_failed_paths(candidates, failed_paths)

    # Select best alternative based on strategy
    case select_alternative(valid_candidates, strategy, history) do
      nil -> {:error, :no_alternatives}
      alternative -> {:ok, alternative}
    end
  end

  @doc """
  Generates multiple alternative paths for exploration.

  ## Parameters

  - `state` - Current state
  - `history` - Reasoning history
  - `beam_width` - Number of alternatives to generate

  ## Returns

  List of alternative states
  """
  @spec generate_alternatives(map(), list(), pos_integer()) :: list(map())
  def generate_alternatives(state, history, beam_width \\ @default_beam_width) do
    generate_candidates(state, history, @default_diversity_factor, beam_width)
  end

  @doc """
  Checks if path has been attempted before.

  ## Parameters

  - `state` - State representing path
  - `failed_paths` - Set of failed path hashes

  ## Returns

  Boolean indicating if path was tried
  """
  @spec path_attempted?(map(), MapSet.t()) :: boolean()
  def path_attempted?(state, failed_paths) do
    state_hash = hash_state(state)
    MapSet.member?(failed_paths, state_hash)
  end

  @doc """
  Marks path as failed.

  ## Parameters

  - `state` - State representing failed path
  - `failed_paths` - Current set of failed paths

  ## Returns

  Updated failed paths set
  """
  @spec mark_path_failed(map(), MapSet.t()) :: MapSet.t()
  def mark_path_failed(state, failed_paths) do
    state_hash = hash_state(state)
    MapSet.put(failed_paths, state_hash)
  end

  @doc """
  Calculates diversity score between two states.

  ## Parameters

  - `state1` - First state
  - `state2` - Second state

  ## Returns

  Diversity score (0.0 = identical, 1.0 = completely different)
  """
  @spec diversity_score(map(), map()) :: float()
  def diversity_score(state1, state2) do
    keys1 = Map.keys(state1) |> MapSet.new()
    keys2 = Map.keys(state2) |> MapSet.new()

    # Jaccard distance for key differences
    intersection = MapSet.intersection(keys1, keys2) |> MapSet.size()
    union = MapSet.union(keys1, keys2) |> MapSet.size()

    key_diversity = if union == 0, do: 0.0, else: 1.0 - intersection / union

    # Value differences for common keys
    common_keys = MapSet.intersection(keys1, keys2)

    value_differences =
      common_keys
      |> Enum.count(fn key -> Map.get(state1, key) != Map.get(state2, key) end)

    value_diversity =
      if MapSet.size(common_keys) == 0 do
        0.0
      else
        value_differences / MapSet.size(common_keys)
      end

    # Combine both factors
    (key_diversity + value_diversity) / 2.0
  end

  @doc """
  Ensures alternatives have sufficient diversity from history.

  ## Parameters

  - `alternatives` - List of alternative states
  - `history` - Reasoning history
  - `min_diversity` - Minimum diversity threshold

  ## Returns

  Filtered list of diverse alternatives
  """
  @spec ensure_diversity(list(map()), list(), float()) :: list(map())
  def ensure_diversity(alternatives, history, min_diversity \\ 0.3) do
    if Enum.empty?(history) do
      alternatives
    else
      # Filter history to only include maps
      recent_states =
        history
        |> Enum.take(5)
        |> Enum.filter(&is_map/1)

      if Enum.empty?(recent_states) do
        alternatives
      else
        Enum.filter(alternatives, fn alt ->
          avg_diversity =
            recent_states
            |> Enum.map(&diversity_score(alt, &1))
            |> Enum.sum()
            |> Kernel./(length(recent_states))

          avg_diversity >= min_diversity
        end)
      end
    end
  end

  @doc """
  Performs exhaustive search with beam width limit.

  ## Parameters

  - `initial_state` - Starting state
  - `validator` - Function to validate states
  - `opts` - Options:
    - `:beam_width` - Max parallel explorations (default: 3)
    - `:max_depth` - Max exploration depth (default: 10)

  ## Returns

  - `{:ok, valid_state}` - Found valid state
  - `{:error, :no_solution}` - No valid state within limits
  """
  @spec beam_search(map(), fun(), keyword()) :: {:ok, map()} | {:error, term()}
  def beam_search(initial_state, validator, opts \\ []) do
    beam_width = Keyword.get(opts, :beam_width, @default_beam_width)
    max_depth = Keyword.get(opts, :max_depth, 10)

    do_beam_search([initial_state], validator, beam_width, max_depth, 0, MapSet.new())
  end

  # Private functions

  defp generate_candidates(state, history, diversity_factor, beam_width) do
    # Generate variations of current state
    variations = [
      vary_by_parameter_adjustment(state),
      vary_by_strategy_change(state),
      vary_by_backtrack(state, history)
    ]

    variations
    |> Enum.take(beam_width)
    |> ensure_diversity(history, diversity_factor)
  end

  defp vary_by_parameter_adjustment(state) do
    # Adjust reasoning parameters
    Map.update(state, :reasoning_params, %{}, fn params ->
      Map.update(params, :temperature, 0.7, &(&1 * 1.2))
    end)
  end

  defp vary_by_strategy_change(state) do
    # Change reasoning strategy
    strategies = [:analytical, :creative, :systematic, :intuitive]
    current_strategy = Map.get(state, :strategy, :analytical)

    new_strategy =
      strategies
      |> Enum.reject(&(&1 == current_strategy))
      |> Enum.random()

    Map.put(state, :strategy, new_strategy)
  end

  defp vary_by_backtrack(state, history) do
    # Backtrack to earlier decision point
    if Enum.empty?(history) do
      state
    else
      # Take state from earlier in history
      earlier_state = Enum.at(history, min(2, length(history) - 1))

      if earlier_state && is_map(earlier_state) do
        Map.merge(state, earlier_state)
      else
        state
      end
    end
  end

  defp filter_failed_paths(candidates, failed_paths) do
    Enum.reject(candidates, &path_attempted?(&1, failed_paths))
  end

  defp select_alternative([], _strategy, _history), do: nil

  defp select_alternative(candidates, :best_first, history) do
    # Select candidate with highest potential (based on history)
    candidates
    |> Enum.map(fn candidate ->
      score = calculate_potential_score(candidate, history)
      {candidate, score}
    end)
    |> Enum.max_by(fn {_candidate, score} -> score end, fn -> nil end)
    |> case do
      nil -> nil
      {candidate, _score} -> candidate
    end
  end

  defp select_alternative(candidates, :breadth_first, _history) do
    # Select first candidate (FIFO)
    List.first(candidates)
  end

  defp select_alternative(candidates, :depth_first, _history) do
    # Select last candidate (LIFO)
    List.last(candidates)
  end

  defp select_alternative(candidates, :random, _history) do
    # Select random candidate
    Enum.random(candidates)
  end

  defp calculate_potential_score(candidate, history) do
    # Simple scoring based on diversity from history
    # Filter history to only include maps
    map_history = Enum.filter(history, &is_map/1)

    if Enum.empty?(map_history) do
      0.5
    else
      avg_diversity =
        map_history
        |> Enum.take(3)
        |> Enum.map(&diversity_score(candidate, &1))
        |> Enum.sum()
        |> Kernel./(min(3, length(map_history)))

      avg_diversity
    end
  end

  defp hash_state(state) do
    :erlang.phash2(state)
  end

  defp do_beam_search(_beam, _validator, _beam_width, max_depth, depth, _visited)
       when depth >= max_depth do
    {:error, :max_depth_exceeded}
  end

  defp do_beam_search([], _validator, _beam_width, _max_depth, _depth, _visited) do
    {:error, :no_solution}
  end

  defp do_beam_search(beam, validator, beam_width, max_depth, depth, visited) do
    # Validate current states
    case Enum.find(beam, &validator.(&1)) do
      nil ->
        # Generate next level
        next_level =
          beam
          |> Enum.flat_map(fn state ->
            generate_candidates(state, [], 0.5, beam_width)
          end)
          |> Enum.reject(fn state ->
            state_hash = hash_state(state)
            MapSet.member?(visited, state_hash)
          end)
          |> Enum.take(beam_width)

        new_visited =
          Enum.reduce(next_level, visited, fn state, acc ->
            MapSet.put(acc, hash_state(state))
          end)

        do_beam_search(next_level, validator, beam_width, max_depth, depth + 1, new_visited)

      valid_state ->
        {:ok, valid_state}
    end
  end
end
