defmodule Jido.AI.Runner.GEPA do
  @moduledoc """
  GEPA (Genetic-Pareto Prompt Optimization) runner for evolutionary prompt improvement.

  This runner implements evolutionary prompt optimization using multi-objective genetic algorithms
  guided by LLM reflection. GEPA treats prompt optimization as an evolutionary search problem where
  prompts evolve through targeted mutations based on LLM feedback about execution failures.

  ## Key Features

  - **Multi-Objective Optimization**: Balances accuracy, cost, latency, and robustness simultaneously
  - **LLM-Guided Evolution**: Uses language feedback for targeted prompt improvements
  - **Sample Efficient**: Achieves 10-19% performance gains with 35× fewer evaluations than RL methods
  - **Pareto Frontier**: Maintains diverse high-performing solutions representing different trade-offs
  - **Evolutionary Search**: Population-based optimization with crossover and mutation operators

  ## Configuration

  The runner accepts the following configuration options:

  ### Population Parameters
  - `:population_size` - Number of prompt candidates per generation (default: 10)
  - `:max_generations` - Maximum evolution cycles (default: 20)
  - `:evaluation_budget` - Hard limit on total evaluations (default: 200)
  - `:seed_prompts` - Initial prompt templates to seed population (default: [])

  ### Evaluation Parameters
  - `:test_inputs` - List of test inputs for evaluation (required)
  - `:expected_outputs` - Optional expected outputs for accuracy measurement (default: nil)
  - `:model` - LLM model for evaluation (default: nil, uses agent's model)

  ### Evolution Parameters
  - `:mutation_rate` - Probability of mutation (0.0-1.0, default: 0.3)
  - `:crossover_rate` - Probability of crossover (0.0-1.0, default: 0.7)
  - `:parallelism` - Maximum concurrent evaluations (default: 5)

  ### Multi-Objective Parameters
  - `:objectives` - List of objectives to optimize (default: [:accuracy, :cost, :latency, :robustness])
  - `:objective_weights` - Map of objective weights (default: %{}, all equal)

  ### Advanced Options
  - `:enable_reflection` - Use LLM reflection for mutations (default: true)
  - `:enable_crossover` - Use crossover operator (default: true)
  - `:convergence_threshold` - Minimum improvement to continue (default: 0.001)

  ## Usage

  ### Basic Usage

  Create an agent with the GEPA runner:

      defmodule MyAgent do
        use Jido.Agent,
          name: "optimizer_agent",
          runner: Jido.AI.Runner.GEPA,
          actions: [MyAction]
      end

      # Run optimization
      {:ok, agent} = MyAgent.new()
      {:ok, optimized_agent, directives} = Jido.AI.Runner.GEPA.run(agent,
        test_inputs: ["input1", "input2", "input3"],
        population_size: 10,
        max_generations: 20
      )

      # Access results
      best_prompts = optimized_agent.state.gepa_best_prompts
      pareto_frontier = optimized_agent.state.gepa_pareto_frontier

  ### Custom Configuration

  Configure with specific optimization parameters:

      opts = [
        population_size: 15,
        max_generations: 30,
        evaluation_budget: 500,
        seed_prompts: ["Solve step by step", "Think carefully"],
        test_inputs: test_cases,
        mutation_rate: 0.4,
        objectives: [:accuracy, :cost],
        parallelism: 10
      ]

      {:ok, agent, directives} = GEPA.run(agent, opts)

  ### Configuration via Agent State

  Store runner configuration in agent state for persistent settings:

      agent = MyAgent.new()
      agent = Jido.Agent.set(agent, :gepa_config, %{
        population_size: 15,
        max_generations: 50,
        seed_prompts: initial_prompts,
        test_inputs: test_data
      })

      # Runner will use stored configuration
      {:ok, updated_agent, directives} = GEPA.run(agent)

  ## Architecture

  The runner follows this execution flow:

  1. **Initialize Population**: Creates initial prompt candidates from seeds or generates variations
  2. **Evaluate**: Executes prompts on test inputs and measures objectives
  3. **Reflect**: Uses LLM to analyze failures and propose improvements
  4. **Mutate & Crossover**: Generates new prompt variations based on reflection
  5. **Select**: Maintains Pareto-optimal solutions for next generation
  6. **Converge**: Repeats until budget exhausted or convergence detected
  7. **Return Results**: Returns agent with optimized prompts and Pareto frontier

  ## Performance Characteristics

  - **Latency**: Depends on population size and generations (minutes to hours)
  - **API Cost**: population_size × max_generations × test_inputs × cost_per_call
  - **Accuracy**: 10-19% improvement over baselines (task-dependent)
  - **Sample Efficiency**: 35× fewer evaluations than RL methods

  ## Research Background

  GEPA achieves significant performance improvements over baselines while using
  substantially fewer evaluations than reinforcement learning methods by leveraging
  language feedback for targeted prompt evolution.

  **Reference**: Agrawal et al., "GEPA: Reflective Prompt Evolution Can Outperform
  Reinforcement Learning" (arXiv:2507.19457)

  ## Implementation Status

  **Phases 1-5 Complete**: Real Optimization Integration
  - ✅ Module structure with @behaviour Jido.Runner
  - ✅ Configuration schema and validation
  - ✅ Real GEPA.Optimizer GenServer integration
  - ✅ Config mapping between runner and optimizer
  - ✅ Result transformation and Pareto frontier extraction
  - ✅ Comprehensive documentation

  **Current Limitations**:
  - Evaluation uses mock fitness (optimizer's mock evaluation)
  - Objectives are derived from fitness (not measured independently)
  - Pareto frontier is simple top-N selection (true Pareto sorting in Phase 7)
  - Reflection and mutation use placeholders in optimizer

  **Future Phases** (6-9):
  - Real evaluation function with LLM calls
  - True Pareto dominance sorting
  - Integration tests with real optimization
  - Enhanced documentation and examples
  """

  use TypedStruct

  @behaviour Jido.Runner

  require Logger

  alias Jido.AI.Runner.GEPA.Optimizer

  # Type definitions

  typedstruct module: Config do
    @moduledoc """
    Configuration schema for the GEPA runner.

    This struct defines all configurable parameters for GEPA optimization behavior.
    """

    # Population parameters
    field(:population_size, pos_integer(), default: 10)
    field(:max_generations, pos_integer(), default: 20)
    field(:evaluation_budget, pos_integer(), default: 200)
    field(:seed_prompts, list(String.t()), default: [])

    # Evaluation parameters
    field(:test_inputs, list(term()), default: [])
    field(:expected_outputs, list(term()) | nil, default: nil)
    field(:model, String.t() | nil, default: nil)

    # Evolution parameters
    field(:mutation_rate, float(), default: 0.3)
    field(:crossover_rate, float(), default: 0.7)
    field(:parallelism, pos_integer(), default: 5)

    # Multi-objective parameters
    field(:objectives, list(atom()), default: [:accuracy, :cost, :latency, :robustness])
    field(:objective_weights, map(), default: %{})

    # Advanced options
    field(:enable_reflection, boolean(), default: true)
    field(:enable_crossover, boolean(), default: true)
    field(:convergence_threshold, float(), default: 0.001)
  end

  @type config :: Config.t()
  @type agent :: struct()
  @type opts :: keyword()
  @type directives :: list()

  # Valid objectives
  @valid_objectives [:accuracy, :cost, :latency, :robustness, :conciseness, :completeness]

  @doc """
  Executes prompt optimization using GEPA evolutionary algorithm.

  This function initializes a population of prompt candidates, evolves them through
  multiple generations using LLM-guided mutations and crossover, and returns the
  best prompts found along the Pareto frontier.

  ## Arguments

  - `agent` - The agent struct with pending instructions and configuration
  - `opts` - Optional keyword list of configuration overrides

  ## Returns

  - `{:ok, updated_agent, directives}` - Success with optimized prompts and results
  - `{:error, reason}` - Failure with error details

  ## Options

  All configuration options from `Jido.AI.Runner.GEPA.Config` can be passed as opts.
  Options override any configuration stored in agent state.

  The `:test_inputs` option is required if not present in agent state.

  ## Examples

      # Basic execution with test inputs
      {:ok, agent, directives} = Jido.AI.Runner.GEPA.run(agent,
        test_inputs: ["input1", "input2"]
      )

      # Custom population and generations
      {:ok, agent, directives} = Jido.AI.Runner.GEPA.run(agent,
        test_inputs: test_data,
        population_size: 20,
        max_generations: 30
      )

      # With seed prompts
      {:ok, agent, directives} = Jido.AI.Runner.GEPA.run(agent,
        test_inputs: test_data,
        seed_prompts: ["Step by step", "Think carefully"],
        evaluation_budget: 500
      )

  ## Agent State Updates

  The runner stores optimization results in agent state:

  - `:gepa_best_prompts` - List of best prompts from final generation
  - `:gepa_pareto_frontier` - Pareto-optimal solutions representing trade-offs
  - `:gepa_history` - Optimization history with metrics per generation
  - `:gepa_config` - Configuration used for optimization

  ## Directives

  Returns directives containing:

  - `:optimization_complete` - Signals completion with result summary
  - `:best_prompts` - Top performing prompts
  - `:pareto_frontier` - Multi-objective trade-off solutions
  """
  @impl Jido.Runner
  @spec run(agent(), opts()) :: {:ok, agent(), directives()} | {:error, term()}
  def run(agent, opts \\ []) do
    with {:ok, config} <- build_config(agent, opts),
         {:ok, agent} <- validate_agent(agent),
         :ok <- validate_test_inputs(config) do
      execute_optimization(agent, config)
    else
      {:error, reason} = error ->
        Logger.warning("GEPA runner error: #{inspect(reason)}")
        error
    end
  end

  # Private Functions

  @doc false
  @spec build_config(agent(), opts()) :: {:ok, config()} | {:error, term()}
  defp build_config(agent, opts) do
    state_config = get_state_config(agent)
    merged_opts = Keyword.merge(state_config, opts)

    config = %Config{
      population_size: Keyword.get(merged_opts, :population_size, 10),
      max_generations: Keyword.get(merged_opts, :max_generations, 20),
      evaluation_budget: Keyword.get(merged_opts, :evaluation_budget, 200),
      seed_prompts: Keyword.get(merged_opts, :seed_prompts, []),
      test_inputs: Keyword.get(merged_opts, :test_inputs, []),
      expected_outputs: Keyword.get(merged_opts, :expected_outputs),
      model: Keyword.get(merged_opts, :model),
      mutation_rate: Keyword.get(merged_opts, :mutation_rate, 0.3),
      crossover_rate: Keyword.get(merged_opts, :crossover_rate, 0.7),
      parallelism: Keyword.get(merged_opts, :parallelism, 5),
      objectives:
        Keyword.get(merged_opts, :objectives, [:accuracy, :cost, :latency, :robustness]),
      objective_weights: Keyword.get(merged_opts, :objective_weights, %{}),
      enable_reflection: Keyword.get(merged_opts, :enable_reflection, true),
      enable_crossover: Keyword.get(merged_opts, :enable_crossover, true),
      convergence_threshold: Keyword.get(merged_opts, :convergence_threshold, 0.001)
    }

    validate_config(config)
  end

  @doc false
  @spec get_state_config(agent()) :: keyword()
  defp get_state_config(agent) when is_map(agent) do
    state = Map.get(agent, :state, %{})

    case Map.get(state, :gepa_config) do
      nil -> []
      config when is_map(config) -> Map.to_list(config)
      _ -> []
    end
  end

  defp get_state_config(_agent), do: []

  @doc false
  @spec validate_config(config()) :: {:ok, config()} | {:error, term()}
  defp validate_config(config) do
    cond do
      config.population_size < 2 ->
        {:error, "population_size must be at least 2, got: #{config.population_size}"}

      config.max_generations < 1 ->
        {:error, "max_generations must be at least 1, got: #{config.max_generations}"}

      config.evaluation_budget < config.population_size ->
        {:error,
         "evaluation_budget (#{config.evaluation_budget}) must be >= population_size (#{config.population_size})"}

      config.mutation_rate < 0.0 or config.mutation_rate > 1.0 ->
        {:error, "mutation_rate must be between 0.0 and 1.0, got: #{config.mutation_rate}"}

      config.crossover_rate < 0.0 or config.crossover_rate > 1.0 ->
        {:error, "crossover_rate must be between 0.0 and 1.0, got: #{config.crossover_rate}"}

      config.parallelism < 1 ->
        {:error, "parallelism must be at least 1, got: #{config.parallelism}"}

      not Enum.all?(config.objectives, &(&1 in @valid_objectives)) ->
        invalid = Enum.reject(config.objectives, &(&1 in @valid_objectives))

        {:error, "invalid objectives: #{inspect(invalid)}. Valid: #{inspect(@valid_objectives)}"}

      true ->
        {:ok, config}
    end
  end

  @doc false
  @spec validate_agent(agent()) :: {:ok, agent()} | {:error, term()}
  defp validate_agent(agent) when is_map(agent) do
    {:ok, agent}
  end

  defp validate_agent(agent) do
    {:error, "invalid agent: expected map, got: #{inspect(agent)}"}
  end

  @doc false
  @spec validate_test_inputs(config()) :: :ok | {:error, term()}
  defp validate_test_inputs(%Config{test_inputs: []}), do: {:error, "test_inputs cannot be empty"}
  defp validate_test_inputs(%Config{test_inputs: inputs}) when is_list(inputs), do: :ok
  defp validate_test_inputs(_), do: {:error, "test_inputs must be a list"}

  @doc false
  @spec execute_optimization(agent(), config()) ::
          {:ok, agent(), directives()} | {:error, term()}
  defp execute_optimization(agent, config) do
    Logger.info(
      "Starting GEPA optimization (population: #{config.population_size}, generations: #{config.max_generations})"
    )

    # Start optimizer GenServer with mapped configuration
    with {:ok, optimizer_opts} <- map_runner_config_to_optimizer_opts(agent, config),
         {:ok, optimizer_pid} <- Optimizer.start_link(optimizer_opts),
         {:ok, optimizer_result} <- Optimizer.optimize(optimizer_pid) do
      # Stop optimizer (cleanup)
      Optimizer.stop(optimizer_pid)

      # Map optimizer result to runner format and add Pareto frontier
      runner_result = map_optimizer_result_to_runner_format(optimizer_result)

      # Update agent state with results
      updated_agent = update_agent_with_results(agent, runner_result, config)

      # Build directives
      directives = build_directives(runner_result)

      Logger.info(
        "GEPA optimization complete (generations: #{runner_result.final_generation}, evaluations: #{runner_result.total_evaluations})"
      )

      {:ok, updated_agent, directives}
    else
      {:error, reason} = error ->
        Logger.error("GEPA optimization failed: #{inspect(reason)}")
        error
    end
  end

  @doc false
  @spec map_runner_config_to_optimizer_opts(agent(), config()) ::
          {:ok, keyword()} | {:error, term()}
  defp map_runner_config_to_optimizer_opts(agent, config) do
    # Build task map from agent and config
    task = extract_task_from_config(agent, config)

    # Map runner config to optimizer options
    optimizer_opts = [
      population_size: config.population_size,
      max_generations: config.max_generations,
      evaluation_budget: config.evaluation_budget,
      seed_prompts: config.seed_prompts,
      task: task,
      parallelism: config.parallelism
    ]

    {:ok, optimizer_opts}
  end

  @doc false
  @spec extract_task_from_config(agent(), config()) :: map()
  defp extract_task_from_config(agent, config) do
    # Build task definition from runner configuration
    # The task map describes what the optimizer should optimize for
    %{
      type: :prompt_optimization,
      test_inputs: config.test_inputs,
      expected_outputs: config.expected_outputs,
      model: config.model || get_agent_model(agent),
      objectives: config.objectives,
      objective_weights: config.objective_weights,
      mutation_rate: config.mutation_rate,
      crossover_rate: config.crossover_rate,
      enable_reflection: config.enable_reflection,
      enable_crossover: config.enable_crossover,
      convergence_threshold: config.convergence_threshold
    }
  end

  @doc false
  @spec get_agent_model(agent()) :: String.t() | nil
  defp get_agent_model(agent) when is_map(agent) do
    # Try to extract model from agent state or config
    agent
    |> Map.get(:state, %{})
    |> Map.get(:model)
  end

  defp get_agent_model(_), do: nil

  @doc false
  @spec map_optimizer_result_to_runner_format(map()) :: map()
  defp map_optimizer_result_to_runner_format(optimizer_result) do
    # Optimizer now provides both best_prompts and pareto_frontier with objectives
    # Runner just needs to ensure objectives are present for backward compatibility

    # Ensure objectives are present (fallback to fitness-based if missing)
    best_prompts = ensure_objectives_present(optimizer_result.best_prompts)
    pareto_frontier = ensure_objectives_present(optimizer_result.pareto_frontier)

    # Determine convergence reason from optimizer result
    convergence_reason =
      Map.get(optimizer_result, :stop_reason, :max_generations_reached)

    %{
      best_prompts: best_prompts,
      pareto_frontier: pareto_frontier,
      final_generation: optimizer_result.final_generation,
      total_evaluations: optimizer_result.total_evaluations,
      history: optimizer_result.history,
      convergence_reason: convergence_reason,
      duration_ms: optimizer_result.duration_ms
    }
  end

  @doc false
  @spec ensure_objectives_present(list(map())) :: list(map())
  defp ensure_objectives_present(prompts) do
    Enum.map(prompts, fn prompt ->
      # If objectives are already present, use them
      # Otherwise create fallback objectives from fitness
      if Map.has_key?(prompt, :objectives) and prompt.objectives do
        prompt
      else
        Map.put(prompt, :objectives, %{
          accuracy: prompt.fitness || 0.0,
          cost: 0.0,
          latency: 0,
          robustness: prompt.fitness || 0.0
        })
      end
    end)
  end

  @doc false
  @spec update_agent_with_results(agent(), map(), config()) :: agent()
  defp update_agent_with_results(agent, result, config) do
    updated_state =
      agent
      |> Map.get(:state, %{})
      |> Map.put(:gepa_best_prompts, result.best_prompts)
      |> Map.put(:gepa_pareto_frontier, result.pareto_frontier)
      |> Map.put(:gepa_history, result.history)
      |> Map.put(:gepa_config, Map.from_struct(config))
      |> Map.put(:gepa_last_run, %{
        final_generation: result.final_generation,
        total_evaluations: result.total_evaluations,
        convergence_reason: result.convergence_reason,
        duration_ms: result.duration_ms,
        timestamp: DateTime.utc_now()
      })

    Map.put(agent, :state, updated_state)
  end

  @doc false
  @spec build_directives(map()) :: directives()
  defp build_directives(result) do
    [
      {:optimization_complete,
       %{
         best_prompts: result.best_prompts,
         pareto_frontier: result.pareto_frontier,
         final_generation: result.final_generation,
         total_evaluations: result.total_evaluations,
         convergence_reason: result.convergence_reason
       }},
      {:best_prompt,
       %{prompt: hd(result.best_prompts).prompt, fitness: hd(result.best_prompts).fitness}}
    ]
  end
end
