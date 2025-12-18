defmodule Jido.AI.Runner.GEPA.Population do
  @moduledoc """
  Population management for GEPA evolutionary optimization.

  This module provides data structures and operations for maintaining prompt candidate
  populations throughout the evolutionary process. It handles population initialization,
  candidate management, fitness tracking, and persistence for interrupted optimizations.

  ## Key Concepts

  **Population Structure**: A structured collection of prompt candidates with:
  - Individual candidates (prompts with fitness scores and metadata)
  - Generation tracking
  - Statistical summaries
  - Diversity metrics

  **Candidate Management**: Operations for:
  - Adding new candidates to the population
  - Removing underperforming candidates
  - Replacing candidates with improved variants
  - Querying candidates by fitness or characteristics

  **Persistence**: Support for:
  - Saving population state to disk
  - Loading population from checkpoints
  - Resuming interrupted optimizations
  - Migration across versions

  ## Usage

      # Create new population
      {:ok, pop} = Population.new(size: 10, generation: 0)

      # Add candidates
      candidate = %{prompt: "Solve step by step", fitness: 0.85, metadata: %{}}
      {:ok, pop} = Population.add_candidate(pop, candidate)

      # Get best candidates
      best = Population.get_best(pop, limit: 5)

      # Update candidate fitness
      {:ok, pop} = Population.update_fitness(pop, candidate_id, 0.92)

      # Save/load population
      :ok = Population.save(pop, "/path/to/checkpoint")
      {:ok, pop} = Population.load("/path/to/checkpoint")

  ## Performance

  Population operations are optimized for:
  - O(1) candidate lookup by ID
  - O(log n) sorted fitness queries
  - Efficient bulk operations
  - Memory-efficient large populations (10K+ candidates)
  """

  use TypedStruct
  require Logger

  # Type definitions

  typedstruct module: Candidate do
    @moduledoc """
    Individual prompt candidate in the population.

    Represents a single prompt variant with its fitness evaluation,
    generation information, and metadata for tracking lineage and characteristics.

    ## Multi-Objective Support (Stage 2)

    Starting in Stage 2, candidates support multi-objective optimization with:
    - `objectives`: Raw objective values (accuracy, latency, cost, robustness)
    - `normalized_objectives`: Normalized values in [0, 1] for fair comparison
    - `pareto_rank`: Front number in non-dominated sorting (0 = best front)
    - `crowding_distance`: Density estimate for diversity preservation

    The `fitness` field is maintained for backward compatibility and can be
    computed as a weighted aggregate of normalized objectives.
    """

    field(:id, String.t(), enforce: true)
    field(:prompt, String.t(), enforce: true)
    field(:fitness, float() | nil)
    field(:generation, non_neg_integer(), enforce: true)
    field(:parent_ids, list(String.t()), default: [])
    field(:metadata, map(), default: %{})
    field(:created_at, integer(), enforce: true)
    field(:evaluated_at, integer() | nil)

    # Multi-objective fields (Stage 2: Section 2.1)
    field(:objectives, map() | nil, default: nil)
    # Example: %{accuracy: 0.90, latency: 1.5, cost: 0.02, robustness: 0.85}

    field(:normalized_objectives, map() | nil, default: nil)
    # Normalized to [0, 1] for fair comparison, with minimization objectives inverted

    field(:pareto_rank, non_neg_integer() | nil, default: nil)
    # Front number from non-dominated sorting (0 = best/non-dominated front)

    field(:crowding_distance, float() | nil, default: nil)
    # Density estimate for maintaining diversity (higher = more isolated = more valuable)
  end

  typedstruct do
    field(:candidates, map(), default: %{})
    field(:candidate_ids, list(String.t()), default: [])
    field(:size, pos_integer(), enforce: true)
    field(:generation, non_neg_integer(), default: 0)
    field(:best_fitness, float(), default: 0.0)
    field(:avg_fitness, float(), default: 0.0)
    field(:diversity, float(), default: 1.0)
    field(:created_at, integer(), enforce: true)
    field(:updated_at, integer(), enforce: true)
  end

  @type candidate :: Candidate.t()

  # Public API

  @doc """
  Creates a new empty population.

  ## Options

  - `:size` - Maximum population size (required)
  - `:generation` - Starting generation number (default: 0)

  ## Examples

      {:ok, pop} = Population.new(size: 10)
      {:ok, pop} = Population.new(size: 20, generation: 5)
  """
  @spec new(keyword()) :: {:ok, t()} | {:error, term()}
  def new(opts) do
    if Keyword.has_key?(opts, :size) do
      size = Keyword.fetch!(opts, :size)

      if is_integer(size) and size > 0 do
        do_new(size, opts)
      else
        {:error, {:invalid_size, size}}
      end
    else
      {:error, :size_required}
    end
  end

  defp do_new(size, opts) do
    generation = Keyword.get(opts, :generation, 0)
    now = System.monotonic_time(:millisecond)

    population = %__MODULE__{
      candidates: %{},
      candidate_ids: [],
      size: size,
      generation: generation,
      best_fitness: 0.0,
      avg_fitness: 0.0,
      diversity: 1.0,
      created_at: now,
      updated_at: now
    }

    {:ok, population}
  end

  @doc """
  Adds a candidate to the population.

  If the population is at capacity, the candidate is only added if it's better
  than the worst existing candidate (which is then removed).

  ## Parameters

  - `population` - The population to add to
  - `candidate_data` - Map or Candidate struct with prompt and metadata

  ## Examples

      candidate = %{
        prompt: "Solve this step by step",
        fitness: 0.85,
        metadata: %{source: :mutation}
      }
      {:ok, pop} = Population.add_candidate(pop, candidate)
  """
  @spec add_candidate(t(), map() | candidate()) :: {:ok, t()} | {:error, term()}
  def add_candidate(%__MODULE__{} = population, candidate_data) when is_map(candidate_data) do
    case ensure_candidate_struct(candidate_data, population.generation) do
      {:ok, candidate} ->
        cond do
          Map.has_key?(population.candidates, candidate.id) ->
            {:error, {:duplicate_id, candidate.id}}

          length(population.candidate_ids) < population.size ->
            add_candidate_internal(population, candidate)

          true ->
            maybe_replace_worst_candidate(population, candidate)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Removes a candidate from the population by ID.

  ## Examples

      {:ok, pop} = Population.remove_candidate(pop, "candidate-123")
  """
  @spec remove_candidate(t(), String.t()) :: {:ok, t()} | {:error, term()}
  def remove_candidate(%__MODULE__{} = population, candidate_id) do
    if Map.has_key?(population.candidates, candidate_id) do
      candidates = Map.delete(population.candidates, candidate_id)
      candidate_ids = List.delete(population.candidate_ids, candidate_id)

      updated_pop = %{
        population
        | candidates: candidates,
          candidate_ids: candidate_ids,
          updated_at: System.monotonic_time(:millisecond)
      }

      {:ok, recalculate_statistics(updated_pop)}
    else
      {:error, {:candidate_not_found, candidate_id}}
    end
  end

  @doc """
  Replaces an existing candidate with a new one.

  ## Examples

      new_candidate = %{prompt: "Improved prompt", fitness: 0.90}
      {:ok, pop} = Population.replace_candidate(pop, "old-id", new_candidate)
  """
  @spec replace_candidate(t(), String.t(), map() | candidate()) :: {:ok, t()} | {:error, term()}
  def replace_candidate(%__MODULE__{} = population, old_id, new_candidate_data) do
    with {:ok, pop} <- remove_candidate(population, old_id) do
      add_candidate(pop, new_candidate_data)
    end
  end

  @doc """
  Updates the fitness score of a candidate.

  ## Examples

      {:ok, pop} = Population.update_fitness(pop, "candidate-123", 0.92)
  """
  @spec update_fitness(t(), String.t(), float()) :: {:ok, t()} | {:error, term()}
  def update_fitness(%__MODULE__{} = population, candidate_id, fitness)
      when is_float(fitness) or is_integer(fitness) do
    if Map.has_key?(population.candidates, candidate_id) do
      candidate = Map.fetch!(population.candidates, candidate_id)
      fitness_float = if is_integer(fitness), do: fitness * 1.0, else: fitness

      updated_candidate = %{
        candidate
        | fitness: fitness_float,
          evaluated_at: System.monotonic_time(:millisecond)
      }

      candidates = Map.put(population.candidates, candidate_id, updated_candidate)

      updated_pop = %{
        population
        | candidates: candidates,
          updated_at: System.monotonic_time(:millisecond)
      }

      {:ok, recalculate_statistics(updated_pop)}
    else
      {:error, {:candidate_not_found, candidate_id}}
    end
  end

  @doc """
  Returns the best N candidates by fitness.

  ## Options

  - `:limit` - Maximum number of candidates to return (default: 10)
  - `:min_fitness` - Only return candidates with fitness >= this value

  ## Examples

      best = Population.get_best(pop, limit: 5)
      best = Population.get_best(pop, limit: 10, min_fitness: 0.7)
  """
  @spec get_best(t(), keyword()) :: list(candidate())
  def get_best(%__MODULE__{} = population, opts \\ []) do
    limit = Keyword.get(opts, :limit, 10)
    min_fitness = Keyword.get(opts, :min_fitness)

    population.candidates
    |> Map.values()
    |> Enum.filter(fn c -> c.fitness != nil end)
    |> then(fn candidates ->
      if min_fitness do
        Enum.filter(candidates, fn c -> c.fitness >= min_fitness end)
      else
        candidates
      end
    end)
    |> Enum.sort_by(& &1.fitness, :desc)
    |> Enum.take(limit)
  end

  @doc """
  Returns a candidate by ID.

  ## Examples

      {:ok, candidate} = Population.get_candidate(pop, "candidate-123")
  """
  @spec get_candidate(t(), String.t()) :: {:ok, candidate()} | {:error, term()}
  def get_candidate(%__MODULE__{} = population, candidate_id) do
    case Map.fetch(population.candidates, candidate_id) do
      {:ok, candidate} -> {:ok, candidate}
      :error -> {:error, {:candidate_not_found, candidate_id}}
    end
  end

  @doc """
  Returns all candidates in the population.

  ## Examples

      candidates = Population.get_all(pop)
  """
  @spec get_all(t()) :: list(candidate())
  def get_all(%__MODULE__{} = population) do
    Map.values(population.candidates)
  end

  @doc """
  Returns population statistics.

  ## Examples

      stats = Population.statistics(pop)
      # => %{
      #   size: 10,
      #   evaluated: 8,
      #   unevaluated: 2,
      #   best_fitness: 0.92,
      #   avg_fitness: 0.78,
      #   diversity: 0.85
      # }
  """
  @spec statistics(t()) :: map()
  def statistics(%__MODULE__{} = population) do
    candidates = Map.values(population.candidates)
    evaluated = Enum.count(candidates, fn c -> c.fitness != nil end)

    %{
      size: length(candidates),
      capacity: population.size,
      evaluated: evaluated,
      unevaluated: length(candidates) - evaluated,
      generation: population.generation,
      best_fitness: population.best_fitness,
      avg_fitness: population.avg_fitness,
      diversity: population.diversity
    }
  end

  @doc """
  Advances the population to the next generation.

  ## Examples

      {:ok, pop} = Population.next_generation(pop)
  """
  @spec next_generation(t()) :: {:ok, t()}
  def next_generation(%__MODULE__{} = population) do
    updated_pop = %{
      population
      | generation: population.generation + 1,
        updated_at: System.monotonic_time(:millisecond)
    }

    {:ok, updated_pop}
  end

  @doc """
  Saves the population to disk for persistence.

  The population is serialized to a binary format using Erlang Term Format.

  ## Examples

      :ok = Population.save(pop, "/path/to/checkpoint.pop")
  """
  @spec save(t(), String.t()) :: :ok | {:error, term()}
  def save(%__MODULE__{} = population, path) do
    Logger.debug("Saving population to #{path}")

    data = %{
      version: 1,
      population: population,
      saved_at: System.monotonic_time(:millisecond)
    }

    # Split error handling for better granularity
    try do
      binary = :erlang.term_to_binary(data, [:compressed])

      try do
        File.write!(path, binary)
        Logger.info("Population saved successfully (path: #{path}, size: #{byte_size(binary)})")
        :ok
      rescue
        error ->
          Logger.error(
            "Failed to write population file (path: #{path}, operation: file_write, error: #{Exception.message(error)})"
          )

          {:error, {:file_write_failed, error}}
      end
    rescue
      error ->
        Logger.error(
          "Failed to serialize population (path: #{path}, operation: serialization, error: #{Exception.message(error)})"
        )

        {:error, {:serialization_failed, error}}
    end
  end

  @doc """
  Loads a population from disk.

  ## Examples

      {:ok, pop} = Population.load("/path/to/checkpoint.pop")
  """
  @spec load(String.t()) :: {:ok, t()} | {:error, term()}
  def load(path) do
    Logger.debug("Loading population from #{path}")

    if File.exists?(path) do
      do_load(path)
    else
      {:error, {:file_not_found, path}}
    end
  end

  defp do_load(path) do
    # Split error handling for better granularity
    binary = File.read!(path)
    deserialize_population(binary, path)
  rescue
    error ->
      Logger.error(
        "Failed to read population file (path: #{path}, operation: file_read, error: #{Exception.message(error)})"
      )

      {:error, {:file_read_failed, error}}
  end

  defp deserialize_population(binary, path) do
    data = :erlang.binary_to_term(binary)

    case data do
      %{version: 1, population: population} ->
        Logger.info("Population loaded successfully (path: #{path})")
        {:ok, population}

      %{version: version} ->
        {:error, {:unsupported_version, version}}

      _ ->
        {:error, :invalid_format}
    end
  rescue
    error ->
      Logger.error(
        "Failed to deserialize population (path: #{path}, operation: deserialization, error: #{Exception.message(error)})"
      )

      {:error, {:deserialization_failed, error}}
  end

  # Private Functions

  @doc false
  @spec ensure_candidate_struct(map() | candidate(), non_neg_integer()) ::
          {:ok, candidate()} | {:error, :missing_prompt}
  defp ensure_candidate_struct(%Candidate{} = candidate, _generation), do: {:ok, candidate}

  defp ensure_candidate_struct(data, generation) when is_map(data) do
    case Map.fetch(data, :prompt) do
      {:ok, prompt} ->
        id = Map.get(data, :id, generate_candidate_id())
        now = System.monotonic_time(:millisecond)

        candidate = %Candidate{
          id: id,
          prompt: prompt,
          fitness: Map.get(data, :fitness),
          generation: Map.get(data, :generation, generation),
          parent_ids: Map.get(data, :parent_ids, []),
          metadata: Map.get(data, :metadata, %{}),
          created_at: Map.get(data, :created_at, now),
          evaluated_at: Map.get(data, :evaluated_at)
        }

        {:ok, candidate}

      :error ->
        {:error, :missing_prompt}
    end
  end

  @doc false
  @spec generate_candidate_id() :: String.t()
  defp generate_candidate_id do
    "cand_#{:erlang.unique_integer([:positive, :monotonic])}"
  end

  @doc false
  @spec add_candidate_internal(t(), candidate()) :: {:ok, t()}
  defp add_candidate_internal(population, candidate) do
    candidates = Map.put(population.candidates, candidate.id, candidate)
    candidate_ids = [candidate.id | population.candidate_ids]

    updated_pop = %{
      population
      | candidates: candidates,
        candidate_ids: candidate_ids,
        updated_at: System.monotonic_time(:millisecond)
    }

    {:ok, recalculate_statistics(updated_pop)}
  end

  @doc false
  @spec maybe_replace_worst_candidate(t(), candidate()) :: {:ok, t()} | {:error, term()}
  defp maybe_replace_worst_candidate(population, new_candidate) do
    # Only replace if new candidate has better fitness than worst candidate
    if new_candidate.fitness do
      worst = find_worst_candidate(population)

      if worst && (!worst.fitness || new_candidate.fitness > worst.fitness) do
        with {:ok, pop} <- remove_candidate(population, worst.id) do
          add_candidate_internal(pop, new_candidate)
        end
      else
        {:error, :population_full}
      end
    else
      {:error, :population_full}
    end
  end

  @doc false
  @spec find_worst_candidate(t()) :: candidate() | nil
  defp find_worst_candidate(population) do
    population.candidates
    |> Map.values()
    |> Enum.filter(fn c -> c.fitness != nil end)
    |> Enum.min_by(& &1.fitness, fn -> nil end)
  end

  @doc false
  @spec recalculate_statistics(t()) :: t()
  defp recalculate_statistics(population) do
    candidates = Map.values(population.candidates)
    evaluated = Enum.filter(candidates, fn c -> c.fitness != nil end)

    best_fitness =
      case evaluated do
        [] -> 0.0
        candidates -> Enum.map(candidates, & &1.fitness) |> Enum.max()
      end

    avg_fitness =
      case evaluated do
        [] ->
          0.0

        candidates ->
          sum = Enum.reduce(candidates, 0.0, fn c, acc -> acc + c.fitness end)
          sum / length(candidates)
      end

    # Simple diversity metric: ratio of unique prompts to population size
    unique_prompts =
      candidates
      |> Enum.map(& &1.prompt)
      |> Enum.uniq()
      |> length()

    diversity =
      if length(candidates) > 0 do
        unique_prompts / length(candidates)
      else
        1.0
      end

    %{
      population
      | best_fitness: best_fitness,
        avg_fitness: avg_fitness,
        diversity: diversity
    }
  end
end
