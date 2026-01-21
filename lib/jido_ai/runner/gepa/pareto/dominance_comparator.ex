defmodule Jido.AI.Runner.GEPA.Pareto.DominanceComparator do
  @moduledoc """
  Computes dominance relationships and performs non-dominated sorting.

  This module implements Task 2.1.2 of GEPA Stage 2, providing dominance
  computation algorithms essential for Pareto frontier management:

  ## Key Algorithms

  **Pareto Dominance**: Solution A dominates solution B if:
  1. A is better than or equal to B in all objectives
  2. A is strictly better than B in at least one objective

  **NSGA-II Fast Non-Dominated Sorting**: Efficiently classifies population
  into Pareto fronts. Front 1 contains non-dominated solutions, Front 2
  contains solutions dominated only by Front 1, etc.
  - Complexity: O(MN²) where M = objectives, N = population size

  **Crowding Distance**: Measures solution density along the Pareto frontier
  to promote diversity. Solutions with higher crowding distance are in
  less-crowded regions.
  - Complexity: O(MN log N) where M = objectives, N = front size

  **Epsilon-Dominance**: Relaxed dominance check for noisy objectives,
  allowing tolerance in comparisons.

  ## Usage

      # Check if solution A dominates B
      result = DominanceComparator.compare(candidate_a, candidate_b)
      # => :dominates | :dominated_by | :non_dominated

      # Classify population into Pareto fronts
      fronts = DominanceComparator.fast_non_dominated_sort(candidates)
      # => %{1 => [%Candidate{}, ...], 2 => [...], ...}

      # Calculate crowding distances for diversity
      distances = DominanceComparator.crowding_distance(front_1_candidates)
      # => %{"candidate_id_1" => 1.5, "candidate_id_2" => :infinity, ...}

      # Check epsilon-dominance for noisy objectives
      epsilon_dom? = DominanceComparator.epsilon_dominates?(a, b, epsilon: 0.05)
      # => true | false
  """

  alias Jido.AI.Runner.GEPA.Population.Candidate

  require Logger

  @type dominance_result :: :dominates | :dominated_by | :non_dominated
  @type comparison_result :: :better | :worse | :equal
  @type crowding_distance :: float() | :infinity

  @doc """
  Compares two candidates for dominance relationship.

  ## Arguments

  - `a` - First candidate to compare
  - `b` - Second candidate to compare
  - `opts` - Options:
    - `:objective_types` - Map of objective -> :maximize/:minimize (optional)

  ## Returns

  - `:dominates` - Candidate A dominates B
  - `:dominated_by` - Candidate B dominates A
  - `:non_dominated` - Neither dominates the other

  ## Examples

      iex> compare(better_candidate, worse_candidate)
      :dominates

      iex> compare(candidate1, candidate2)
      :non_dominated
  """
  @spec compare(Candidate.t(), Candidate.t(), keyword()) :: dominance_result()
  def compare(a, b, opts \\ [])

  def compare(%Candidate{normalized_objectives: nil}, _b, _opts) do
    Logger.warning("Candidate A has no normalized_objectives, returning :non_dominated")
    :non_dominated
  end

  def compare(_a, %Candidate{normalized_objectives: nil}, _opts) do
    Logger.warning("Candidate B has no normalized_objectives, returning :non_dominated")
    :non_dominated
  end

  def compare(%Candidate{} = a, %Candidate{} = b, _opts) do
    a_objectives = a.normalized_objectives
    b_objectives = b.normalized_objectives

    # Get all objectives from both candidates
    objectives =
      (Map.keys(a_objectives) ++ Map.keys(b_objectives))
      |> Enum.uniq()

    if Enum.empty?(objectives) do
      :non_dominated
    else
      # Compare each objective (all normalized, higher is better)
      comparisons =
        Enum.map(objectives, fn obj ->
          a_val = Map.get(a_objectives, obj, 0.0)
          b_val = Map.get(b_objectives, obj, 0.0)

          cond do
            a_val > b_val -> :better
            a_val < b_val -> :worse
            true -> :equal
          end
        end)

      # A dominates B if all >= and at least one >
      all_better_or_equal? = Enum.all?(comparisons, &(&1 in [:better, :equal]))
      at_least_one_better? = Enum.any?(comparisons, &(&1 == :better))

      # B dominates A if all <= and at least one <
      all_worse_or_equal? = Enum.all?(comparisons, &(&1 in [:worse, :equal]))
      at_least_one_worse? = Enum.any?(comparisons, &(&1 == :worse))

      cond do
        all_better_or_equal? and at_least_one_better? -> :dominates
        all_worse_or_equal? and at_least_one_worse? -> :dominated_by
        true -> :non_dominated
      end
    end
  end

  @doc """
  Checks if candidate A dominates candidate B.

  Convenience function that returns boolean instead of atom.

  ## Examples

      iex> dominates?(better_candidate, worse_candidate)
      true
  """
  @spec dominates?(Candidate.t(), Candidate.t(), keyword()) :: boolean()
  def dominates?(a, b, opts \\ []) do
    compare(a, b, opts) == :dominates
  end

  @doc """
  Performs fast non-dominated sorting on a population of candidates.

  Implements the NSGA-II algorithm to classify candidates into Pareto fronts.
  Front 1 contains non-dominated solutions (Pareto optimal). Front k contains
  solutions dominated only by solutions in Fronts 1..(k-1).

  ## Arguments

  - `candidates` - List of candidates with normalized_objectives
  - `opts` - Options (reserved for future use)

  ## Returns

  Map of front_number => list of candidates:
  ```
  %{
    1 => [candidate1, candidate2, ...],  # Non-dominated (Pareto optimal)
    2 => [candidate5, candidate6, ...],  # Dominated only by Front 1
    3 => [candidate9, ...],              # Dominated only by Fronts 1-2
    ...
  }
  ```

  ## Complexity

  O(MN²) where M = number of objectives, N = population size

  ## Examples

      iex> fronts = fast_non_dominated_sort(population)
      iex> pareto_optimal = fronts[1]
      iex> length(pareto_optimal)
      12
  """
  @spec fast_non_dominated_sort(list(Candidate.t()), keyword()) :: %{
          pos_integer() => list(Candidate.t())
        }
  def fast_non_dominated_sort(candidates, opts \\ [])

  def fast_non_dominated_sort([], _opts), do: %{}

  def fast_non_dominated_sort(candidates, opts) when is_list(candidates) do
    # Initialize dominance relationships for each candidate
    initial_state =
      candidates
      |> Enum.reduce(%{}, fn candidate, acc ->
        Map.put(acc, candidate.id, %{
          candidate: candidate,
          # IDs of solutions that dominate this one
          dominated_by: [],
          # IDs of solutions this one dominates
          dominates: [],
          # Number of solutions that dominate this one
          domination_count: 0
        })
      end)

    # Calculate all pairwise dominance relationships
    state_with_dominance =
      calculate_dominance_relationships(
        candidates,
        initial_state,
        opts
      )

    # Classify candidates into fronts
    classify_into_fronts(state_with_dominance)
  end

  @doc """
  Calculates crowding distance for candidates in a Pareto front.

  Crowding distance measures the density of solutions along the Pareto
  frontier. Solutions with higher crowding distance are in less-crowded
  regions and should be preferred to maintain diversity.

  Boundary solutions (extreme values in any objective) receive infinite
  distance to ensure they are always preserved.

  ## Arguments

  - `candidates` - List of candidates from same front with normalized_objectives
  - `opts` - Options (reserved for future use)

  ## Returns

  Map of candidate_id => crowding_distance:
  ```
  %{
    "candidate_1" => :infinity,  # Boundary solution
    "candidate_2" => 1.5,
    "candidate_3" => 0.8,
    "candidate_4" => :infinity   # Boundary solution
  }
  ```

  ## Complexity

  O(MN log N) where M = objectives, N = front size

  ## Examples

      iex> distances = crowding_distance(front_1_candidates)
      iex> sorted_by_crowding = Enum.sort_by(distances, fn {_id, dist} ->
      ...>   if dist == :infinity, do: 999999, else: dist
      ...> end, :desc)
  """
  @spec crowding_distance(list(Candidate.t()), keyword()) :: %{String.t() => crowding_distance()}
  def crowding_distance(candidates, opts \\ [])

  def crowding_distance([], _opts), do: %{}

  def crowding_distance(candidates, _opts) when length(candidates) <= 2 do
    # With 2 or fewer candidates, all are boundary solutions
    candidates
    |> Enum.map(fn c -> {c.id, :infinity} end)
    |> Map.new()
  end

  def crowding_distance(candidates, _opts) do
    # Get all objectives from first candidate
    first_candidate = List.first(candidates)

    objectives =
      case first_candidate.normalized_objectives do
        nil -> []
        obj_map -> Map.keys(obj_map)
      end

    if Enum.empty?(objectives) do
      # No objectives, return zero distance for all
      candidates
      |> Enum.map(fn c -> {c.id, 0.0} end)
      |> Map.new()
    else
      # Initialize all distances to 0.0
      initial_distances =
        candidates
        |> Enum.map(fn c -> {c.id, 0.0} end)
        |> Map.new()

      # Add distance contribution from each objective
      Enum.reduce(objectives, initial_distances, fn objective, distances ->
        add_objective_crowding(candidates, objective, distances)
      end)
    end
  end

  @doc """
  Checks if candidate A epsilon-dominates candidate B.

  Epsilon-dominance is a relaxed form of dominance useful when objectives
  have measurement noise or when we want to prevent bloat in the archive.

  A epsilon-dominates B if:
  1. A >= B - epsilon in all objectives
  2. A > B + epsilon in at least one objective

  ## Arguments

  - `a` - First candidate to compare
  - `b` - Second candidate to compare
  - `opts` - Options:
    - `:epsilon` - Tolerance value (default: 0.01)

  ## Returns

  Boolean indicating if A epsilon-dominates B

  ## Examples

      iex> epsilon_dominates?(candidate_a, candidate_b, epsilon: 0.05)
      true

      iex> epsilon_dominates?(similar_a, similar_b)  # Uses default 0.01
      false
  """
  @spec epsilon_dominates?(Candidate.t(), Candidate.t(), keyword()) :: boolean()
  def epsilon_dominates?(a, b, opts \\ [])

  def epsilon_dominates?(%Candidate{normalized_objectives: nil}, _b, _opts), do: false
  def epsilon_dominates?(_a, %Candidate{normalized_objectives: nil}, _opts), do: false

  def epsilon_dominates?(%Candidate{} = a, %Candidate{} = b, opts) do
    epsilon = Keyword.get(opts, :epsilon, 0.01)

    a_objectives = a.normalized_objectives
    b_objectives = b.normalized_objectives

    # Get all objectives
    objectives =
      (Map.keys(a_objectives) ++ Map.keys(b_objectives))
      |> Enum.uniq()

    if Enum.empty?(objectives) do
      false
    else
      # Check if A >= B - epsilon in all objectives
      all_better_or_within_epsilon? =
        Enum.all?(objectives, fn obj ->
          a_val = Map.get(a_objectives, obj, 0.0)
          b_val = Map.get(b_objectives, obj, 0.0)
          a_val >= b_val - epsilon
        end)

      # Check if A > B + epsilon in at least one objective
      at_least_one_strictly_better? =
        Enum.any?(objectives, fn obj ->
          a_val = Map.get(a_objectives, obj, 0.0)
          b_val = Map.get(b_objectives, obj, 0.0)
          a_val > b_val + epsilon
        end)

      all_better_or_within_epsilon? and at_least_one_strictly_better?
    end
  end

  # Private helper functions

  @spec calculate_dominance_relationships(list(Candidate.t()), map(), keyword()) :: map()
  defp calculate_dominance_relationships(candidates, state, opts) do
    # Compare each pair of candidates
    for a <- candidates,
        b <- candidates,
        a.id != b.id,
        reduce: state do
      acc ->
        case compare(a, b, opts) do
          :dominates ->
            # A dominates B
            acc
            |> update_in([a.id, :dominates], &[b.id | &1])
            |> update_in([b.id, :dominated_by], &[a.id | &1])
            |> update_in([b.id, :domination_count], &(&1 + 1))

          _ ->
            acc
        end
    end
  end

  @spec classify_into_fronts(map()) :: %{pos_integer() => list(Candidate.t())}
  defp classify_into_fronts(state) do
    # Front 1: candidates with domination_count = 0 (non-dominated)
    front_1 =
      state
      |> Enum.filter(fn {_id, info} -> info.domination_count == 0 end)
      |> Enum.map(fn {_id, info} -> info.candidate end)

    if Enum.empty?(front_1) do
      %{}
    else
      # Recursively build remaining fronts
      classify_remaining_fronts(state, front_1, %{1 => front_1}, 1)
    end
  end

  @spec classify_remaining_fronts(map(), list(Candidate.t()), map(), pos_integer()) :: map()
  defp classify_remaining_fronts(state, current_front, fronts, front_num) do
    if Enum.empty?(current_front) do
      fronts
    else
      # Find next front: solutions whose domination count becomes 0
      # when we remove dominance from current front
      next_front = find_next_front(state, current_front, fronts)

      if Enum.empty?(next_front) do
        fronts
      else
        new_fronts = Map.put(fronts, front_num + 1, next_front)
        classify_remaining_fronts(state, next_front, new_fronts, front_num + 1)
      end
    end
  end

  @spec find_next_front(map(), list(Candidate.t()), map()) :: list(Candidate.t())
  defp find_next_front(state, current_front, existing_fronts) do
    # Get IDs of all candidates already classified into fronts
    classified_ids =
      existing_fronts
      |> Map.values()
      |> List.flatten()
      |> Enum.map(& &1.id)
      |> MapSet.new()

    # For each candidate in current front, decrement domination count
    # of candidates it dominates
    _current_front_ids = Enum.map(current_front, & &1.id)

    state
    |> Enum.reject(fn {id, _info} -> MapSet.member?(classified_ids, id) end)
    |> Enum.filter(fn {_id, info} ->
      # Count how many of this candidate's dominators are in all previous fronts (already classified)
      dominators_in_previous_fronts =
        info.dominated_by
        |> Enum.filter(&MapSet.member?(classified_ids, &1))
        |> length()

      # This candidate joins next front if ALL its dominators are in previous fronts
      info.domination_count == dominators_in_previous_fronts
    end)
    |> Enum.map(fn {_id, info} -> info.candidate end)
  end

  @spec add_objective_crowding(list(Candidate.t()), atom(), %{String.t() => crowding_distance()}) ::
          %{String.t() => crowding_distance()}
  defp add_objective_crowding(candidates, objective, distances) do
    # Sort candidates by this objective value
    sorted =
      Enum.sort_by(candidates, fn c ->
        case c.normalized_objectives do
          nil -> 0.0
          obj_map -> Map.get(obj_map, objective, 0.0)
        end
      end)

    # Boundary solutions get infinite distance
    first = List.first(sorted)
    last = List.last(sorted)

    # Check if all values are the same
    first_val = get_in(first, [Access.key(:normalized_objectives), objective]) || 0.0
    last_val = get_in(last, [Access.key(:normalized_objectives), objective]) || 0.0
    range = last_val - first_val

    if range == 0.0 do
      # All values are the same, don't add distance
      distances
    else
      # Set boundary distances to infinity
      distances =
        distances
        |> Map.put(first.id, :infinity)
        |> Map.put(last.id, :infinity)

      # Calculate distance contribution for interior solutions
      sorted
      # Skip first (boundary)
      |> Enum.drop(1)
      # Skip last (boundary)
      |> Enum.drop(-1)
      # Track position in sorted list
      |> Enum.with_index(1)
      |> Enum.reduce(distances, fn {candidate, idx}, acc ->
        prev = Enum.at(sorted, idx - 1)
        next = Enum.at(sorted, idx + 1)

        prev_val = get_in(prev, [Access.key(:normalized_objectives), objective]) || 0.0
        next_val = get_in(next, [Access.key(:normalized_objectives), objective]) || 0.0

        # Distance = (next - prev) / range
        contribution = (next_val - prev_val) / range

        # Add contribution to current distance (unless it's already infinite)
        case Map.get(acc, candidate.id) do
          :infinity ->
            acc

          current_distance ->
            Map.put(acc, candidate.id, current_distance + contribution)
        end
      end)
    end
  end
end
