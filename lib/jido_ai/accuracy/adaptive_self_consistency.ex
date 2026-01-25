defmodule Jido.AI.Accuracy.AdaptiveSelfConsistency do
  @moduledoc """
  Adaptive self-consistency with dynamic N and early stopping.

  This module implements self-consistency that adjusts the number of
  candidates based on query difficulty and stops early when consensus
  is reached, optimizing for both accuracy and compute efficiency.

  ## Adaptive N

  The number of candidates is adjusted based on difficulty:

  | Difficulty | Initial N | Max N | Batch Size |
  |------------|-----------|-------|------------|
  | Easy       | 3         | 5     | 3          |
  | Medium     | 5         | 10    | 3          |
  | Hard       | 10        | 20    | 5          |

  ## Early Stopping

  Generation stops early when:
  - Consensus threshold is reached (default 0.8)
  - Minimum candidates have been generated
  - Agreement score is calculated from normalized answers

  ## Usage

      # Create adapter with defaults
      adapter = AdaptiveSelfConsistency.new!(%{})

      # Run with difficulty estimate
      {:ok, difficulty} = DifficultyEstimate.new(%{level: :medium, score: 0.5})

      {:ok, result, metadata} = AdaptiveSelfConsistency.run(
        adapter,
        "What is 2+2?",
        difficulty_estimate: difficulty,
        generator: &MyApp.generate/1
      )

      # metadata.actual_n - number of candidates actually generated
      # metadata.early_stopped - true if stopped before max
      # metadata.consensus - final agreement score

  ## Consensus Calculation

  Consensus is calculated using the MajorityVote aggregator to extract
  normalized answers and calculate agreement:

      agreement_score = max_vote_count / total_candidates
      consensus_reached = agreement_score >= threshold

  ## Configuration

  - `:min_candidates` - Minimum candidates (default: 3)
  - `:max_candidates` - Maximum candidates (default: 20)
  - `:batch_size` - Candidates per consensus check (default: 3)
  - `:early_stop_threshold` - Consensus for early stop (default: 0.8)
  - `:difficulty_estimator` - Module for difficulty estimation
  - `:aggregator` - Aggregator for consensus (default: MajorityVote)

  ## Metadata

  The returned metadata includes:
  - `:actual_n` - Number of candidates generated
  - `:early_stopped` - Whether generation stopped early
  - `:consensus` - Final agreement score
  - `:difficulty_level` - Difficulty level used
  - `:initial_n` - Initial N planned for this difficulty
  - `:max_n` - Maximum N for this difficulty
  """

  alias Jido.AI.Accuracy.{
    Aggregators.MajorityVote,
    DifficultyEstimate,
    Thresholds
  }

  @type t :: %__MODULE__{
          min_candidates: pos_integer(),
          max_candidates: pos_integer(),
          batch_size: pos_integer(),
          early_stop_threshold: float(),
          difficulty_estimator: module() | nil,
          aggregator: module(),
          timeout: pos_integer()
        }

  @type options :: [
          {:difficulty_estimate, DifficultyEstimate.t()}
          | {:difficulty_level, DifficultyEstimate.level()}
          | {:generator, function()}
          | {:context, map()}
          | {:min_candidates, pos_integer()}
          | {:max_candidates, pos_integer()}
          | {:timeout, pos_integer()}
        ]

  # Defaults
  @default_min_candidates 3
  @default_max_candidates 20
  @default_batch_size 3
  @default_early_stop_threshold Thresholds.early_stop_threshold()
  @default_aggregator MajorityVote
  @default_timeout 30_000

  @enforce_keys [:min_candidates, :max_candidates]
  defstruct [
    :min_candidates,
    :max_candidates,
    batch_size: @default_batch_size,
    early_stop_threshold: @default_early_stop_threshold,
    difficulty_estimator: nil,
    aggregator: @default_aggregator,
    timeout: @default_timeout
  ]

  @doc """
  Creates a new AdaptiveSelfConsistency adapter.

  ## Parameters

  - `attrs` - Map with adapter configuration:
    - `:min_candidates` - Minimum candidates (default: 3)
    - `:max_candidates` - Maximum candidates (default: 20)
    - `:batch_size` - Batch size for consensus checks (default: 3)
    - `:early_stop_threshold` - Consensus threshold (default: 0.8)
    - `:difficulty_estimator` - Difficulty estimator module
    - `:aggregator` - Aggregator module (default: MajorityVote)
    - `:timeout` - Maximum runtime in milliseconds (default: 30_000)

  ## Returns

  - `{:ok, adapter}` on success
  - `{:error, reason}` on validation failure

  ## Examples

      {:ok, adapter} = AdaptiveSelfConsistency.new(%{
        min_candidates: 5,
        early_stop_threshold: 0.9,
        timeout: 60_000
      })

  """
  @spec new(map()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_map(attrs) do
    min_candidates = Map.get(attrs, :min_candidates, @default_min_candidates)
    max_candidates = Map.get(attrs, :max_candidates, @default_max_candidates)
    batch_size = Map.get(attrs, :batch_size, @default_batch_size)
    early_stop_threshold = Map.get(attrs, :early_stop_threshold, @default_early_stop_threshold)
    difficulty_estimator = Map.get(attrs, :difficulty_estimator)
    aggregator = Map.get(attrs, :aggregator, @default_aggregator)
    timeout = Map.get(attrs, :timeout, @default_timeout)

    with {:ok, _} <- validate_positive(min_candidates, :min_candidates),
         {:ok, _} <- validate_positive(max_candidates, :max_candidates),
         {:ok, _} <- validate_positive(batch_size, :batch_size),
         {:ok, _} <- validate_threshold(early_stop_threshold),
         {:ok, _} <- validate_min_less_than_max(min_candidates, max_candidates),
         {:ok, _} <- validate_aggregator(aggregator),
         {:ok, _} <- validate_timeout(timeout) do
      adapter = %__MODULE__{
        min_candidates: min_candidates,
        max_candidates: max_candidates,
        batch_size: batch_size,
        early_stop_threshold: early_stop_threshold,
        difficulty_estimator: difficulty_estimator,
        aggregator: aggregator,
        timeout: timeout
      }

      {:ok, adapter}
    end
  end

  @doc """
  Creates a new adapter, raising on error.

  ## Examples

      adapter = AdaptiveSelfConsistency.new!(%{min_candidates: 5})

  """
  @spec new!(map()) :: t()
  def new!(attrs) do
    case new(attrs) do
      {:ok, adapter} -> adapter
      {:error, reason} -> raise ArgumentError, "Invalid AdaptiveSelfConsistency: #{format_error(reason)}"
    end
  end

  @doc """
  Runs adaptive self-consistency for the given query.

  Generates candidates incrementally, checking for consensus after each
  batch. Stops early when consensus threshold is reached or timeout is exceeded.

  ## Parameters

  - `adapter` - The adapter struct
  - `query` - The query string
  - `opts` - Options:
    - `:difficulty_estimate` - Pre-computed difficulty estimate (optional)
    - `:difficulty_level` - Difficulty level atom (optional, used if no estimate)
    - `:generator` - Function to generate candidates (required)
    - `:context` - Additional context (optional)
    - `:timeout` - Override the adapter's timeout (optional, in milliseconds)

  ## Returns

  - `{:ok, result, metadata}` on success
  - `{:error, reason}` on failure
  - `{:error, :timeout}` if the operation exceeds the timeout

  ## Examples

      # With generator function
      {:ok, result, metadata} = AdaptiveSelfConsistency.run(
        adapter,
        "What is 2+2?",
        generator: fn query -> MyApp.generate(query) end
      )

      # With difficulty estimate and custom timeout
      {:ok, estimate} = DifficultyEstimate.new(%{level: :easy, score: 0.2})
      {:ok, result, metadata} = AdaptiveSelfConsistency.run(
        adapter,
        query,
        difficulty_estimate: estimate,
        generator: &MyApp.generate/1,
        timeout: 60_000
      )

  """
  @spec run(t(), String.t(), keyword()) :: {:ok, term(), map()} | {:error, term()}
  def run(%__MODULE__{} = adapter, query, opts) when is_binary(query) do
    generator = Keyword.get(opts, :generator)

    if is_function(generator, 1) do
      context = Keyword.get(opts, :context, %{})
      timeout = Keyword.get(opts, :timeout, adapter.timeout)

      # Get or estimate difficulty
      result =
        case Keyword.get(opts, :difficulty_estimate) do
          %DifficultyEstimate{} = estimate ->
            {:ok, estimate}

          nil ->
            case Keyword.get(opts, :difficulty_level) do
              nil when not is_nil(adapter.difficulty_estimator) ->
                estimate_difficulty(adapter, query, context)

              nil ->
                # No difficulty info and no estimator, default to medium
                {:ok, DifficultyEstimate.new!(%{level: :medium, score: 0.5})}

              level when is_atom(level) ->
                {:ok, DifficultyEstimate.new!(%{level: level, score: level_to_score(level)})}
            end
        end

      case result do
        {:ok, %DifficultyEstimate{} = estimate} ->
          # Run with timeout protection
          task = Task.async(fn -> do_run(adapter, query, estimate, generator, context) end)

          case Task.yield(task, timeout) do
            {:ok, {:ok, result, metadata}} ->
              {:ok, result, metadata}

            {:ok, {:error, reason}} ->
              {:error, reason}

            {:exit, _reason} ->
              {:error, :generator_crashed}

            nil ->
              # Timeout - kill the task
              Task.shutdown(task, :brutal_kill)
              {:error, :timeout}
          end

        {:error, _} = error ->
          error
      end
    else
      {:error, :generator_required}
    end
  end

  @doc """
  Gets the initial N for a given difficulty level.

  ## Examples

      AdaptiveSelfConsistency.initial_n_for_level(:easy)
      # => 3

      AdaptiveSelfConsistency.initial_n_for_level(:hard)
      # => 10

  """
  @spec initial_n_for_level(DifficultyEstimate.level()) :: pos_integer()
  def initial_n_for_level(:easy), do: 3
  def initial_n_for_level(:medium), do: 5
  def initial_n_for_level(:hard), do: 10

  @doc """
  Gets the max N for a given difficulty level.

  ## Examples

      AdaptiveSelfConsistency.max_n_for_level(:easy)
      # => 5

      AdaptiveSelfConsistency.max_n_for_level(:hard)
      # => 20

  """
  @spec max_n_for_level(DifficultyEstimate.level()) :: pos_integer()
  def max_n_for_level(:easy), do: 5
  def max_n_for_level(:medium), do: 10
  def max_n_for_level(:hard), do: 20

  @doc """
  Calculates the consensus (agreement) score for a list of candidates.

  Returns a value between 0.0 (no agreement) and 1.0 (full agreement).

  ## Examples

      {:ok, consensus, _} = AdaptiveSelfConsistency.check_consensus(candidates, aggregator: MajorityVote)

  """
  @spec check_consensus([struct()], keyword()) :: {:ok, float(), map()} | {:error, term()}
  def check_consensus(candidates, opts \\ []) when is_list(candidates) do
    if Enum.empty?(candidates) do
      {:error, :no_candidates}
    else
      aggregator = Keyword.get(opts, :aggregator, @default_aggregator)

      case aggregator.aggregate(candidates, []) do
        {:ok, _best, metadata} ->
          vote_distribution = Map.get(metadata, :vote_distribution, %{})
          total_votes = Map.values(vote_distribution) |> Enum.sum()

          agreement =
            if total_votes > 0 do
              max_vote = vote_distribution |> Map.values() |> Enum.max(fn -> 0 end)
              max_vote / total_votes
            else
              0.0
            end

          {:ok, agreement, metadata}

        {:error, _} = error ->
          error
      end
    end
  end

  @doc """
  Checks if consensus has been reached based on the threshold.

  ## Examples

      {:ok, reached?} = AdaptiveSelfConsistency.consensus_reached?(candidates, 0.8)

  """
  @spec consensus_reached?([struct()], float()) :: {:ok, boolean()} | {:error, term()}
  def consensus_reached?(candidates, threshold \\ @default_early_stop_threshold) do
    case check_consensus(candidates) do
      {:ok, agreement, _metadata} ->
        {:ok, agreement >= threshold}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Adjusts N based on difficulty level and current state.

  ## Parameters

  - `level` - Difficulty level
  - `current_n` - Current number of candidates
  - `opts` - Options

  ## Returns

  The next N to generate (batch size if haven't reached max, 0 if done)

  ## Examples

      AdaptiveSelfConsistency.adjust_n(:easy, 3, max_n: 5)
      # => 3 (next batch)

      AdaptiveSelfConsistency.adjust_n(:easy, 5, max_n: 5)
      # => 0 (at max)

  """
  @spec adjust_n(DifficultyEstimate.level(), non_neg_integer(), keyword()) :: non_neg_integer()
  def adjust_n(level, current_n, opts \\ []) do
    max_n = Keyword.get(opts, :max_n, max_n_for_level(level))
    batch_size = Keyword.get(opts, :batch_size, @default_batch_size)

    if current_n >= max_n do
      0
    else
      remaining = max_n - current_n
      min(batch_size, remaining)
    end
  end

  # Private functions

  defp do_run(adapter, query, estimate, generator, context) do
    level = estimate.level
    initial_n = max(initial_n_for_level(level), adapter.min_candidates)
    max_n = min(max_n_for_level(level), adapter.max_candidates)

    # Generate candidates in batches, checking for consensus
    case generate_with_early_stop(
           adapter,
           query,
           generator,
           context,
           [],
           0,
           initial_n,
           max_n,
           level
         ) do
      {:ok, result, metadata} ->
        {:ok, result, metadata}

      {:error, _reason} = error ->
        error
    end
  end

  defp generate_with_early_stop(adapter, query, generator, context, candidates, current_n, target_n, max_n, level) do
    # Generate next batch
    batch_size = adjust_n_batch(adapter.batch_size, current_n, max_n)

    if batch_size == 0 do
      # At max, aggregate and return
      aggregate_and_return(candidates, adapter, %{
        actual_n: length(candidates),
        early_stopped: false,
        consensus: nil,
        difficulty_level: level,
        initial_n: target_n,
        max_n: max_n
      })
    else
      # Generate batch
      new_candidates = generate_batch(generator, query, batch_size, context)
      all_candidates = candidates ++ new_candidates
      total_n = length(all_candidates)

      # Check for empty candidates - all generators failed
      if total_n == 0 and batch_size > 0 do
        {:error, :all_generators_failed}
      else
        # Check for consensus if we have at least min_candidates
        should_check_consensus = total_n >= adapter.min_candidates

        if should_check_consensus do
          case check_consensus(all_candidates, aggregator: adapter.aggregator) do
            {:ok, agreement, _metadata} ->
              if agreement >= adapter.early_stop_threshold do
                # Consensus reached - aggregate and return early
                aggregate_and_return(all_candidates, adapter, %{
                  actual_n: total_n,
                  early_stopped: true,
                  consensus: agreement,
                  difficulty_level: level,
                  initial_n: target_n,
                  max_n: max_n
                })
              else
                # No consensus, continue if not at max
                if total_n >= max_n do
                  aggregate_and_return(all_candidates, adapter, %{
                    actual_n: total_n,
                    early_stopped: false,
                    consensus: agreement,
                    difficulty_level: level,
                    initial_n: target_n,
                    max_n: max_n
                  })
                else
                  generate_with_early_stop(
                    adapter,
                    query,
                    generator,
                    context,
                    all_candidates,
                    total_n,
                    target_n,
                    max_n,
                    level
                  )
                end
              end

            {:error, _reason} ->
              # Consensus check failed, continue if not at max
              if total_n >= max_n do
                aggregate_and_return(all_candidates, adapter, %{
                  actual_n: total_n,
                  early_stopped: false,
                  consensus: nil,
                  difficulty_level: level,
                  initial_n: target_n,
                  max_n: max_n
                })
              else
                generate_with_early_stop(
                  adapter,
                  query,
                  generator,
                  context,
                  all_candidates,
                  total_n,
                  target_n,
                  max_n,
                  level
                )
              end
          end
        else
          # Not enough candidates to check consensus, continue
          generate_with_early_stop(
            adapter,
            query,
            generator,
            context,
            all_candidates,
            total_n,
            target_n,
            max_n,
            level
          )
        end
      end
    end
  end

  defp adjust_n_batch(batch_size, current_n, max_n) do
    if current_n + batch_size > max_n do
      max(0, max_n - current_n)
    else
      batch_size
    end
  end

  defp generate_batch(generator, query, count, _context) do
    # Generate count candidates
    # In a real implementation, this would call the generator
    # For now, return a list of dummy candidates
    for _i <- 1..count do
      case generator.(query) do
        {:ok, candidate} -> candidate
        {:error, _} -> nil
      end
    end
    |> Enum.reject(&is_nil/1)
  end

  defp aggregate_and_return(candidates, adapter, base_metadata) do
    # Check if we have any candidates to aggregate
    if Enum.empty?(candidates) do
      {:error, :no_candidates_to_aggregate}
    else
      case adapter.aggregator.aggregate(candidates, []) do
        {:ok, best, agg_metadata} ->
          consensus = Map.get(agg_metadata, :confidence, 0.0)
          final_metadata = Map.put(base_metadata, :consensus, consensus)
          final_metadata = Map.put(final_metadata, :aggregation_metadata, agg_metadata)
          {:ok, best, final_metadata}

        {:error, _reason} ->
          # If aggregation fails, return first candidate
          candidate = List.first(candidates)

          if candidate do
            final_metadata = Map.put(base_metadata, :aggregation_error, true)
            {:ok, candidate, final_metadata}
          else
            {:error, :no_candidates_to_aggregate}
          end
      end
    end
  end

  defp estimate_difficulty(adapter, query, context) do
    if adapter.difficulty_estimator do
      adapter.difficulty_estimator.estimate(adapter.difficulty_estimator, query, context)
    else
      # Default to medium
      {:ok, DifficultyEstimate.new!(%{level: :medium, score: 0.5})}
    end
  end

  # NOTE: Now delegates to centralized Thresholds module
  defp level_to_score(level), do: Thresholds.level_to_score(level)

  # Validation

  defp validate_positive(value, _field) when is_integer(value) and value > 0, do: {:ok, :valid}
  defp validate_positive(_, field), do: {:error, {field, :must_be_positive}}

  defp validate_threshold(value) when is_number(value) and value >= 0.0 and value <= 1.0, do: {:ok, :valid}
  defp validate_threshold(_), do: {:error, :early_stop_threshold_must_be_between_0_and_1}

  defp validate_min_less_than_max(min, max) when min <= max, do: {:ok, :valid}
  defp validate_min_less_than_max(_, _), do: {:error, :min_candidates_must_be_less_than_max}

  defp validate_aggregator(module) when is_atom(module) do
    if Code.ensure_loaded?(module) and function_exported?(module, :aggregate, 2) do
      {:ok, :valid}
    else
      {:error, :aggregator_must_implement_aggregate}
    end
  end

  defp validate_timeout(timeout) when is_integer(timeout) and timeout >= 1000 and timeout <= 300_000, do: {:ok, :valid}

  defp validate_timeout(_), do: {:error, :timeout_must_be_between_1000_and_300_000_ms}

  defp format_error({field, reason}) when is_atom(field) and is_atom(reason) do
    "#{field}: #{reason}"
  end

  defp format_error(atom) when is_atom(atom), do: atom
end
