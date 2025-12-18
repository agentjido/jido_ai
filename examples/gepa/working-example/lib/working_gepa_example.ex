defmodule Examples.WorkingGEPAExample do
  @moduledoc """
  **WORKING** example of GEPA (Genetic-Pareto Prompt Optimization) with real LLM calls.

  ## ⚠️  CRITICAL COST WARNING ⚠️

  **THIS EXAMPLE MAKES REAL API CALLS TO LLM PROVIDERS AND WILL INCUR ACTUAL COSTS!**

  **COSTS CAN BE UNPREDICTABLE AND POTENTIALLY EXPENSIVE:**
  - Each generation evaluates MULTIPLE prompts (default: 20 candidates/generation)
  - Each evaluation = 1 API call with input + output tokens
  - Default 10 generations = 200+ API calls minimum
  - Actual costs depend on: model pricing, prompt length, response length
  - ESTIMATED: $0.50 - $5.00+ per optimization run (highly variable)

  **BEFORE RUNNING:**
  1. Set strict budget limits in your provider account
  2. Start with SMALL population sizes (5-10) and FEW generations (3-5)
  3. Use CHEAPER models first (gpt-3.5-turbo, claude-instant)
  4. Monitor your API usage dashboard actively
  5. Understand you are responsible for ALL incurred costs

  **COST EXAMPLE:**
  ```
  population_size: 10, generations: 5, model: gpt-4
  = 50 evaluations minimum
  = ~$2.50 (at $0.05/eval, varies by length)
  ```

  ## Model Format

  Models MUST be specified in the format: **`"provider:model_name"`**

  Examples:
  - `"openai:gpt-4"`
  - `"openai:gpt-3.5-turbo"`
  - `"anthropic:claude-3-haiku-20240307"`
  - `"anthropic:claude-3-sonnet-20240229"`
  - `"groq:llama-3.1-8b-instant"`

  See ReqLLM documentation for full list of supported providers and models.

  ## Prerequisites

  API keys must be loaded via Jido.AI.Keyring before running:

  ```elixir
  # Set API key (required before optimization)
  Jido.AI.Keyring.set_env_value(:openai_api_key, "sk-...")

  # Or use environment variable:
  # export OPENAI_API_KEY="sk-..."
  ```

  ## Basic Usage

  ```elixir
  # SMALL test run (recommended first)
  {:ok, results} = Examples.WorkingGEPAExample.optimize_prompt(
    initial_prompt: "Summarize: {{text}}",
    model: "openai:gpt-3.5-turbo",  # Cheaper model
    test_inputs: ["Short text here"],
    population_size: 5,   # SMALL
    max_generations: 3    # FEW
  )

  # View results
  IO.puts("Best prompts found:")
  Enum.each(results.pareto_frontier, fn candidate ->
    IO.puts("\nPrompt: #{candidate.prompt}")
    IO.puts("Fitness: #{candidate.fitness}")
  end)
  ```

  ## Features

  - Real multi-objective optimization with LLM evaluation using GEPA runner
  - Automatic agent state management
  - Task-specific evaluation support
  - Pareto frontier extraction via NSGA-II
  - Progress monitoring and convergence detection
  """

  require Logger

  alias Jido.AI.Keyring
  alias Jido.AI.Runner.GEPA

  @doc """
  Optimize a prompt template using GEPA with real LLM evaluation.

  ## ⚠️  WARNING: MAKES REAL API CALLS - SEE MODULE DOC FOR COST WARNINGS ⚠️

  ## Parameters

  - `:initial_prompt` - Starting prompt template (use {{variable}} for placeholders)
  - `:model` - Model in "provider:model" format (e.g., "openai:gpt-3.5-turbo")
  - `:test_inputs` - List of test inputs for evaluation
  - `:population_size` - Candidates per generation (default: 10, recommend 5-10)
  - `:max_generations` - Maximum generations (default: 5, recommend 3-5 for testing)
  - `:objectives` - List of objectives to optimize (default: [:accuracy, :latency, :cost])
  - `:task` - Task configuration for task-specific evaluation (optional)

  ## Returns

  - `{:ok, results}` with:
    - `:pareto_frontier` - Best trade-off solutions
    - `:best_prompts` - Top prompts by fitness
    - `:total_evaluations` - Number of LLM calls made
    - `:history` - Optimization history

  ## Examples

      # Minimal test (recommended first run)
      {:ok, results} = optimize_prompt(
        initial_prompt: "Translate to French: {{text}}",
        model: "openai:gpt-3.5-turbo",
        test_inputs: ["Hello"],
        population_size: 5,
        max_generations: 2
      )

      # Code generation task
      {:ok, results} = optimize_prompt(
        initial_prompt: "Write a function to {{problem}}",
        model: "openai:gpt-4",
        test_inputs: [
          %{problem: "calculate fibonacci"}
        ],
        population_size: 10,
        max_generations: 5,
        task: %{
          type: :code_generation,
          language: :elixir,
          test_cases: [%{input: 5, expected: 5}]
        }
      )
  """
  @spec optimize_prompt(keyword()) :: {:ok, map()} | {:error, term()}
  def optimize_prompt(opts) do
    # Extract and validate parameters
    with {:ok, config} <- build_config(opts),
         :ok <- check_api_key(config.model),
         :ok <- confirm_cost_awareness(config) do
      Logger.warning("""

      ========================================
      STARTING GEPA OPTIMIZATION
      ========================================
      Model: #{config.model}
      Population: #{config.population_size}
      Max Generations: #{config.max_generations}
      Test Inputs: #{length(config.test_inputs)}

      ESTIMATED MAX EVALUATIONS: #{estimate_evaluations(config)}
      ESTIMATED COST: $#{estimate_cost(config)}
      (Actual cost may vary based on response lengths)
      ========================================
      """)

      run_optimization(config)
    end
  end

  # Private implementation

  defp build_config(opts) do
    config = %{
      initial_prompt: Keyword.fetch!(opts, :initial_prompt),
      model: Keyword.fetch!(opts, :model),
      test_inputs: Keyword.fetch!(opts, :test_inputs),
      population_size: Keyword.get(opts, :population_size, 10),
      max_generations: Keyword.get(opts, :max_generations, 5),
      objectives: Keyword.get(opts, :objectives, [:accuracy, :latency, :cost]),
      task: Keyword.get(opts, :task)
    }

    # Validate
    cond do
      not String.contains?(config.model, ":") ->
        {:error, "Model must be in format 'provider:model', got: #{config.model}"}

      config.population_size < 2 ->
        {:error, "Population size must be at least 2"}

      config.max_generations < 1 ->
        {:error, "Must run at least 1 generation"}

      config.test_inputs == [] ->
        {:error, "test_inputs must be non-empty"}

      true ->
        {:ok, config}
    end
  end

  defp check_api_key(model_string) do
    [provider_str | _] = String.split(model_string, ":")
    provider = String.to_atom(provider_str)
    key_name = :"#{provider}_api_key"

    case Keyring.get_env_value(key_name, nil) do
      nil ->
        {:error, """
        API key not found for provider: #{provider}

        Please set the API key first:
        Jido.AI.Keyring.set_env_value(:#{key_name}, "your-key-here")

        Or set environment variable: #{String.upcase("#{provider}_api_key")}
        """}

      _key ->
        :ok
    end
  end

  defp confirm_cost_awareness(config) do
    # In a real interactive environment, you might prompt the user
    # For this example, we just log a final warning
    Logger.warning("""

    ⚠️  FINAL COST WARNING ⚠️
    You are about to make real API calls that will cost real money.
    Max evaluations: #{estimate_evaluations(config)}
    Estimated cost: $#{estimate_cost(config)}

    Proceeding in 2 seconds... (Ctrl+C to abort)
    """)

    Process.sleep(2000)
    :ok
  end

  defp estimate_evaluations(config) do
    config.population_size * config.max_generations
  end

  defp estimate_cost(config) do
    # Rough estimation: varies by model
    evaluations = estimate_evaluations(config)
    # Multiply by number of test inputs
    total_calls = evaluations * length(config.test_inputs)

    cost_per_eval = cond do
      String.contains?(config.model, "gpt-4") -> 0.10
      String.contains?(config.model, "claude-3-opus") -> 0.15
      String.contains?(config.model, "claude-3-sonnet") -> 0.08
      String.contains?(config.model, "gpt-3.5") -> 0.03
      true -> 0.05  # Conservative estimate
    end

    Float.round(total_calls * cost_per_eval, 2)
  end

  defp run_optimization(config) do
    # Create agent for GEPA runner
    agent = build_agent()

    Logger.info("Running GEPA optimization via runner...")

    # Build options for GEPA runner
    gepa_opts = [
      test_inputs: config.test_inputs,
      seed_prompts: [config.initial_prompt],
      model: config.model,
      population_size: config.population_size,
      max_generations: config.max_generations,
      objectives: config.objectives
    ]

    # Add task config if provided
    gepa_opts =
      if config.task do
        Keyword.put(gepa_opts, :task, config.task)
      else
        gepa_opts
      end

    # Run optimization via GEPA runner
    case GEPA.run(agent, gepa_opts) do
      {:ok, updated_agent, directives} ->
        # Extract results from agent state
        results = extract_results(updated_agent, directives)

        Logger.info("""

        ========================================
        OPTIMIZATION COMPLETE
        ========================================
        Best Prompts: #{length(results.best_prompts)}
        Pareto Frontier: #{length(results.pareto_frontier)}
        Directives: #{inspect(directives)}
        ========================================
        """)

        {:ok, results}

      {:error, reason} = error ->
        Logger.error("GEPA optimization failed: #{inspect(reason)}")
        error
    end
  end

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

  defp extract_results(agent, _directives) do
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
end
