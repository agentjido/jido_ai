defmodule Jido.AI.Runner.GEPA.Selection.EliteSelector do
  @moduledoc """
  Elite preservation for GEPA multi-objective optimization.

  Ensures that the best solutions found are never lost during evolution.
  Elite selection prioritizes:
  1. Pareto rank (Front 1 > Front 2 > ...)
  2. Crowding distance (diverse > clustered)
  3. Generation age (older = more validated)

  ## Elitism Benefits

  - **Monotonic improvement**: Best fitness never decreases
  - **Convergence guarantee**: Optimization cannot regress
  - **Safety net**: Protects discoveries from mutation damage
  - **Efficiency**: Preserves expensive evaluations

  ## Elite Ratio Guidelines

  - **Too low (<5%)**: Risk losing good solutions to mutation
  - **Balanced (10-20%)**: Standard recommendation for most problems
  - **Too high (>30%)**: Reduced exploration, slower improvement

  ## Elite Selection Strategies

  1. **Standard elitism** (`select_elites/2`): Top K by rank/distance
  2. **Frontier-preserving** (`select_elites_preserve_frontier/2`): Guarantees all Front 1 included
  3. **Diversity-preserving** (`select_diverse_elites/2`): Avoids near-duplicate elites

  ## Usage

      # Select elites for next generation (15% of population)
      {:ok, elites} = EliteSelector.select_elites(population, elite_ratio: 0.15)

      # Select exact number of elites
      {:ok, elites} = EliteSelector.select_elites(population, elite_count: 20)

      # Get all Pareto-optimal solutions
      {:ok, pareto_optimal} = EliteSelector.select_pareto_front_1(population)

      # Preserve entire frontier plus diverse lower fronts
      {:ok, elites} = EliteSelector.select_elites_preserve_frontier(
        population,
        elite_count: 50
      )

      # Select diverse elites (no near-duplicates)
      {:ok, diverse_elites} = EliteSelector.select_diverse_elites(
        population,
        elite_count: 30,
        similarity_threshold: 0.01
      )

  ## Integration with NSGA-II

  Elite preservation is a core component of NSGA-II. After generating offspring:
  1. Combine parents + offspring
  2. Select elites (preserves best)
  3. Fill remaining population with tournament selection

  This ensures monotonic improvement: each generation is at least as good as previous.
  """

  alias Jido.AI.Runner.GEPA.Pareto.DominanceComparator
  alias Jido.AI.Runner.GEPA.Population.Candidate
  alias Jido.AI.Runner.GEPA.Selection.CrowdingDistanceSelector

  require Logger

  # 15% of population
  @default_elite_ratio 0.15
  # 1% objective space distance
  @default_similarity_threshold 0.01

  @type selection_result :: {:ok, list(Candidate.t())} | {:error, term()}

  @doc """
  Selects elite candidates for preservation.

  Elite count can be specified as:
  - `:elite_ratio` - Fraction of population (default: 0.15 = 15%)
  - `:elite_count` - Absolute count (overrides ratio)
  - `:min_elites` - Minimum to preserve even if ratio/count would be less

  Elites are selected by:
  1. Sort by Pareto rank (ascending - Front 1 first)
  2. Within each rank, sort by crowding distance (descending - diverse first)
  3. Take top K candidates

  ## Arguments

  - `population` - List of candidates (must have `pareto_rank` and `crowding_distance`)
  - `opts` - Options:
    - `:elite_ratio` - Fraction of population to preserve (default: 0.15)
    - `:elite_count` - Absolute count to preserve (overrides ratio)
    - `:min_elites` - Minimum number to preserve (default: 1)

  ## Returns

  - `{:ok, elites}` - List of elite candidates
  - `{:error, reason}` - Validation failed

  ## Examples

      # Select 15% of population as elites
      {:ok, elites} = EliteSelector.select_elites(population)
      assert length(elites) == 15  # For population of 100

      # Select exact count
      {:ok, elites} = EliteSelector.select_elites(population, elite_count: 25)
      assert length(elites) == 25

      # Use different ratio
      {:ok, elites} = EliteSelector.select_elites(population, elite_ratio: 0.20)
      assert length(elites) == 20  # For population of 100

      # Ensure minimum preserved
      {:ok, elites} = EliteSelector.select_elites(small_pop, min_elites: 5)
      assert length(elites) >= 5
  """
  @spec select_elites(list(Candidate.t()), keyword()) :: selection_result()
  def select_elites(population, opts \\ [])

  def select_elites([], _opts), do: {:ok, []}

  def select_elites(population, opts) do
    with :ok <- validate_selection_metrics(population) do
      elite_count = calculate_elite_count(length(population), opts)

      # Ensure count doesn't exceed population
      actual_count = min(elite_count, length(population))

      # Select top elite_count by (rank ASC, distance DESC)
      elites = select_by_rank_and_distance(population, actual_count)

      {:ok, elites}
    end
  end

  @doc """
  Selects all Pareto Front 1 (non-dominated) solutions.

  Front 1 consists of all candidates that are not dominated by any other candidate.
  These are the Pareto-optimal solutions representing the current best trade-offs.

  ## Arguments

  - `population` - List of candidates with `normalized_objectives`

  ## Returns

  - `{:ok, front_1}` - List of non-dominated candidates
  - `{:ok, []}` - If population is empty or has no valid objectives

  ## Examples

      {:ok, front_1} = EliteSelector.select_pareto_front_1(population)

      # All Front 1 members are non-dominated
      assert Enum.all?(front_1, fn c -> c.pareto_rank == 1 end)

      # Used to ensure frontier is always preserved
      {:ok, elites} = EliteSelector.select_pareto_front_1(population)
      # Then fill remaining elite slots from Front 2, 3, ...
  """
  @spec select_pareto_front_1(list(Candidate.t())) :: selection_result()
  def select_pareto_front_1([]), do: {:ok, []}

  def select_pareto_front_1(population) do
    # Perform non-dominated sorting
    fronts = DominanceComparator.fast_non_dominated_sort(population)

    # Get Front 1 (non-dominated solutions)
    front_1 = Map.get(fronts, 1, [])

    {:ok, front_1}
  end

  @doc """
  Selects elites with frontier preservation guarantee.

  This strategy ensures the Pareto frontier never degrades by:
  1. **Always including all Front 1** (non-dominated solutions)
  2. If Front 1 < elite_count: Fill remaining from Front 2 by crowding distance
  3. If Front 1 > elite_count: Trim Front 1 by crowding distance

  This is stronger than standard elitism because it guarantees:
  - All non-dominated solutions survive
  - Frontier diversity is maintained via crowding distance
  - Optimization monotonically improves the Pareto frontier

  ## Arguments

  - `population` - Candidates with `normalized_objectives`
  - `opts` - Options:
    - `:elite_count` - Total elites to select (required)

  ## Returns

  - `{:ok, elites}` - All Front 1 + diverse Front 2/3/... up to elite_count

  ## Examples

      # Preserve entire frontier plus diverse lower fronts
      {:ok, elites} = EliteSelector.select_elites_preserve_frontier(
        population,
        elite_count: 50
      )

      # If Front 1 has 30 candidates, all 30 included
      # Plus 20 most diverse from Front 2

      # If Front 1 has 60 candidates (> elite_count)
      # Trim to 50 most diverse from Front 1
  """
  @spec select_elites_preserve_frontier(list(Candidate.t()), keyword()) :: selection_result()
  def select_elites_preserve_frontier(population, opts) do
    with {:ok, elite_count} <- fetch_required(opts, :elite_count) do
      # Perform non-dominated sorting
      fronts = DominanceComparator.fast_non_dominated_sort(population)

      # Assign ranks and crowding distances
      population_with_metrics = assign_selection_metrics(population, fronts)

      # Get Front 1
      front_1 = Enum.filter(population_with_metrics, fn c -> c.pareto_rank == 1 end)

      cond do
        # Front 1 is larger than elite quota - trim by crowding distance
        length(front_1) > elite_count ->
          elites = select_diverse_subset(front_1, elite_count)
          {:ok, elites}

        # Front 1 fits within quota - include all + fill from lower fronts
        length(front_1) < elite_count ->
          remaining = elite_count - length(front_1)
          lower_fronts = Enum.filter(population_with_metrics, fn c -> c.pareto_rank > 1 end)

          additional_elites = select_by_rank_and_distance(lower_fronts, remaining)

          {:ok, front_1 ++ additional_elites}

        # Front 1 exactly matches elite quota
        true ->
          {:ok, front_1}
      end
    end
  end

  @doc """
  Selects diverse elites, avoiding near-duplicate candidates.

  When multiple candidates have nearly identical objectives, this function
  selects only the best representative to preserve elite diversity.

  Candidates are considered duplicates if their Euclidean distance in
  normalized objective space is below the similarity threshold.

  Selection priority:
  1. Pareto rank (lower is better)
  2. Crowding distance (higher is better)
  3. Generation (older = more validated)

  ## Arguments

  - `population` - Candidates with metrics
  - `opts` - Options:
    - `:elite_count` - Number to select (required)
    - `:similarity_threshold` - Objective distance threshold (default: 0.01)

  ## Returns

  - `{:ok, diverse_elites}` - Elites with no near-duplicates

  ## Examples

      {:ok, diverse_elites} = EliteSelector.select_diverse_elites(
        population,
        elite_count: 30,
        similarity_threshold: 0.01  # 1% of objective space
      )

      # No two elites will be within 0.01 distance in objective space
      # Ensures true diversity, not just clustering around a few solutions
  """
  @spec select_diverse_elites(list(Candidate.t()), keyword()) :: selection_result()
  def select_diverse_elites(population, opts) do
    with {:ok, elite_count} <- fetch_required(opts, :elite_count),
         :ok <- validate_selection_metrics(population) do
      similarity_threshold =
        Keyword.get(opts, :similarity_threshold, @default_similarity_threshold)

      # Sort by (rank ASC, distance DESC, generation ASC)
      sorted =
        Enum.sort_by(
          population,
          fn c ->
            {c.pareto_rank, negate_distance(c.crowding_distance), c.generation}
          end,
          :asc
        )

      # Greedily select diverse elites
      elites = select_diverse_subset_greedy(sorted, elite_count, similarity_threshold)

      {:ok, elites}
    end
  end

  # Private helper functions

  @spec calculate_elite_count(non_neg_integer(), keyword()) :: pos_integer()
  defp calculate_elite_count(population_size, opts) do
    min_elites = Keyword.get(opts, :min_elites, 1)

    count =
      cond do
        Keyword.has_key?(opts, :elite_count) ->
          Keyword.get(opts, :elite_count)

        Keyword.has_key?(opts, :elite_ratio) ->
          ratio = Keyword.get(opts, :elite_ratio)
          round(population_size * ratio)

        true ->
          round(population_size * @default_elite_ratio)
      end

    max(min_elites, count)
  end

  @spec select_by_rank_and_distance(list(Candidate.t()), non_neg_integer()) :: list(Candidate.t())
  defp select_by_rank_and_distance(population, count) do
    population
    |> Enum.sort_by(
      fn c -> {c.pareto_rank, negate_distance(c.crowding_distance)} end,
      :asc
    )
    |> Enum.take(count)
  end

  @spec select_diverse_subset(list(Candidate.t()), pos_integer()) :: list(Candidate.t())
  defp select_diverse_subset(candidates, count) do
    # Select by crowding distance (highest first)
    candidates
    |> Enum.sort_by(fn c -> negate_distance(c.crowding_distance) end, :asc)
    |> Enum.take(count)
  end

  @spec select_diverse_subset_greedy(list(Candidate.t()), pos_integer(), float()) ::
          list(Candidate.t())
  defp select_diverse_subset_greedy(sorted_candidates, count, similarity_threshold) do
    {selected, _} =
      Enum.reduce(sorted_candidates, {[], 0}, fn candidate, {selected, selected_count} ->
        if selected_count >= count do
          # Already have enough elites
          {selected, selected_count}
        else
          # Check if candidate is too similar to any already-selected elite
          too_similar =
            Enum.any?(selected, fn elite ->
              objective_distance(candidate, elite) < similarity_threshold
            end)

          if too_similar do
            # Skip this candidate
            {selected, selected_count}
          else
            # Add to selected
            {selected ++ [candidate], selected_count + 1}
          end
        end
      end)

    selected
  end

  @spec objective_distance(Candidate.t(), Candidate.t()) :: float()
  defp objective_distance(a, b) do
    # Calculate Euclidean distance in normalized objective space
    a_objs = a.normalized_objectives || %{}
    b_objs = b.normalized_objectives || %{}

    objectives = (Map.keys(a_objs) ++ Map.keys(b_objs)) |> Enum.uniq()

    if Enum.empty?(objectives) do
      0.0
    else
      sum_squared_diffs =
        Enum.reduce(objectives, 0.0, fn obj, acc ->
          a_val = Map.get(a_objs, obj, 0.0)
          b_val = Map.get(b_objs, obj, 0.0)
          diff = a_val - b_val
          acc + diff * diff
        end)

      :math.sqrt(sum_squared_diffs)
    end
  end

  @spec assign_selection_metrics(list(Candidate.t()), map()) :: list(Candidate.t())
  defp assign_selection_metrics(_population, fronts) do
    # Assign ranks
    population_with_ranks =
      fronts
      |> Enum.flat_map(fn {rank, candidates} ->
        Enum.map(candidates, fn c -> %{c | pareto_rank: rank} end)
      end)

    # Assign crowding distances
    case CrowdingDistanceSelector.assign_crowding_distances(population_with_ranks) do
      {:ok, population_with_distances} -> population_with_distances
      # Fallback: return with ranks only
      {:error, _} -> population_with_ranks
    end
  end

  # Validation helpers

  @spec validate_selection_metrics(list(Candidate.t())) :: :ok | {:error, term()}
  defp validate_selection_metrics(population) do
    missing_rank = Enum.find(population, fn c -> c.pareto_rank == nil end)
    missing_distance = Enum.find(population, fn c -> c.crowding_distance == nil end)

    cond do
      missing_rank ->
        {:error, {:missing_pareto_rank, missing_rank.id}}

      missing_distance ->
        {:error, {:missing_crowding_distance, missing_distance.id}}

      true ->
        :ok
    end
  end

  @spec fetch_required(keyword(), atom()) :: {:ok, term()} | {:error, term()}
  defp fetch_required(opts, key) do
    case Keyword.fetch(opts, key) do
      {:ok, value} -> {:ok, value}
      :error -> {:error, {:missing_required_option, key}}
    end
  end

  # Helper: Handle infinity in sorting
  # Negating distance for descending sort (higher distance = better)
  @spec negate_distance(float() | :infinity) :: number()
  defp negate_distance(:infinity), do: -999_999_999
  defp negate_distance(dist) when is_number(dist), do: -dist
end
