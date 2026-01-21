defmodule Jido.AI.Runner.GEPA.Selection.TournamentSelector do
  @moduledoc """
  Tournament selection for parent selection in genetic algorithms.

  Tournament selection works by randomly selecting k candidates from the population
  and choosing the best one according to a fitness criterion. This module implements
  multiple tournament variants:

  1. **Pareto Tournament**: Uses Pareto ranking as primary criterion, crowding distance as tiebreaker
  2. **Diversity-Aware Tournament**: Favors solutions in less crowded regions
  3. **Adaptive Tournament**: Adjusts tournament size based on population diversity

  ## Tournament Selection Process

  For each parent needed:
  1. Randomly sample k candidates from population
  2. Compare candidates using specified criterion
  3. Select winner as parent

  ## Comparison Criteria

  - **Pareto Ranking**: Lower rank is better (Front 1 > Front 2 > ...)
  - **Crowding Distance**: Higher distance is better (more diversity)
  - **Combined**: Rank first, then crowding distance for tiebreaking

  ## Usage

      # Basic Pareto tournament (k=3)
      {:ok, parents} = TournamentSelector.select(
        population,
        count: 10,
        tournament_size: 3,
        strategy: :pareto
      )

      # Diversity-aware tournament
      {:ok, parents} = TournamentSelector.select(
        population,
        count: 10,
        tournament_size: 3,
        strategy: :diversity
      )

      # Adaptive tournament (adjusts size based on diversity)
      {:ok, parents} = TournamentSelector.select(
        population,
        count: 10,
        strategy: :adaptive,
        min_tournament_size: 2,
        max_tournament_size: 7,
        diversity_threshold: 0.5
      )

  ## References

  - Deb et al. (2002). "A fast and elitist multiobjective genetic algorithm: NSGA-II"
  - Goldberg & Deb (1991). "A comparative analysis of selection schemes"
  """

  alias Jido.AI.Runner.GEPA.Population.Candidate

  require Logger

  @type tournament_strategy :: :pareto | :diversity | :adaptive
  @type selection_opts :: [
          count: pos_integer(),
          tournament_size: pos_integer(),
          strategy: tournament_strategy(),
          min_tournament_size: pos_integer(),
          max_tournament_size: pos_integer(),
          diversity_threshold: float()
        ]

  @doc """
  Select parents from population using tournament selection.

  ## Arguments

  - `population` - List of candidates (must have pareto_rank and crowding_distance)
  - `opts` - Selection options:
    - `:count` - Number of parents to select (required)
    - `:tournament_size` - Number of candidates per tournament (default: 3)
    - `:strategy` - Selection strategy: :pareto | :diversity | :adaptive (default: :pareto)
    - `:min_tournament_size` - Minimum tournament size for adaptive (default: 2)
    - `:max_tournament_size` - Maximum tournament size for adaptive (default: 7)
    - `:diversity_threshold` - Diversity threshold for adaptive sizing (default: 0.5)

  ## Returns

  - `{:ok, parents}` - List of selected parent candidates
  - `{:error, reason}` - Validation or selection failed

  ## Examples

      # Select 10 parents using Pareto tournament
      {:ok, parents} = TournamentSelector.select(population, count: 10)

      # Select with larger tournament size (more selection pressure)
      {:ok, parents} = TournamentSelector.select(
        population,
        count: 20,
        tournament_size: 5
      )

      # Use diversity-aware tournament
      {:ok, parents} = TournamentSelector.select(
        population,
        count: 10,
        strategy: :diversity
      )
  """
  @spec select(list(Candidate.t()), selection_opts()) ::
          {:ok, list(Candidate.t())} | {:error, term()}
  def select(population, opts) do
    with {:ok, count} <- fetch_required(opts, :count),
         :ok <- validate_population(population),
         :ok <- validate_count(count, length(population)) do
      strategy = Keyword.get(opts, :strategy, :pareto)
      tournament_size = Keyword.get(opts, :tournament_size, 3)

      # Validate tournament size
      if tournament_size < 2 or tournament_size > length(population) do
        {:error, {:invalid_tournament_size, tournament_size, length(population)}}
      else
        parents =
          case strategy do
            :pareto ->
              select_pareto_tournament(population, count, tournament_size)

            :diversity ->
              select_diversity_tournament(population, count, tournament_size)

            :adaptive ->
              select_adaptive_tournament(population, count, opts)

            _ ->
              {:error, {:invalid_strategy, strategy}}
          end

        case parents do
          {:error, _} = error -> error
          selected -> {:ok, selected}
        end
      end
    end
  end

  @doc """
  Run a single tournament and return the winner.

  ## Arguments

  - `population` - List of candidates
  - `tournament_size` - Number of candidates to compete
  - `comparator` - Function to compare two candidates, returns true if first is better

  ## Returns

  Winner candidate from the tournament

  ## Examples

      # Run Pareto tournament
      winner = TournamentSelector.run_tournament(
        population,
        3,
        &pareto_compare/2
      )
  """
  @spec run_tournament(list(Candidate.t()), pos_integer(), function()) :: Candidate.t()
  def run_tournament(population, tournament_size, comparator) do
    population
    |> Enum.take_random(tournament_size)
    |> Enum.reduce(fn candidate, best ->
      if comparator.(candidate, best), do: candidate, else: best
    end)
  end

  @doc """
  Calculate population diversity based on crowding distance distribution.

  Returns a value between 0.0 (no diversity) and 1.0 (maximum diversity).
  Uses the coefficient of variation of crowding distances.

  ## Arguments

  - `population` - List of candidates with crowding_distance

  ## Returns

  Float between 0.0 and 1.0 representing diversity level

  ## Examples

      diversity = TournamentSelector.population_diversity(population)
      # => 0.73
  """
  @spec population_diversity(list(Candidate.t())) :: float()
  def population_diversity([]), do: 0.0
  def population_diversity([_single]), do: 0.0

  def population_diversity(population) do
    # Filter candidates with valid crowding distance
    distances =
      population
      |> Enum.map(fn c -> c.crowding_distance || 0.0 end)
      |> Enum.filter(fn d -> is_number(d) and d != :infinity end)

    if Enum.empty?(distances) or length(distances) < 2 do
      0.0
    else
      mean = Enum.sum(distances) / length(distances)

      if mean == 0.0 do
        0.0
      else
        # Calculate coefficient of variation (normalized standard deviation)
        variance =
          distances
          |> Enum.map(fn d -> :math.pow(d - mean, 2) end)
          |> Enum.sum()
          |> Kernel./(length(distances))

        std_dev = :math.sqrt(variance)
        cv = std_dev / mean

        # Normalize to [0, 1] using sigmoid-like function
        # CV of 1.0 maps to ~0.76 diversity
        :math.tanh(cv)
      end
    end
  end

  # Private implementation

  @spec select_pareto_tournament(list(Candidate.t()), pos_integer(), pos_integer()) ::
          list(Candidate.t())
  defp select_pareto_tournament(population, count, tournament_size) do
    1..count
    |> Enum.map(fn _ ->
      run_tournament(population, tournament_size, &pareto_compare/2)
    end)
  end

  @spec select_diversity_tournament(list(Candidate.t()), pos_integer(), pos_integer()) ::
          list(Candidate.t())
  defp select_diversity_tournament(population, count, tournament_size) do
    1..count
    |> Enum.map(fn _ ->
      run_tournament(population, tournament_size, &diversity_compare/2)
    end)
  end

  @spec select_adaptive_tournament(list(Candidate.t()), pos_integer(), keyword()) ::
          list(Candidate.t()) | {:error, term()}
  defp select_adaptive_tournament(population, count, opts) do
    min_size = Keyword.get(opts, :min_tournament_size, 2)
    max_size = Keyword.get(opts, :max_tournament_size, 7)
    diversity_threshold = Keyword.get(opts, :diversity_threshold, 0.5)

    # Validate adaptive parameters
    cond do
      min_size < 2 ->
        {:error, {:invalid_min_tournament_size, min_size}}

      max_size > length(population) ->
        {:error, {:invalid_max_tournament_size, max_size, length(population)}}

      min_size > max_size ->
        {:error, {:min_greater_than_max, min_size, max_size}}

      true ->
        # Calculate current diversity
        diversity = population_diversity(population)

        # Adapt tournament size based on diversity
        # Low diversity -> smaller tournaments (less pressure, more exploration)
        # High diversity -> larger tournaments (more pressure, faster convergence)
        tournament_size =
          if diversity < diversity_threshold do
            min_size
          else
            # Scale linearly from min to max based on diversity
            range = max_size - min_size

            scaled =
              trunc(range * ((diversity - diversity_threshold) / (1.0 - diversity_threshold)))

            min(min_size + scaled, max_size)
          end

        Logger.debug(
          "Adaptive tournament: diversity=#{Float.round(diversity, 3)}, size=#{tournament_size}"
        )

        select_pareto_tournament(population, count, tournament_size)
    end
  end

  # Comparison functions

  @doc """
  Compare two candidates using Pareto ranking with crowding distance tiebreaking.

  Returns true if candidate A is better than candidate B:
  1. Lower Pareto rank is better (Front 1 > Front 2)
  2. If ranks equal, higher crowding distance is better (more diversity)

  ## Examples

      pareto_compare(candidate_a, candidate_b)
      # => true (if A dominates B or has better rank/distance)
  """
  @spec pareto_compare(Candidate.t(), Candidate.t()) :: boolean()
  def pareto_compare(a, b) do
    rank_a = a.pareto_rank || :infinity
    rank_b = b.pareto_rank || :infinity

    cond do
      # Lower rank is better
      rank_a < rank_b ->
        true

      rank_a > rank_b ->
        false

      # Same rank: higher crowding distance is better
      true ->
        dist_a = a.crowding_distance || 0.0
        dist_b = b.crowding_distance || 0.0

        # Handle infinity (boundary solutions)
        cond do
          dist_a == :infinity -> true
          dist_b == :infinity -> false
          true -> dist_a > dist_b
        end
    end
  end

  @doc """
  Compare two candidates with emphasis on diversity (crowding distance).

  Returns true if candidate A is better than candidate B:
  1. Higher crowding distance is better (primary criterion)
  2. If distances equal, lower Pareto rank is better (tiebreaker)

  This prioritizes exploration of sparse regions over exploitation.

  ## Examples

      diversity_compare(candidate_a, candidate_b)
      # => true (if A is in less crowded region)
  """
  @spec diversity_compare(Candidate.t(), Candidate.t()) :: boolean()
  def diversity_compare(a, b) do
    dist_a = a.crowding_distance || 0.0
    dist_b = b.crowding_distance || 0.0

    cond do
      # Boundary solutions (infinity) always win
      dist_a == :infinity and dist_b != :infinity ->
        true

      dist_b == :infinity and dist_a != :infinity ->
        false

      dist_a == :infinity and dist_b == :infinity ->
        # Both boundary: use rank as tiebreaker
        (a.pareto_rank || :infinity) < (b.pareto_rank || :infinity)

      # Higher crowding distance is better
      dist_a > dist_b ->
        true

      dist_a < dist_b ->
        false

      # Same distance: lower rank is better
      true ->
        (a.pareto_rank || :infinity) < (b.pareto_rank || :infinity)
    end
  end

  # Validation helpers

  @spec fetch_required(keyword(), atom()) :: {:ok, term()} | {:error, term()}
  defp fetch_required(opts, key) do
    case Keyword.fetch(opts, key) do
      {:ok, value} -> {:ok, value}
      :error -> {:error, {:missing_required_option, key}}
    end
  end

  @spec validate_population(list(Candidate.t())) :: :ok | {:error, term()}
  defp validate_population([]), do: {:error, :empty_population}

  defp validate_population(population) when is_list(population) do
    # Check that all candidates have required fields
    missing_fields =
      Enum.find(population, fn candidate ->
        not is_struct(candidate, Candidate) or
          candidate.pareto_rank == nil or
          candidate.crowding_distance == nil
      end)

    if missing_fields do
      {:error, :candidates_missing_ranking}
    else
      :ok
    end
  end

  defp validate_population(_), do: {:error, :invalid_population_format}

  @spec validate_count(pos_integer(), non_neg_integer()) :: :ok | {:error, term()}
  defp validate_count(count, _pop_size) when count < 1 do
    {:error, {:invalid_count, count}}
  end

  defp validate_count(_count, _pop_size), do: :ok
end
