defmodule Examples.GEPAOptimizationExample do
  @moduledoc """
  Example demonstrating GEPA (Genetic-Pareto Prompt Optimization) usage.

  This example shows how to optimize prompts across multiple competing objectives using
  the GEPA runner and extract different types of solutions from the Pareto frontier.

  ## Objectives

  GEPA can optimize across multiple objectives simultaneously:
  - **Accuracy**: How well the prompt performs on the task
  - **Latency**: How fast the prompt executes
  - **Cost**: How expensive the prompt is to run
  - **Robustness**: How consistently the prompt performs

  ## Basic Usage

      # Simple optimization
      {:ok, results} = Examples.GEPAOptimizationExample.optimize_prompt(
        initial_prompt: "Summarize this text concisely",
        task: :summarization,
        test_inputs: ["Your test text here"],
        max_generations: 30
      )

      # Access Pareto frontier (best trade-off solutions)
      frontier = results.pareto_frontier
      IO.puts("Found #{length(frontier)} optimal solutions")

      # Select solution for your use case
      fast_solution = Examples.GEPAOptimizationExample.select_fast_solution(frontier)
      accurate_solution = Examples.GEPAOptimizationExample.select_accurate_solution(frontier)
      balanced_solution = Examples.GEPAOptimizationExample.select_balanced_solution(frontier)

  ## Advanced Usage

      # Custom objectives and task-specific evaluation
      {:ok, results} = Examples.GEPAOptimizationExample.optimize_with_config(
        initial_prompt: "Analyze sentiment in this review",
        test_inputs: ["Product review text..."],
        config: %{
          population_size: 100,
          max_generations: 50,
          objectives: [:accuracy, :cost, :latency],
          task: %{
            type: :classification,
            categories: ["positive", "negative", "neutral"]
          }
        }
      )

  ## Features

  - Multi-objective optimization (Pareto frontier via NSGA-II)
  - Task-specific evaluation strategies
  - Trade-off exploration and selection helpers
  - Agent state management via GEPA runner
  """

  require Logger

  alias Jido.AI.Runner.GEPA
  alias Jido.AI.Runner.GEPA.Population.Candidate

  @doc """
  Basic prompt optimization with sensible defaults.

  ## Parameters

  - `initial_prompt` - Starting prompt to optimize
  - `test_inputs` - List of test inputs for evaluation
  - `task` - Task type (e.g., :summarization, :classification, :qa)
  - `max_generations` - Maximum optimization generations (default: 30)
  - `model` - LLM model to use (default: "openai:gpt-3.5-turbo")

  ## Returns

  - `{:ok, results}` - Optimization results with Pareto frontier
  - `{:error, reason}` - Optimization failed

  ## Examples

      {:ok, results} = optimize_prompt(
        initial_prompt: "Answer this question briefly",
        test_inputs: ["What is the capital of France?"],
        task: :qa,
        max_generations: 20
      )

      # Results structure:
      # %{
      #   pareto_frontier: [%Candidate{}, ...],
      #   best_prompts: [%Candidate{}, ...],
      #   total_evaluations: 750,
      #   history: [...]
      # }
  """
  @spec optimize_prompt(keyword()) :: {:ok, map()} | {:error, term()}
  def optimize_prompt(opts) do
    initial_prompt = Keyword.fetch!(opts, :initial_prompt)
    test_inputs = Keyword.fetch!(opts, :test_inputs)
    task = Keyword.get(opts, :task, :generic)
    max_generations = Keyword.get(opts, :max_generations, 30)
    model = Keyword.get(opts, :model, "openai:gpt-3.5-turbo")

    Logger.info("Starting GEPA optimization for #{task} task")
    Logger.info("Initial prompt: #{initial_prompt}")

    # Create agent for GEPA runner
    agent = build_agent()

    # Configure optimization
    gepa_opts = [
      test_inputs: test_inputs,
      seed_prompts: [initial_prompt],
      model: model,
      population_size: 50,
      max_generations: max_generations,
      objectives: [:accuracy, :latency, :cost, :robustness]
    ]

    # Add task config if it's a map
    gepa_opts =
      if is_map(task) do
        Keyword.put(gepa_opts, :task, task)
      else
        Keyword.put(gepa_opts, :task, %{type: task})
      end

    # Run optimization
    Logger.info("Running optimization...")

    case GEPA.run(agent, gepa_opts) do
      {:ok, updated_agent, _directives} ->
        results = extract_results(updated_agent)

        Logger.info("Optimization completed:")
        Logger.info("  Best Prompts: #{length(results.best_prompts)}")
        Logger.info("  Pareto Frontier: #{length(results.pareto_frontier)}")

        {:ok, results}

      {:error, reason} = error ->
        Logger.error("Optimization failed: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Advanced optimization with custom configuration.

  Provides full control over population size, objectives, convergence criteria,
  and optimization strategies.

  ## Parameters

  - `initial_prompt` - Starting prompt to optimize
  - `test_inputs` - List of test inputs for evaluation
  - `config` - Full optimization configuration

  ## Configuration Options

  - `:population_size` - Number of candidates per generation (default: 50)
  - `:max_generations` - Maximum generations (default: 30)
  - `:objectives` - List of objectives to optimize (default: all 4)
  - `:task` - Task configuration for task-specific evaluation
  - `:model` - LLM model to use

  ## Examples

      {:ok, results} = optimize_with_config(
        initial_prompt: "Classify sentiment",
        test_inputs: ["I love this product!"],
        config: %{
          population_size: 100,
          max_generations: 50,
          objectives: [:accuracy, :cost],  # Only optimize these two
          task: %{
            type: :classification,
            categories: ["positive", "negative"]
          }
        }
      )
  """
  @spec optimize_with_config(keyword()) :: {:ok, map()} | {:error, term()}
  def optimize_with_config(opts) do
    initial_prompt = Keyword.fetch!(opts, :initial_prompt)
    test_inputs = Keyword.fetch!(opts, :test_inputs)
    custom_config = Keyword.fetch!(opts, :config)

    Logger.info("Starting advanced GEPA optimization")

    # Create agent
    agent = build_agent()

    # Build GEPA options from config
    gepa_opts = [
      test_inputs: test_inputs,
      seed_prompts: [initial_prompt],
      model: Map.get(custom_config, :model, "openai:gpt-3.5-turbo"),
      population_size: Map.get(custom_config, :population_size, 50),
      max_generations: Map.get(custom_config, :max_generations, 30),
      objectives: Map.get(custom_config, :objectives, [:accuracy, :latency, :cost, :robustness])
    ]

    # Add task if provided
    gepa_opts =
      if Map.has_key?(custom_config, :task) do
        Keyword.put(gepa_opts, :task, custom_config.task)
      else
        gepa_opts
      end

    # Run optimization
    case GEPA.run(agent, gepa_opts) do
      {:ok, updated_agent, _directives} ->
        results = extract_results(updated_agent)
        {:ok, results}

      {:error, reason} = error ->
        Logger.error("Optimization failed: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Select the fastest solution from Pareto frontier.

  Chooses the solution with lowest latency (best response time).
  May sacrifice some accuracy for speed.

  ## Examples

      frontier = results.pareto_frontier
      fast = select_fast_solution(frontier)
      IO.puts("Fast solution: #{fast.prompt}")
      IO.puts("Fitness: #{fast.fitness}")
  """
  @spec select_fast_solution(list(Candidate.t())) :: Candidate.t() | nil
  def select_fast_solution([]), do: nil

  def select_fast_solution(frontier) do
    # Filter candidates with objectives
    with_objectives = Enum.filter(frontier, fn c -> c.objectives != nil && c.objectives != %{} end)

    if with_objectives == [] do
      # Fallback to best fitness if no objectives
      Enum.max_by(frontier, & &1.fitness)
    else
      Enum.min_by(with_objectives, fn c -> Map.get(c.objectives, :latency, 1000) end)
    end
  end

  @doc """
  Select the most accurate solution from Pareto frontier.

  Chooses the solution with highest accuracy.
  May be slower or more expensive.

  ## Examples

      frontier = results.pareto_frontier
      accurate = select_accurate_solution(frontier)
      IO.puts("Accurate solution: #{accurate.prompt}")
      IO.puts("Fitness: #{accurate.fitness}")
  """
  @spec select_accurate_solution(list(Candidate.t())) :: Candidate.t() | nil
  def select_accurate_solution([]), do: nil

  def select_accurate_solution(frontier) do
    # Filter candidates with objectives
    with_objectives = Enum.filter(frontier, fn c -> c.objectives != nil && c.objectives != %{} end)

    if with_objectives == [] do
      # Fallback to best fitness if no objectives
      Enum.max_by(frontier, & &1.fitness)
    else
      Enum.max_by(with_objectives, fn c -> Map.get(c.objectives, :accuracy, 0) end)
    end
  end

  @doc """
  Select the most cost-efficient solution from Pareto frontier.

  Chooses the solution with lowest cost per evaluation.

  ## Examples

      frontier = results.pareto_frontier
      cheap = select_cost_efficient_solution(frontier)
      IO.puts("Cost-efficient solution: #{cheap.prompt}")
  """
  @spec select_cost_efficient_solution(list(Candidate.t())) :: Candidate.t() | nil
  def select_cost_efficient_solution([]), do: nil

  def select_cost_efficient_solution(frontier) do
    with_objectives = Enum.filter(frontier, fn c -> c.objectives != nil && c.objectives != %{} end)

    if with_objectives == [] do
      Enum.max_by(frontier, & &1.fitness)
    else
      Enum.min_by(with_objectives, fn c -> Map.get(c.objectives, :cost, 1.0) end)
    end
  end

  @doc """
  Select a balanced solution from Pareto frontier.

  Uses a weighted scoring function to find the solution with the best
  overall balance across all objectives.

  Default weights: accuracy=0.4, latency=0.2, cost=0.2, robustness=0.2

  ## Examples

      frontier = results.pareto_frontier
      balanced = select_balanced_solution(frontier)
      IO.puts("Balanced solution: #{balanced.prompt}")

      # Custom weights
      balanced = select_balanced_solution(frontier,
        weights: %{accuracy: 0.5, latency: 0.3, cost: 0.1, robustness: 0.1}
      )
  """
  @spec select_balanced_solution(list(Candidate.t()), keyword()) :: Candidate.t() | nil
  def select_balanced_solution([], _opts), do: nil

  def select_balanced_solution(frontier, opts \\ []) do
    weights =
      Keyword.get(opts, :weights, %{
        accuracy: 0.4,
        latency: 0.2,
        cost: 0.2,
        robustness: 0.2
      })

    # Filter candidates with objectives
    with_objectives = Enum.filter(frontier, fn c -> c.objectives != nil && c.objectives != %{} end)

    if with_objectives == [] do
      # Fallback to best fitness if no objectives
      Enum.max_by(frontier, & &1.fitness)
    else
      # Normalize objectives to [0, 1] for comparison
      normalized = normalize_frontier_objectives(with_objectives)

      # Calculate weighted scores
      Enum.max_by(normalized, fn {_candidate, norm_obj} ->
        weights[:accuracy] * Map.get(norm_obj, :accuracy, 0.5) +
          # Invert latency and cost (lower is better)
          weights[:latency] * (1.0 - Map.get(norm_obj, :latency, 0.5)) +
          weights[:cost] * (1.0 - Map.get(norm_obj, :cost, 0.5)) +
          weights[:robustness] * Map.get(norm_obj, :robustness, 0.5)
      end)
      |> elem(0)
    end
  end

  @doc """
  Visualize the Pareto frontier trade-offs.

  Prints a summary of solutions showing the trade-off between objectives.

  ## Examples

      visualize_frontier(results.pareto_frontier)

      # Output:
      # === Pareto Frontier (8 solutions) ===
      #
      # Solution 1: High Accuracy Focus
      #   Prompt: Summarize this text...
      #   Fitness: 0.92
      #
      # Solution 2: Fast & Cheap
      #   Prompt: Brief summary:...
      #   Fitness: 0.75
      # ...
  """
  @spec visualize_frontier(list(Candidate.t())) :: :ok
  def visualize_frontier(frontier) do
    IO.puts("\n=== Pareto Frontier (#{length(frontier)} solutions) ===\n")

    frontier
    |> Enum.with_index(1)
    |> Enum.each(fn {candidate, idx} ->
      category = categorize_solution(candidate)

      IO.puts("Solution #{idx}: #{category}")
      IO.puts("  Prompt: #{String.slice(candidate.prompt, 0..60)}...")
      IO.puts("  Fitness: #{format_score(candidate.fitness)}")

      if candidate.objectives && candidate.objectives != %{} do
        IO.puts("  Objectives:")

        if Map.has_key?(candidate.objectives, :accuracy) do
          IO.puts("    Accuracy:   #{format_score(candidate.objectives.accuracy)}")
        end

        if Map.has_key?(candidate.objectives, :latency) do
          IO.puts("    Latency:    #{round(candidate.objectives.latency)}ms")
        end

        if Map.has_key?(candidate.objectives, :cost) do
          IO.puts("    Cost:       $#{Float.round(candidate.objectives.cost, 4)}")
        end

        if Map.has_key?(candidate.objectives, :robustness) do
          IO.puts("    Robustness: #{Float.round(candidate.objectives.robustness, 2)}")
        end
      end

      IO.puts("")
    end)

    :ok
  end

  # Private functions

  defp build_agent do
    %{
      id: "gepa-optimizer-#{System.unique_integer([:positive])}",
      name: "GEPA Prompt Optimizer",
      state: %{},
      pending_instructions: :queue.new(),
      actions: [],
      runner: GEPA,
      result: nil
    }
  end

  defp extract_results(agent) do
    state = agent.state

    %{
      pareto_frontier: Map.get(state, :gepa_pareto_frontier, []),
      best_prompts: Map.get(state, :gepa_best_prompts, []),
      total_evaluations: get_total_evaluations(state),
      history: Map.get(state, :gepa_history, [])
    }
  end

  defp get_total_evaluations(state) do
    case Map.get(state, :gepa_last_run) do
      nil -> 0
      last_run -> Map.get(last_run, :total_evaluations, 0)
    end
  end

  defp normalize_frontier_objectives(frontier) do
    # Find min/max for each objective
    accuracy_range = get_objective_range(frontier, :accuracy)
    latency_range = get_objective_range(frontier, :latency)
    cost_range = get_objective_range(frontier, :cost)
    robustness_range = get_objective_range(frontier, :robustness)

    Enum.map(frontier, fn candidate ->
      normalized = %{
        accuracy: normalize_value(Map.get(candidate.objectives, :accuracy), accuracy_range),
        latency: normalize_value(Map.get(candidate.objectives, :latency), latency_range),
        cost: normalize_value(Map.get(candidate.objectives, :cost), cost_range),
        robustness: normalize_value(Map.get(candidate.objectives, :robustness), robustness_range)
      }

      {candidate, normalized}
    end)
  end

  defp get_objective_range(frontier, objective) do
    values =
      frontier
      |> Enum.map(fn c -> Map.get(c.objectives, objective) end)
      |> Enum.filter(&(&1 != nil))

    if values == [] do
      {0.0, 1.0}
    else
      {Enum.min(values), Enum.max(values)}
    end
  end

  defp normalize_value(nil, _range), do: 0.5
  defp normalize_value(value, {min, max}) when max > min, do: (value - min) / (max - min)
  defp normalize_value(_value, _range), do: 0.5

  defp categorize_solution(candidate) do
    if candidate.objectives == nil || candidate.objectives == %{} do
      "Standard"
    else
      obj = candidate.objectives

      cond do
        Map.get(obj, :accuracy, 0) > 0.85 and Map.get(obj, :cost, 0) > 0.007 ->
          "High Accuracy Focus"

        Map.get(obj, :latency, 1000) < 200 and Map.get(obj, :cost, 1.0) < 0.004 ->
          "Fast & Cheap"

        Map.get(obj, :accuracy, 0) > 0.80 and Map.get(obj, :robustness, 0) > 0.85 ->
          "Accurate & Robust"

        Map.get(obj, :cost, 1.0) < 0.003 ->
          "Budget Optimized"

        true ->
          "Balanced"
      end
    end
  end

  defp format_score(nil), do: "N/A"
  defp format_score(score) when is_float(score), do: Float.round(score, 2)
  defp format_score(score), do: score
end
