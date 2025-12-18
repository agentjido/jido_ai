defmodule Jido.AI.Runner.GEPA.Pareto.MultiObjectiveEvaluator do
  @moduledoc """
  Multi-objective fitness evaluation for GEPA prompt optimization.

  This module implements Task 2.1.1 of GEPA Stage 2, providing multi-objective
  evaluation that measures prompts across multiple performance dimensions:
  accuracy, latency, cost, and robustness.

  ## Key Concepts

  **Multi-Objective Optimization**: Unlike single-objective optimization that
  seeks a single "best" solution, multi-objective optimization maintains a set
  of non-dominated solutions (Pareto frontier) representing optimal trade-offs
  between competing objectives.

  **Objectives**:
  - **Accuracy**: Task success rate (maximize)
  - **Latency**: Average execution time in seconds (minimize)
  - **Cost**: Token usage cost in dollars (minimize)
  - **Robustness**: Inverse of performance variance (maximize)

  **Normalization**: Objectives are normalized to [0, 1] for fair comparison,
  with minimization objectives inverted so that higher is always better.

  ## Usage

      # Evaluate a candidate with trajectory results
      objectives = MultiObjectiveEvaluator.evaluate(trajectory_results, opts)
      # => %{accuracy: 0.90, latency: 1.5, cost: 0.02, robustness: 0.85}

      # Normalize objectives for comparison
      normalized = MultiObjectiveEvaluator.normalize_objectives(
        objectives,
        population_stats
      )
      # => %{accuracy: 0.90, latency: 0.75, cost: 0.80, robustness: 0.85}

      # Compute weighted aggregate fitness (backward compatibility)
      fitness = MultiObjectiveEvaluator.aggregate_fitness(normalized, weights: %{
        accuracy: 0.5, latency: 0.2, cost: 0.2, robustness: 0.1
      })
      # => 0.845

  ## Custom Objectives

  Custom objective functions can be defined for domain-specific optimization:

      custom_objectives = %{
        factuality: fn results -> calculate_factuality(results) end,
        conciseness: fn results -> calculate_conciseness(results) end
      }

      objectives = MultiObjectiveEvaluator.evaluate(
        results,
        custom_objectives: custom_objectives,
        objective_types: %{factuality: :maximize, conciseness: :maximize}
      )
  """

  alias Jido.AI.Runner.GEPA.Population.Candidate

  require Logger

  # Standard objectives
  @standard_objectives [:accuracy, :latency, :cost, :robustness]

  # Default objective weights for aggregate fitness
  @default_weights %{
    accuracy: 0.5,
    latency: 0.2,
    cost: 0.2,
    robustness: 0.1
  }

  # Default cost per 1K tokens (approximate for GPT-4)
  @default_cost_per_1k_tokens 0.03

  @type objective_name :: atom()
  @type objective_value :: float()
  @type objectives :: %{objective_name() => objective_value()}
  @type objective_type :: :maximize | :minimize
  @type objective_function :: (list() -> float())

  @doc """
  Evaluates a candidate across multiple objectives.

  ## Arguments

  - `trajectory_results` - List of evaluation results with metrics
  - `opts` - Options:
    - `:model_pricing` - Pricing information for cost calculation
    - `:custom_objectives` - Map of custom objective functions
    - `:objective_types` - Map specifying :maximize or :minimize for each objective
    - `:objectives` - List of objectives to evaluate (default: all standard)

  ## Returns

  Map of objective values, e.g.:
  `%{accuracy: 0.90, latency: 1.5, cost: 0.02, robustness: 0.85}`
  """
  @spec evaluate(list(map()), keyword()) :: {:ok, objectives()} | {:error, term()}
  def evaluate(trajectory_results, opts \\ [])

  def evaluate([], _opts) do
    {:error, :no_trajectory_results}
  end

  def evaluate(trajectory_results, opts) when is_list(trajectory_results) do
    objectives_to_eval = Keyword.get(opts, :objectives, @standard_objectives)
    custom_objectives = Keyword.get(opts, :custom_objectives, %{})

    model_pricing =
      Keyword.get(opts, :model_pricing, %{cost_per_1k_tokens: @default_cost_per_1k_tokens})

    try do
      objectives =
        objectives_to_eval
        |> Enum.map(fn obj ->
          value = measure_objective(obj, trajectory_results, model_pricing, custom_objectives)
          {obj, value}
        end)
        |> Map.new()

      {:ok, objectives}
    rescue
      e ->
        Logger.error("Failed to evaluate objectives: #{inspect(e)}")
        {:error, {:evaluation_failed, Exception.message(e)}}
    end
  end

  def evaluate(_trajectory_results, _opts) do
    {:error, :invalid_trajectory_results}
  end

  # Measures a specific objective from trajectory results.
  @spec measure_objective(objective_name(), list(map()), map(), map()) :: float()
  defp measure_objective(:accuracy, trajectory_results, _pricing, _custom) do
    measure_accuracy(trajectory_results)
  end

  defp measure_objective(:latency, trajectory_results, _pricing, _custom) do
    measure_latency(trajectory_results)
  end

  defp measure_objective(:cost, trajectory_results, pricing, _custom) do
    measure_cost(trajectory_results, pricing)
  end

  defp measure_objective(:robustness, trajectory_results, _pricing, _custom) do
    measure_robustness(trajectory_results)
  end

  defp measure_objective(custom_obj, trajectory_results, _pricing, custom_objectives)
       when is_map_key(custom_objectives, custom_obj) do
    custom_fn = Map.get(custom_objectives, custom_obj)
    custom_fn.(trajectory_results)
  end

  defp measure_objective(unknown, _results, _pricing, _custom) do
    Logger.warning("Unknown objective: #{unknown}, returning 0.0")
    0.0
  end

  # Objective measurement functions

  # Measures accuracy as the success rate on evaluation tasks.
  # Returns a float in [0.0, 1.0] where 1.0 = 100% success rate.
  @spec measure_accuracy(list(map())) :: float()
  defp measure_accuracy(trajectory_results) do
    successes =
      Enum.count(trajectory_results, fn result ->
        Map.get(result, :success, false)
      end)

    total = max(length(trajectory_results), 1)
    Float.round(successes / total, 4)
  end

  # Measures latency as the average execution time in seconds.
  @spec measure_latency(list(map())) :: float()
  defp measure_latency(trajectory_results) do
    durations =
      Enum.map(trajectory_results, fn result ->
        Map.get(result, :duration_ms, 0)
      end)

    total_duration = Enum.sum(durations)
    count = max(length(durations), 1)
    avg_ms = total_duration / count

    # Convert to seconds and round
    Float.round(avg_ms / 1000.0, 4)
  end

  # Measures cost based on token usage (in dollars).
  @spec measure_cost(list(map()), map()) :: float()
  defp measure_cost(trajectory_results, model_pricing) do
    cost_per_1k = Map.get(model_pricing, :cost_per_1k_tokens, @default_cost_per_1k_tokens)

    total_tokens =
      Enum.reduce(trajectory_results, 0, fn result, acc ->
        prompt_tokens = Map.get(result, :prompt_tokens, 0)
        completion_tokens = Map.get(result, :completion_tokens, 0)
        acc + prompt_tokens + completion_tokens
      end)

    cost = total_tokens * cost_per_1k / 1000.0
    Float.round(cost, 4)
  end

  # Measures robustness as the inverse of performance variance.
  # Returns a float in [0.0, 1.0] where 1.0 = perfectly consistent performance.
  @spec measure_robustness(list(map())) :: float()
  defp measure_robustness(trajectory_results) do
    scores =
      Enum.map(trajectory_results, fn result ->
        Map.get(result, :quality_score, 0.0)
      end)

    case scores do
      [] ->
        0.0

      [_single] ->
        # Single result = perfect consistency
        1.0

      scores ->
        mean = Enum.sum(scores) / length(scores)

        variance =
          Enum.reduce(scores, 0.0, fn score, acc ->
            acc + :math.pow(score - mean, 2)
          end) / length(scores)

        # Convert variance to robustness score (0-1, higher is better)
        # Use exponential decay to map variance to robustness
        robustness = :math.exp(-variance)
        Float.round(robustness, 4)
    end
  end

  @doc """
  Normalizes objectives to [0, 1] for fair comparison.

  Uses min-max normalization based on population statistics. Minimization
  objectives (latency, cost) are inverted so that higher is always better.

  ## Arguments

  - `objectives` - Raw objective values
  - `population_stats` - Population min/max statistics for normalization
  - `opts` - Options:
    - `:objective_types` - Map specifying :maximize or :minimize for each objective

  ## Returns

  Map of normalized objective values in [0, 1]
  """
  @spec normalize_objectives(objectives(), map(), keyword()) :: objectives()
  def normalize_objectives(objectives, population_stats, opts \\ [])

  def normalize_objectives(objectives, population_stats, opts)
      when is_map(objectives) and is_map(population_stats) do
    objective_types = Keyword.get(opts, :objective_types, default_objective_types())

    objectives
    |> Enum.map(fn {obj, value} ->
      min_val = Map.get(population_stats, :"#{obj}_min", 0.0)
      max_val = Map.get(population_stats, :"#{obj}_max", 1.0)

      # Normalize to [0, 1]
      normalized =
        if max_val > min_val do
          (value - min_val) / (max_val - min_val)
        else
          # All values are the same
          0.5
        end

      # Invert if minimization objective (so higher is always better)
      normalized =
        case Map.get(objective_types, obj, :maximize) do
          :minimize -> 1.0 - normalized
          :maximize -> normalized
        end

      {obj, Float.round(normalized, 4)}
    end)
    |> Map.new()
  end

  def normalize_objectives(_objectives, _population_stats, _opts) do
    %{}
  end

  @doc """
  Calculates population statistics for normalization.

  Computes min and max values for each objective across all candidates
  in the population.

  ## Arguments

  - `candidates` - List of candidates with objective values

  ## Returns

  Map with min/max statistics, e.g.:
  `%{accuracy_min: 0.7, accuracy_max: 0.95, latency_min: 0.5, latency_max: 3.0, ...}`
  """
  @spec calculate_population_stats(list(Candidate.t())) :: map()
  def calculate_population_stats([]), do: %{}

  def calculate_population_stats(candidates) when is_list(candidates) do
    # Extract all objective maps
    all_objectives =
      candidates
      |> Enum.map(& &1.objectives)
      |> Enum.reject(&is_nil/1)

    case all_objectives do
      [] ->
        %{}

      objectives_list ->
        # Get all objective names
        objective_names =
          objectives_list
          |> Enum.flat_map(&Map.keys/1)
          |> Enum.uniq()

        # Calculate min/max for each objective
        Enum.flat_map(objective_names, fn obj ->
          values =
            objectives_list
            |> Enum.map(&Map.get(&1, obj, 0.0))
            |> Enum.reject(&is_nil/1)

          case values do
            [] ->
              []

            values ->
              [
                {:"#{obj}_min", Enum.min(values)},
                {:"#{obj}_max", Enum.max(values)}
              ]
          end
        end)
        |> Map.new()
    end
  end

  @doc """
  Computes weighted aggregate fitness from normalized objectives.

  For backward compatibility with single-objective optimization code.
  The aggregate fitness is a weighted sum of normalized objectives.

  ## Arguments

  - `normalized_objectives` - Map of normalized objective values
  - `opts` - Options:
    - `:weights` - Map of weights for each objective (default: balanced)

  ## Returns

  Float in [0.0, 1.0] representing aggregate fitness
  """
  @spec aggregate_fitness(objectives(), keyword()) :: float()
  def aggregate_fitness(normalized_objectives, opts \\ [])

  def aggregate_fitness(normalized_objectives, opts) when is_map(normalized_objectives) do
    weights = Keyword.get(opts, :weights, @default_weights)

    fitness =
      normalized_objectives
      |> Enum.reduce(0.0, fn {obj, value}, acc ->
        weight = Map.get(weights, obj, 0.0)
        acc + value * weight
      end)

    Float.round(fitness, 4)
  end

  def aggregate_fitness(_normalized_objectives, _opts), do: 0.0

  @doc """
  Returns default objective types (maximize or minimize).
  """
  @spec default_objective_types() :: %{objective_name() => objective_type()}
  def default_objective_types do
    %{
      accuracy: :maximize,
      latency: :minimize,
      cost: :minimize,
      robustness: :maximize
    }
  end

  @doc """
  Returns the list of standard objectives.
  """
  @spec standard_objectives() :: list(objective_name())
  def standard_objectives, do: @standard_objectives

  @doc """
  Returns default objective weights for aggregate fitness.
  """
  @spec default_weights() :: %{objective_name() => float()}
  def default_weights, do: @default_weights
end
