defmodule Jido.AI.GEPA.Optimizer do
  @moduledoc """
  Main optimization loop for GEPA (Genetic-Pareto Prompt Evolution).

  The Optimizer orchestrates the evolutionary process, combining all GEPA
  components (Evaluator, Reflector, Selection) to iteratively improve prompts.

  ## Usage

      # Define tasks to optimize against
      tasks = [
        Task.new!(%{input: "What is 2+2?", expected: "4"}),
        Task.new!(%{input: "What is 3*3?", expected: "9"})
      ]

      # Define a runner function for LLM calls
      runner = fn prompt, input, opts ->
        # Call your LLM here
        {:ok, %{output: "...", tokens: 100}}
      end

      # Run optimization
      {:ok, result} = Optimizer.optimize(
        "Answer the math question: {{input}}",
        tasks,
        runner: runner,
        generations: 5,
        population_size: 4
      )

      # Get the best variants
      result.best_variants  # => [%PromptVariant{...}, ...]
      result.best_accuracy  # => 0.95

  ## Options

  - `:runner` (required) - Function for LLM calls: `(prompt, input, opts) -> {:ok, %{output, tokens}}`
  - `:generations` - Number of evolution cycles (default: 10)
  - `:population_size` - Target variants per generation (default: 8)
  - `:mutation_count` - Mutations generated per survivor (default: 3)
  - `:objectives` - Selection objectives (default: accuracy↑, cost↓)
  - `:crossover_rate` - Probability of crossover vs mutation (default: 0.2)
  - `:runner_opts` - Options passed to runner function

  ## Telemetry Events

  The optimizer emits telemetry events for monitoring:

  - `[:jido, :ai, :gepa, :generation]` - After each generation
  - `[:jido, :ai, :gepa, :evaluation]` - After each variant evaluation
  - `[:jido, :ai, :gepa, :mutation]` - After generating mutations
  - `[:jido, :ai, :gepa, :complete]` - When optimization finishes
  """

  alias Jido.AI.GEPA.{Evaluator, Helpers, Optimizer, PromptVariant, Reflector, Selection}

  @type result :: %{
          best_variants: [PromptVariant.t()],
          best_accuracy: float(),
          final_population: [PromptVariant.t()],
          generations_run: non_neg_integer(),
          total_evaluations: non_neg_integer()
        }

  @default_generations 10
  @default_population_size 8
  @default_mutation_count 3
  @default_crossover_rate 0.2

  # Maximum bounds to prevent resource exhaustion
  @max_generations 1000
  @max_population_size 100
  @max_mutation_count 20

  # ============================================================================
  # Public API
  # ============================================================================

  @doc """
  Runs the GEPA optimization loop to evolve a prompt template.

  ## Parameters

  - `seed_template` - Initial prompt template (string or map)
  - `tasks` - List of Task structs to evaluate against
  - `opts` - Configuration options (see module docs)

  ## Returns

  `{:ok, result}` with optimization results, or `{:error, reason}`.

  ## Example

      {:ok, result} = Optimizer.optimize(
        "Answer: {{input}}",
        tasks,
        runner: runner,
        generations: 10
      )

      IO.inspect(result.best_accuracy)
      IO.inspect(hd(result.best_variants).template)
  """
  @spec optimize(String.t() | map(), [Jido.AI.GEPA.Task.t()], keyword()) ::
          {:ok, result()} | {:error, atom()}
  def optimize(seed_template, tasks, opts) when is_list(tasks) do
    case validate_opts(opts) do
      :ok ->
        do_optimize(seed_template, tasks, opts)

      {:error, _} = error ->
        error
    end
  end

  def optimize(_, _, _), do: {:error, :invalid_args}

  @doc """
  Executes a single generation of the optimization loop.

  ## Parameters

  - `variants` - Current population of PromptVariants
  - `tasks` - List of Task structs
  - `generation` - Current generation number (0-indexed)
  - `opts` - Configuration options

  ## Returns

  `{:ok, new_variants}` with the next generation's population.
  """
  @spec run_generation([PromptVariant.t()], [Jido.AI.GEPA.Task.t()], non_neg_integer(), keyword()) ::
          {:ok, [PromptVariant.t()]} | {:error, atom()}
  def run_generation(variants, tasks, generation, opts) when is_list(variants) do
    runner = Keyword.fetch!(opts, :runner)
    population_size = Keyword.get(opts, :population_size, @default_population_size)
    mutation_count = Keyword.get(opts, :mutation_count, @default_mutation_count)
    crossover_rate = Keyword.get(opts, :crossover_rate, @default_crossover_rate)
    objectives = Keyword.get(opts, :objectives, Selection.default_objectives())
    runner_opts = Keyword.get(opts, :runner_opts, [])

    # Step 1: Evaluate unevaluated variants
    evaluated_variants = evaluate_population(variants, tasks, runner, runner_opts, generation)

    # Step 2: Select survivors
    survivor_count = max(2, div(population_size, 2))
    survivors = Selection.select_survivors(evaluated_variants, survivor_count, objectives: objectives)

    # Emit generation telemetry
    emit_generation_telemetry(evaluated_variants, generation, objectives)

    # Step 3: Generate next generation
    new_variants = generate_offspring(survivors, mutation_count, crossover_rate, runner, runner_opts)

    # Combine survivors with new variants, trim to population size
    next_population =
      (survivors ++ new_variants)
      |> Enum.uniq_by(& &1.id)
      |> Enum.take(population_size)

    {:ok, next_population}
  end

  def run_generation(_, _, _, _), do: {:error, :invalid_args}

  @doc """
  Extracts the best variants from a population based on objectives.

  Returns the Pareto front of the population.
  """
  @spec best_variants([PromptVariant.t()], keyword()) :: [PromptVariant.t()]
  def best_variants(variants, opts \\ []) do
    objectives = Keyword.get(opts, :objectives, Selection.default_objectives())
    Selection.pareto_front(variants, objectives)
  end

  # ============================================================================
  # Private Implementation
  # ============================================================================

  defp validate_opts(opts) do
    with :ok <- Helpers.validate_runner_opts(opts) do
      cond do
        Keyword.get(opts, :generations, @default_generations) > @max_generations ->
          {:error, :generations_exceeds_max}

        Keyword.get(opts, :population_size, @default_population_size) > @max_population_size ->
          {:error, :population_size_exceeds_max}

        Keyword.get(opts, :mutation_count, @default_mutation_count) > @max_mutation_count ->
          {:error, :mutation_count_exceeds_max}

        true ->
          :ok
      end
    end
  end

  defp do_optimize(seed_template, tasks, opts) do
    generations = Keyword.get(opts, :generations, @default_generations)
    population_size = Keyword.get(opts, :population_size, @default_population_size)
    objectives = Keyword.get(opts, :objectives, Selection.default_objectives())

    # Create seed variant
    seed = PromptVariant.new!(%{template: seed_template, generation: 0})

    # Initialize population with seed and initial mutations
    initial_population = initialize_population(seed, population_size, opts)

    # Run evolution loop
    {final_population, total_evals} =
      Enum.reduce(0..(generations - 1), {initial_population, 0}, fn gen, {pop, evals} ->
        case run_generation(pop, tasks, gen, opts) do
          {:ok, new_pop} ->
            new_evals = count_new_evaluations(pop, new_pop)
            {new_pop, evals + new_evals}

          {:error, _} ->
            {pop, evals}
        end
      end)

    # Get best variants
    best = best_variants(final_population, objectives: objectives)
    best_acc = best |> Enum.map(& &1.accuracy) |> Enum.max(fn -> 0.0 end)

    # Emit completion telemetry
    emit_complete_telemetry(generations, total_evals, best_acc, best)

    {:ok,
     %{
       best_variants: best,
       best_accuracy: best_acc,
       final_population: final_population,
       generations_run: generations,
       total_evaluations: total_evals
     }}
  end

  defp initialize_population(seed, population_size, opts) do
    runner = Keyword.fetch!(opts, :runner)
    runner_opts = Keyword.get(opts, :runner_opts, [])
    mutation_count = min(population_size - 1, Keyword.get(opts, :mutation_count, @default_mutation_count))

    if mutation_count > 0 do
      # Generate initial mutations from seed
      mutation_opts = [runner: runner, mutation_count: mutation_count, runner_opts: runner_opts]
      case Reflector.propose_mutations(seed, "Initial population generation", mutation_opts) do
        {:ok, templates} ->
          children = Enum.map(templates, &PromptVariant.create_child(seed, &1))
          [seed | children]

        {:error, _} ->
          [seed]
      end
    else
      [seed]
    end
  end

  defp evaluate_population(variants, tasks, runner, runner_opts, generation) do
    Enum.map(variants, fn variant ->
      if PromptVariant.evaluated?(variant) do
        variant
      else
        evaluate_single_variant(variant, tasks, runner, runner_opts, generation)
      end
    end)
  end

  defp evaluate_single_variant(variant, tasks, runner, runner_opts, generation) do
    case Evaluator.evaluate_variant(variant, tasks, runner: runner, runner_opts: runner_opts) do
      {:ok, result} ->
        updated = update_variant_metrics(variant, result, generation)
        updated

      {:error, _} ->
        PromptVariant.update_metrics(variant, %{accuracy: 0.0, token_cost: 0})
    end
  end

  defp update_variant_metrics(variant, result, generation) do
    updated = PromptVariant.update_metrics(variant, %{
      accuracy: result.accuracy,
      token_cost: result.token_cost,
      latency_ms: result.latency_ms
    })

    emit_evaluation_telemetry(updated, generation)
    updated
  end

  defp generate_offspring(survivors, mutation_count, crossover_rate, runner, runner_opts) do
    # Determine how many to generate via crossover vs mutation
    total_to_generate = length(survivors) * mutation_count
    crossover_count = round(total_to_generate * crossover_rate)
    mutation_pop_count = total_to_generate - crossover_count

    # Generate mutations
    mutations =
      survivors
      |> Enum.flat_map(fn survivor ->
        per_survivor = div(mutation_pop_count, max(1, length(survivors)))

        case Reflector.propose_mutations(survivor, "Generate improved variants",
               runner: runner,
               mutation_count: per_survivor,
               runner_opts: runner_opts
             ) do
          {:ok, templates} ->
            children = Enum.map(templates, &PromptVariant.create_child(survivor, &1))
            emit_mutation_telemetry(survivor, length(children))
            children

          {:error, _} ->
            []
        end
      end)

    # Generate crossovers if we have enough survivors
    crossovers =
      if crossover_count > 0 and length(survivors) >= 2 do
        generate_crossovers(survivors, crossover_count, runner, runner_opts)
      else
        []
      end

    mutations ++ crossovers
  end

  defp generate_crossovers(survivors, count, runner, runner_opts) do
    # Pair up survivors randomly for crossover
    pairs =
      survivors
      |> Enum.shuffle()
      |> Enum.chunk_every(2, 2, :discard)
      |> Enum.take(div(count, 2) + 1)

    Enum.flat_map(pairs, fn [parent1, parent2] ->
      case Reflector.crossover(parent1, parent2, runner: runner, children_count: 2, runner_opts: runner_opts) do
        {:ok, children} -> children
        {:error, _} -> []
      end
    end)
    |> Enum.take(count)
  end

  defp count_new_evaluations(old_pop, new_pop) do
    old_evaluated = Enum.count(old_pop, &PromptVariant.evaluated?/1)
    new_evaluated = Enum.count(new_pop, &PromptVariant.evaluated?/1)
    max(0, new_evaluated - old_evaluated + length(new_pop) - length(old_pop))
  end

  # ============================================================================
  # Telemetry
  # ============================================================================

  defp emit_generation_telemetry(variants, generation, objectives) do
    evaluated = Enum.filter(variants, &PromptVariant.evaluated?/1)

    if Enum.empty?(evaluated) do
      :ok
    else
      accuracies = Enum.map(evaluated, & &1.accuracy)
      best_acc = Enum.max(accuracies)
      avg_acc = Enum.sum(accuracies) / length(accuracies)
      total_cost = Enum.sum(Enum.map(evaluated, & &1.token_cost))

      front = Selection.pareto_front(evaluated, objectives)

      :telemetry.execute(
        [:jido, :ai, :gepa, :generation],
        %{
          best_accuracy: best_acc,
          avg_accuracy: avg_acc,
          token_cost: total_cost,
          pareto_front_size: length(front)
        },
        %{
          generation: generation,
          population_size: length(variants)
        }
      )
    end
  end

  defp emit_evaluation_telemetry(variant, generation) do
    :telemetry.execute(
      [:jido, :ai, :gepa, :evaluation],
      %{
        accuracy: variant.accuracy || 0.0,
        token_cost: variant.token_cost || 0,
        latency_ms: variant.latency_ms || 0
      },
      %{
        variant_id: variant.id,
        generation: generation
      }
    )
  end

  defp emit_mutation_telemetry(parent, mutation_count) do
    :telemetry.execute(
      [:jido, :ai, :gepa, :mutation],
      %{mutation_count: mutation_count},
      %{parent_id: parent.id, generation: parent.generation}
    )
  end

  defp emit_complete_telemetry(generations, total_evals, best_acc, best_variants) do
    best_id = if Enum.empty?(best_variants), do: nil, else: hd(best_variants).id

    :telemetry.execute(
      [:jido, :ai, :gepa, :complete],
      %{
        total_generations: generations,
        total_evaluations: total_evals,
        best_accuracy: best_acc
      },
      %{
        best_variant_id: best_id,
        pareto_front_size: length(best_variants)
      }
    )
  end
end
