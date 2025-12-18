defmodule Jido.AI.Runner.GEPA.Selection.CrowdingDistanceSelector do
  @moduledoc """
  Integration wrapper for crowding distance in selection operations.

  This module provides convenience functions for using crowding distance
  (calculated by DominanceComparator) in various selection contexts:

  - Survivor selection (trim population while preserving diversity)
  - Elite selection (choose diverse elites)
  - Environmental selection (NSGA-II style parent+offspring merging)
  - Boundary solution detection (identify extreme objective values)

  ## Note

  Crowding distance calculation is implemented in:
  `Jido.AI.Runner.GEPA.Pareto.DominanceComparator.crowding_distance/2`

  This module focuses on **applying** that metric for selection operations,
  not reimplementing the calculation itself.

  ## Crowding Distance in NSGA-II

  Crowding distance is a density estimation metric that measures how close
  a solution is to its neighbors in objective space. It is used to:

  1. **Preserve diversity**: Higher distance = more isolated = more valuable
  2. **Break ties**: When candidates have same Pareto rank, prefer higher distance
  3. **Trim population**: When removing candidates from a front, keep highest distance
  4. **Protect boundaries**: Extreme objective values receive infinite distance

  ## Usage

      # Assign crowding distances to population
      {:ok, population} = CrowdingDistanceSelector.assign_crowding_distances(candidates)

      # Select survivors by distance (within fronts)
      {:ok, survivors} = CrowdingDistanceSelector.select_by_crowding_distance(
        population,
        count: 50
      )

      # NSGA-II environmental selection
      {:ok, next_gen} = CrowdingDistanceSelector.environmental_selection(
        parents ++ offspring,
        target_size: 100
      )

      # Identify boundary solutions
      boundary_ids = CrowdingDistanceSelector.identify_boundary_solutions(population)
  """

  alias Jido.AI.Runner.GEPA.Pareto.DominanceComparator
  alias Jido.AI.Runner.GEPA.Population.Candidate

  require Logger

  @type selection_result :: {:ok, list(Candidate.t())} | {:error, term()}

  @doc """
  Updates population with crowding distances.

  Calculates crowding distance for each Pareto front separately,
  then assigns distances to the `crowding_distance` field of each candidate.

  This is a convenience wrapper around `DominanceComparator.crowding_distance/2`
  that handles the common case of computing distances for an entire population.

  ## Arguments

  - `population` - List of candidates with `pareto_rank` assigned
  - `opts` - Options (passed to DominanceComparator.crowding_distance/2)

  ## Returns

  - `{:ok, population}` - Population with `crowding_distance` assigned to each candidate
  - `{:error, reason}` - Validation or calculation failed

  ## Examples

      # After non-dominated sorting
      {:ok, fronts} = DominanceComparator.fast_non_dominated_sort(population)
      population_with_ranks = assign_ranks_from_fronts(fronts)

      # Assign crowding distances
      {:ok, population_with_distances} =
        CrowdingDistanceSelector.assign_crowding_distances(population_with_ranks)

      # Now candidates have both pareto_rank and crowding_distance set
  """
  @spec assign_crowding_distances(list(Candidate.t()), keyword()) :: selection_result()
  def assign_crowding_distances(population, opts \\ [])

  def assign_crowding_distances([], _opts), do: {:ok, []}

  def assign_crowding_distances(population, opts) do
    # Validate that candidates have pareto_rank assigned
    case validate_pareto_ranks(population) do
      :ok ->
        # Group by Pareto front
        fronts = Enum.group_by(population, & &1.pareto_rank)

        # Calculate crowding distance for each front separately
        population_with_distances =
          Enum.flat_map(fronts, fn {_rank, front_candidates} ->
            # Call existing DominanceComparator function
            distances = DominanceComparator.crowding_distance(front_candidates, opts)

            # Assign to candidate struct
            Enum.map(front_candidates, fn candidate ->
              distance = Map.get(distances, candidate.id, 0.0)
              %{candidate | crowding_distance: distance}
            end)
          end)

        {:ok, population_with_distances}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Selects candidates prioritizing higher crowding distance within each front.

  Used for survivor selection when trimming population. Selection proceeds by:
  1. Sort by Pareto rank (ascending - front 1 first)
  2. Within each rank, sort by crowding distance (descending - high distance first)
  3. Take first N candidates

  This ensures:
  - Better fronts are preferred
  - Within each front, diverse (high distance) candidates are preferred
  - Boundary solutions (infinite distance) are always preserved

  ## Arguments

  - `population` - Candidates with `pareto_rank` and `crowding_distance`
  - `opts` - Options:
    - `:count` - Number of survivors to select (required)

  ## Returns

  - `{:ok, survivors}` - Selected candidates (length = count)
  - `{:error, reason}` - Validation failed or count > population size

  ## Examples

      # Trim population from 200 to 100, keeping most diverse
      {:ok, survivors} = CrowdingDistanceSelector.select_by_crowding_distance(
        population,
        count: 100
      )

      # All Front 1 candidates will be selected first
      # Then Front 2 candidates with highest crowding distance
      # etc.
  """
  @spec select_by_crowding_distance(list(Candidate.t()), keyword()) :: selection_result()
  def select_by_crowding_distance(population, opts) do
    with {:ok, count} <- fetch_required(opts, :count),
         :ok <- validate_count(count, length(population)),
         :ok <- validate_pareto_ranks(population),
         :ok <- validate_crowding_distances(population) do
      # Sort by (rank ASC, distance DESC)
      # Infinity distance sorts before any finite distance
      survivors =
        population
        |> Enum.sort_by(
          fn c ->
            {c.pareto_rank, negate_distance(c.crowding_distance)}
          end,
          :asc
        )
        |> Enum.take(count)

      {:ok, survivors}
    end
  end

  @doc """
  Environmental selection: Combines parents and offspring, selects best N.

  This implements the NSGA-II survivor selection strategy:
  1. Perform non-dominated sorting on combined population
  2. Calculate crowding distances within each front
  3. Add fronts in order (Front 1, Front 2, ...) until next would exceed target
  4. From the cutoff front, select candidates with highest crowding distance

  This is the standard NSGA-II selection that:
  - Preserves elitism (best fronts survive)
  - Maintains diversity (crowding distance tie-breaking)
  - Provides smooth population control (exact target size)

  ## Arguments

  - `combined_population` - Parents + offspring (must have `normalized_objectives`)
  - `opts` - Options:
    - `:target_size` - Desired population size (required)

  ## Returns

  - `{:ok, survivors}` - Selected population for next generation (length = target_size)
  - `{:error, reason}` - Selection failed

  ## Examples

      # Standard NSGA-II generation transition
      parents = current_generation  # 100 candidates
      offspring = generate_offspring(parents, count: 100)  # 100 new candidates

      {:ok, next_generation} = CrowdingDistanceSelector.environmental_selection(
        parents ++ offspring,
        target_size: 100
      )

      # Result: 100 best candidates from 200, selected by (rank, distance)
  """
  @spec environmental_selection(list(Candidate.t()), keyword()) :: selection_result()
  def environmental_selection(combined_population, opts) do
    with {:ok, target_size} <- fetch_required(opts, :target_size),
         :ok <- validate_target_size(target_size, length(combined_population)) do
      # Step 1: Non-dominated sorting
      fronts = DominanceComparator.fast_non_dominated_sort(combined_population)

      # Step 2: Assign ranks to candidates
      population_with_ranks =
        fronts
        |> Enum.flat_map(fn {rank, candidates} ->
          Enum.map(candidates, fn c -> %{c | pareto_rank: rank} end)
        end)

      # Step 3: Assign crowding distances within each front
      {:ok, population_with_distances} =
        assign_crowding_distances(population_with_ranks, opts)

      # Step 4: Fill survivor population front by front
      survivors =
        fill_population_by_fronts(
          fronts,
          population_with_distances,
          target_size
        )

      {:ok, survivors}
    end
  end

  @doc """
  Identifies boundary solutions with extreme objective values.

  A candidate is a boundary solution if it has the minimum OR maximum
  value in ANY objective across the population. Boundary solutions are
  important because they:

  - Define the extent of the Pareto frontier
  - Show the best achievable value in each objective
  - Receive infinite crowding distance (highest priority)
  - Should never be eliminated during selection

  ## Arguments

  - `population` - Candidates with `normalized_objectives`

  ## Returns

  List of candidate IDs that are boundary solutions.

  ## Examples

      boundary_ids = CrowdingDistanceSelector.identify_boundary_solutions(population)
      # => ["candidate_17", "candidate_42", "candidate_83"]

      # Verify they have infinite crowding distance
      boundary_candidates = Enum.filter(population, fn c -> c.id in boundary_ids end)
      assert Enum.all?(boundary_candidates, fn c -> c.crowding_distance == :infinity end)
  """
  @spec identify_boundary_solutions(list(Candidate.t())) :: list(String.t())
  def identify_boundary_solutions([]), do: []

  def identify_boundary_solutions(population) do
    # Get all objectives from first candidate
    first_candidate = List.first(population)

    objectives =
      case first_candidate.normalized_objectives do
        nil -> []
        obj_map -> Map.keys(obj_map)
      end

    if Enum.empty?(objectives) do
      []
    else
      # For each objective, find min and max candidates
      boundary_ids =
        Enum.flat_map(objectives, fn obj ->
          # Get candidates sorted by this objective
          candidates_with_values =
            population
            |> Enum.map(fn c ->
              {c, Map.get(c.normalized_objectives || %{}, obj, 0.0)}
            end)
            |> Enum.sort_by(fn {_c, val} -> val end)

          # Min and max for this objective
          {min_candidate, _} = List.first(candidates_with_values)
          {max_candidate, _} = List.last(candidates_with_values)

          [min_candidate.id, max_candidate.id]
        end)
        |> Enum.uniq()

      boundary_ids
    end
  end

  # Private helper functions

  @spec fill_population_by_fronts(map(), list(Candidate.t()), pos_integer()) ::
          list(Candidate.t())
  defp fill_population_by_fronts(fronts, population_with_distances, target_size) do
    # Create lookup map for candidates with distances
    candidate_map = Map.new(population_with_distances, fn c -> {c.id, c} end)

    # Get front ranks in order
    front_ranks = Map.keys(fronts) |> Enum.sort()

    # Fill population front by front
    {survivors, _remaining_space} =
      Enum.reduce_while(front_ranks, {[], target_size}, fn rank, {selected, remaining} ->
        front_candidate_ids = Enum.map(fronts[rank], & &1.id)
        front_candidates = Enum.map(front_candidate_ids, fn id -> candidate_map[id] end)

        if length(front_candidates) <= remaining do
          # Entire front fits
          {:cont, {selected ++ front_candidates, remaining - length(front_candidates)}}
        else
          # Front needs trimming - select by crowding distance
          # Sort front by crowding distance (descending)
          selected_from_front =
            front_candidates
            |> Enum.sort_by(fn c -> negate_distance(c.crowding_distance) end, :asc)
            |> Enum.take(remaining)

          {:halt, {selected ++ selected_from_front, 0}}
        end
      end)

    survivors
  end

  # Validation helpers

  @spec validate_pareto_ranks(list(Candidate.t())) :: :ok | {:error, term()}
  defp validate_pareto_ranks(population) do
    missing_rank = Enum.find(population, fn c -> c.pareto_rank == nil end)

    if missing_rank do
      {:error, {:missing_pareto_rank, missing_rank.id}}
    else
      :ok
    end
  end

  @spec validate_crowding_distances(list(Candidate.t())) :: :ok | {:error, term()}
  defp validate_crowding_distances(population) do
    missing_distance = Enum.find(population, fn c -> c.crowding_distance == nil end)

    if missing_distance do
      {:error, {:missing_crowding_distance, missing_distance.id}}
    else
      :ok
    end
  end

  @spec validate_count(pos_integer(), non_neg_integer()) :: :ok | {:error, term()}
  defp validate_count(count, _pop_size) when count < 1 do
    {:error, {:invalid_count, count}}
  end

  defp validate_count(count, pop_size) when count > pop_size do
    {:error, {:count_exceeds_population, count, pop_size}}
  end

  defp validate_count(_count, _pop_size), do: :ok

  @spec validate_target_size(pos_integer(), non_neg_integer()) :: :ok | {:error, term()}
  defp validate_target_size(target, _pop_size) when target < 1 do
    {:error, {:invalid_target_size, target}}
  end

  defp validate_target_size(target, pop_size) when target > pop_size do
    {:error, {:target_exceeds_population, target, pop_size}}
  end

  defp validate_target_size(_target, _pop_size), do: :ok

  @spec fetch_required(keyword(), atom()) :: {:ok, term()} | {:error, term()}
  defp fetch_required(opts, key) do
    case Keyword.fetch(opts, key) do
      {:ok, value} -> {:ok, value}
      :error -> {:error, {:missing_required_option, key}}
    end
  end

  # Helper: Handle infinity in sorting
  # Negating distance for descending sort (higher distance = better)
  # Infinity becomes most negative number (sorts first when using :asc)
  @spec negate_distance(float() | :infinity) :: number()
  defp negate_distance(:infinity), do: -999_999_999
  defp negate_distance(dist) when is_number(dist), do: -dist
end
