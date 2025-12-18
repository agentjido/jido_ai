defmodule Jido.AI.Runner.GEPA.Selection.FitnessSharing do
  @moduledoc """
  Fitness sharing for GEPA multi-objective optimization.

  Fitness sharing penalizes solutions in crowded regions of objective space,
  promoting diversity and niche formation. Each candidate's fitness is divided
  by its "niche count" - the number of similar solutions nearby.

  ## Mechanism

  **Shared fitness**: `f_shared(i) = f_raw(i) / niche_count(i)`

  **Niche count**: Sum of sharing function over all other solutions

  **Sharing function**: `sh(distance) =`
  - `1 - (distance / niche_radius)^α` if distance < niche_radius
  - `0` otherwise

  Where:
  - **distance**: Euclidean distance in normalized objective space
  - **niche_radius**: Similarity threshold (typically 0.05-0.2)
  - **α**: Sharing slope (typically 1.0 or 2.0)

  ## Effects

  - **Crowded solutions**: High niche count → low shared fitness → less likely selected
  - **Isolated solutions**: Low niche count → high shared fitness → more likely selected
  - **Promotes speciation**: Stable subpopulations in different niches
  - **Maintains diversity**: Prevents convergence to single solution

  ## Niche Radius Selection

  - **Too small**: No diversity pressure, clustering occurs
  - **Optimal**: ~10% of objective space diagonal
  - **Too large**: Over-penalization, population spreads too thin

  ## Usage

      # Apply fitness sharing to population
      {:ok, shared_pop} = FitnessSharing.apply_sharing(population, niche_radius: 0.1)

      # Calculate niche count for a candidate
      count = FitnessSharing.niche_count(candidate, population, niche_radius: 0.1)

      # Calculate appropriate niche radius
      radius = FitnessSharing.calculate_niche_radius(population, strategy: :objective_range)

      # Adaptive sharing (only when diversity is low)
      {:ok, shared_pop} = FitnessSharing.adaptive_apply_sharing(
        population,
        diversity_threshold: 0.3
      )

  ## Integration with Selection

  Fitness sharing should be applied BEFORE selection:
  1. Evaluate raw fitness
  2. Apply fitness sharing
  3. Run tournament selection using shared fitness
  4. Generate offspring
  5. Repeat

  ## References

  - Goldberg & Richardson (1987). "Genetic algorithms with sharing for multimodal function optimization"
  - Horn et al. (1994). "The niched pareto genetic algorithm"
  """

  alias Jido.AI.Runner.GEPA.Population.Candidate

  require Logger

  @default_niche_radius 0.1
  @default_sharing_alpha 1.0
  @default_diversity_threshold 0.3

  @type sharing_result :: {:ok, list(Candidate.t())} | {:ok, list(Candidate.t()), :skipped}

  @doc """
  Applies fitness sharing to population.

  Calculates niche counts and shared fitness for all candidates.
  Updates `candidate.fitness` to shared_fitness for selection.
  Original fitness is preserved in metadata for inspection.

  ## Arguments

  - `population` - Candidates with `normalized_objectives` and `fitness`
  - `opts` - Options:
    - `:niche_radius` - Similarity threshold (default: 0.1)
    - `:sharing_alpha` - Sharing slope (default: 1.0)
    - `:preserve_raw_fitness` - Store original fitness in metadata (default: true)

  ## Returns

  - `{:ok, population}` - Candidates with shared fitness

  ## Examples

      # Basic sharing with default parameters
      {:ok, shared_pop} = FitnessSharing.apply_sharing(population)

      # Custom niche radius and slope
      {:ok, shared_pop} = FitnessSharing.apply_sharing(
        population,
        niche_radius: 0.15,
        sharing_alpha: 2.0
      )

      # Check niche count in metadata
      candidate = List.first(shared_pop)
      niche_count = candidate.metadata.niche_count
      raw_fitness = candidate.metadata.raw_fitness
      shared_fitness = candidate.fitness
  """
  @spec apply_sharing(list(Candidate.t()), keyword()) :: {:ok, list(Candidate.t())}
  def apply_sharing(population, opts \\ [])

  def apply_sharing([], _opts), do: {:ok, []}

  def apply_sharing(population, opts) do
    niche_radius = Keyword.get(opts, :niche_radius, @default_niche_radius)
    sharing_alpha = Keyword.get(opts, :sharing_alpha, @default_sharing_alpha)
    preserve_raw = Keyword.get(opts, :preserve_raw_fitness, true)

    shared_population =
      Enum.map(population, fn candidate ->
        # Calculate niche count
        nc =
          niche_count(candidate, population,
            niche_radius: niche_radius,
            sharing_alpha: sharing_alpha
          )

        # Calculate shared fitness
        raw_fitness = candidate.fitness || 0.0
        shared_fitness = if nc > 0, do: raw_fitness / nc, else: raw_fitness

        # Update candidate
        metadata =
          if preserve_raw do
            candidate.metadata
            |> Map.put(:raw_fitness, raw_fitness)
            |> Map.put(:niche_count, nc)
          else
            candidate.metadata
          end

        %{candidate | fitness: shared_fitness, metadata: metadata}
      end)

    {:ok, shared_population}
  end

  @doc """
  Calculates niche count for a candidate.

  Sums sharing function over all candidates in population (including itself).
  Minimum value is 1.0 (candidate shares niche with itself).

  ## Arguments

  - `candidate` - Candidate to calculate niche count for
  - `population` - All candidates (must include `candidate`)
  - `opts` - Options:
    - `:niche_radius` - Similarity threshold (default: 0.1)
    - `:sharing_alpha` - Sharing slope (default: 1.0)

  ## Returns

  Float >= 1.0 representing number of similar solutions

  ## Examples

      # Isolated candidate (only itself in niche)
      count = FitnessSharing.niche_count(candidate, population)
      # => ~1.0

      # Crowded candidate (many similar solutions)
      count = FitnessSharing.niche_count(candidate, crowded_population)
      # => ~5.2 (penalized fitness: f_raw / 5.2)
  """
  @spec niche_count(Candidate.t(), list(Candidate.t()), keyword()) :: float()
  def niche_count(candidate, population, opts \\ []) do
    niche_radius = Keyword.get(opts, :niche_radius, @default_niche_radius)
    sharing_alpha = Keyword.get(opts, :sharing_alpha, @default_sharing_alpha)

    population
    |> Enum.map(fn other ->
      distance = objective_distance(candidate, other)
      sharing_function(distance, niche_radius, sharing_alpha)
    end)
    |> Enum.sum()
  end

  @doc """
  Calculates appropriate niche radius for population.

  Niche radius controls sharing intensity:
  - **Small radius**: Only very similar solutions share fitness (weak diversity pressure)
  - **Large radius**: Many solutions share fitness (strong diversity pressure)

  ## Strategies

  - `:fixed` - Use provided radius
  - `:population_based` - Based on population size (larger pop → smaller radius)
  - `:objective_range` - Fraction of objective space diagonal (default: 0.1)
  - `:adaptive` - Based on population diversity

  ## Arguments

  - `population` - Current population
  - `opts` - Options:
    - `:strategy` - Calculation strategy (default: :objective_range)
    - `:radius` - For :fixed strategy
    - `:fraction` - For :objective_range strategy (default: 0.1)
    - `:base_radius` - For :population_based strategy (default: 0.3)
    - `:target_diversity` - For :adaptive strategy (default: 0.3)

  ## Returns

  Calculated niche radius (float > 0)

  ## Examples

      # Default: 10% of objective space diagonal
      radius = FitnessSharing.calculate_niche_radius(population)

      # Fixed radius
      radius = FitnessSharing.calculate_niche_radius(
        population,
        strategy: :fixed,
        radius: 0.15
      )

      # Adaptive to population diversity
      radius = FitnessSharing.calculate_niche_radius(
        population,
        strategy: :adaptive
      )
  """
  @spec calculate_niche_radius(list(Candidate.t()), keyword()) :: float()
  def calculate_niche_radius(population, opts \\ [])

  def calculate_niche_radius([], _opts), do: @default_niche_radius

  def calculate_niche_radius(population, opts) do
    strategy = Keyword.get(opts, :strategy, :objective_range)

    case strategy do
      :fixed ->
        Keyword.get(opts, :radius, @default_niche_radius)

      :population_based ->
        # Larger populations need smaller radius to maintain niches
        # radius = base_radius / sqrt(population_size)
        base = Keyword.get(opts, :base_radius, 0.3)
        base / :math.sqrt(length(population))

      :objective_range ->
        # Fraction of objective space diagonal
        fraction = Keyword.get(opts, :fraction, 0.1)
        diagonal = objective_space_diagonal(population)
        diagonal * fraction

      :adaptive ->
        # Based on current diversity
        adaptive_niche_radius(population, opts)
    end
  end

  @doc """
  Conditionally applies fitness sharing based on diversity state.

  Only applies sharing when diversity is below threshold, to avoid
  unnecessary computation when population is already diverse.

  This is useful for:
  - Performance optimization (skip sharing when not needed)
  - Avoiding over-penalization of already diverse populations
  - Adaptive diversity maintenance

  ## Arguments

  - `population` - Current population with `crowding_distance` assigned
  - `opts` - Options:
    - `:diversity_threshold` - Apply sharing if diversity < this (default: 0.3)
    - `:diversity_metric` - :crowding | :pairwise_distance (default: :crowding)
    - `:niche_radius` - Radius for sharing if applied
    - `:sharing_alpha` - Alpha for sharing if applied

  ## Returns

  - `{:ok, population}` - With sharing applied if needed
  - `{:ok, population, :skipped}` - Sharing skipped (already diverse)

  ## Examples

      # Only apply sharing if diversity is low
      case FitnessSharing.adaptive_apply_sharing(population) do
        {:ok, shared_pop} ->
          # Sharing was applied
          Logger.info("Applied fitness sharing")
          shared_pop

        {:ok, pop, :skipped} ->
          # Population already diverse, sharing skipped
          Logger.debug("Skipped fitness sharing - population diverse")
          pop
      end
  """
  @spec adaptive_apply_sharing(list(Candidate.t()), keyword()) :: sharing_result()
  def adaptive_apply_sharing(population, opts \\ [])

  def adaptive_apply_sharing([], _opts), do: {:ok, [], :skipped}

  def adaptive_apply_sharing(population, opts) do
    threshold = Keyword.get(opts, :diversity_threshold, @default_diversity_threshold)
    metric = Keyword.get(opts, :diversity_metric, :crowding)

    # Calculate current diversity
    diversity = population_diversity(population, metric)

    if diversity < threshold do
      # Low diversity: apply sharing
      Logger.debug(
        "Applying fitness sharing (diversity: #{Float.round(diversity, 3)} < #{threshold})"
      )

      apply_sharing(population, opts)
    else
      # Good diversity: skip sharing
      Logger.debug(
        "Skipping fitness sharing (diversity: #{Float.round(diversity, 3)} >= #{threshold})"
      )

      {:ok, population, :skipped}
    end
  end

  # Private helper functions

  @spec sharing_function(float(), float(), float()) :: float()
  defp sharing_function(distance, niche_radius, alpha) do
    if distance < niche_radius do
      1.0 - :math.pow(distance / niche_radius, alpha)
    else
      0.0
    end
  end

  @spec objective_distance(Candidate.t(), Candidate.t()) :: float()
  defp objective_distance(candidate_a, candidate_b) do
    # Calculate Euclidean distance in normalized objective space
    a_objs = candidate_a.normalized_objectives || %{}
    b_objs = candidate_b.normalized_objectives || %{}

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

  @spec objective_space_diagonal(list(Candidate.t())) :: float()
  defp objective_space_diagonal(population) do
    # Calculate diagonal of bounding box in normalized objective space
    first_candidate = List.first(population)

    objectives =
      case first_candidate.normalized_objectives do
        nil -> []
        obj_map -> Map.keys(obj_map)
      end

    if Enum.empty?(objectives) do
      # Default diagonal
      1.0
    else
      # For normalized objectives in [0, 1], diagonal = sqrt(num_objectives)
      :math.sqrt(length(objectives))
    end
  end

  @spec adaptive_niche_radius(list(Candidate.t()), keyword()) :: float()
  defp adaptive_niche_radius(population, opts) do
    # Calculate average pairwise distance
    avg_distance = average_pairwise_distance(population)

    # Adjust radius based on diversity
    # High avg_distance → good diversity → small radius (maintain)
    # Low avg_distance → poor diversity → large radius (spread out)
    target_diversity = Keyword.get(opts, :target_diversity, 0.3)

    cond do
      avg_distance < target_diversity * 0.5 ->
        # Very low diversity: large radius to spread population
        max(avg_distance * 2.0, @default_niche_radius)

      avg_distance < target_diversity ->
        # Low diversity: increase radius
        avg_distance * 1.5

      true ->
        # Good diversity: moderate radius to maintain
        avg_distance * 0.5
    end
  end

  @spec average_pairwise_distance(list(Candidate.t())) :: float()
  defp average_pairwise_distance(population) when length(population) < 2, do: 0.0

  defp average_pairwise_distance(population) do
    # Sample pairwise distances (full computation is O(N^2))
    # For large populations, sample to keep it tractable
    sample_size = min(50, length(population))
    sampled = Enum.take_random(population, sample_size)

    distances =
      for a <- sampled, b <- sampled, a.id != b.id do
        objective_distance(a, b)
      end

    if Enum.empty?(distances) do
      0.0
    else
      Enum.sum(distances) / length(distances)
    end
  end

  @spec population_diversity(list(Candidate.t()), atom()) :: float()
  defp population_diversity(population, :crowding) do
    # Use crowding distance as diversity metric
    distances =
      population
      |> Enum.map(fn c -> c.crowding_distance || 0.0 end)
      |> Enum.filter(fn d -> is_number(d) and d != :infinity end)

    if Enum.empty?(distances) do
      0.0
    else
      # Average crowding distance
      Enum.sum(distances) / length(distances)
    end
  end

  defp population_diversity(population, :pairwise_distance) do
    # Use average pairwise distance as diversity metric
    average_pairwise_distance(population)
  end
end
