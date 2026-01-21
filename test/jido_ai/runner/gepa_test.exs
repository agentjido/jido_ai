defmodule Jido.AI.Runner.GEPATest do
  use ExUnit.Case, async: true

  # These tests now make real API calls via TaskEvaluator
  # Exclude by default to avoid requiring API keys in CI/development
  @moduletag :requires_api

  alias Jido.AI.Runner.GEPA
  alias Jido.AI.Runner.GEPA.Config

  doctest GEPA

  describe "module structure" do
    test "implements Jido.Runner behaviour" do
      behaviours =
        GEPA.module_info(:attributes)
        |> Keyword.get(:behaviour, [])

      assert Jido.Runner in behaviours
    end

    test "exports run/2 function" do
      assert function_exported?(GEPA, :run, 2)
    end

    test "defines Config struct with required fields" do
      config = %Config{}

      # Population parameters
      assert Map.has_key?(config, :population_size)
      assert Map.has_key?(config, :max_generations)
      assert Map.has_key?(config, :evaluation_budget)
      assert Map.has_key?(config, :seed_prompts)

      # Evaluation parameters
      assert Map.has_key?(config, :test_inputs)
      assert Map.has_key?(config, :expected_outputs)
      assert Map.has_key?(config, :model)

      # Evolution parameters
      assert Map.has_key?(config, :mutation_rate)
      assert Map.has_key?(config, :crossover_rate)
      assert Map.has_key?(config, :parallelism)

      # Multi-objective parameters
      assert Map.has_key?(config, :objectives)
      assert Map.has_key?(config, :objective_weights)

      # Advanced options
      assert Map.has_key?(config, :enable_reflection)
      assert Map.has_key?(config, :enable_crossover)
      assert Map.has_key?(config, :convergence_threshold)
    end
  end

  describe "Config struct defaults" do
    test "has correct default values" do
      config = %Config{}

      # Population parameters
      assert config.population_size == 10
      assert config.max_generations == 20
      assert config.evaluation_budget == 200
      assert config.seed_prompts == []

      # Evaluation parameters
      assert config.test_inputs == []
      assert config.expected_outputs == nil
      assert config.model == nil

      # Evolution parameters
      assert config.mutation_rate == 0.3
      assert config.crossover_rate == 0.7
      assert config.parallelism == 5

      # Multi-objective parameters
      assert config.objectives == [:accuracy, :cost, :latency, :robustness]
      assert config.objective_weights == %{}

      # Advanced options
      assert config.enable_reflection == true
      assert config.enable_crossover == true
      assert config.convergence_threshold == 0.001
    end
  end

  describe "configuration validation" do
    setup do
      agent = build_test_agent()
      {:ok, agent: agent}
    end

    test "accepts valid population_size", %{agent: agent} do
      result = GEPA.run(agent, test_inputs: ["input"], population_size: 5)
      assert {:ok, _agent, _directives} = result
    end

    test "rejects non-positive population_size", %{agent: agent} do
      assert {:error, error} = GEPA.run(agent, test_inputs: ["input"], population_size: 1)
      assert error =~ "population_size must be at least 2"
    end

    test "rejects zero population_size", %{agent: agent} do
      assert {:error, error} = GEPA.run(agent, test_inputs: ["input"], population_size: 0)
      assert error =~ "population_size must be at least 2"
    end

    test "accepts valid max_generations", %{agent: agent} do
      result = GEPA.run(agent, test_inputs: ["input"], max_generations: 10)
      assert {:ok, _agent, _directives} = result
    end

    test "rejects zero max_generations", %{agent: agent} do
      assert {:error, error} = GEPA.run(agent, test_inputs: ["input"], max_generations: 0)
      assert error =~ "max_generations must be at least 1"
    end

    test "accepts valid evaluation_budget", %{agent: agent} do
      result = GEPA.run(agent, test_inputs: ["input"], evaluation_budget: 100)
      assert {:ok, _agent, _directives} = result
    end

    test "rejects evaluation_budget < population_size", %{agent: agent} do
      assert {:error, error} =
               GEPA.run(agent, test_inputs: ["input"], population_size: 20, evaluation_budget: 10)

      assert error =~ "evaluation_budget"
      assert error =~ "must be >= population_size"
    end

    test "accepts valid mutation_rate", %{agent: agent} do
      result = GEPA.run(agent, test_inputs: ["input"], mutation_rate: 0.5)
      assert {:ok, _agent, _directives} = result
    end

    test "rejects mutation_rate < 0", %{agent: agent} do
      assert {:error, error} = GEPA.run(agent, test_inputs: ["input"], mutation_rate: -0.1)
      assert error =~ "mutation_rate must be between 0.0 and 1.0"
    end

    test "rejects mutation_rate > 1", %{agent: agent} do
      assert {:error, error} = GEPA.run(agent, test_inputs: ["input"], mutation_rate: 1.5)
      assert error =~ "mutation_rate must be between 0.0 and 1.0"
    end

    test "accepts valid crossover_rate", %{agent: agent} do
      result = GEPA.run(agent, test_inputs: ["input"], crossover_rate: 0.8)
      assert {:ok, _agent, _directives} = result
    end

    test "rejects crossover_rate < 0", %{agent: agent} do
      assert {:error, error} = GEPA.run(agent, test_inputs: ["input"], crossover_rate: -0.1)
      assert error =~ "crossover_rate must be between 0.0 and 1.0"
    end

    test "rejects crossover_rate > 1", %{agent: agent} do
      assert {:error, error} = GEPA.run(agent, test_inputs: ["input"], crossover_rate: 1.1)
      assert error =~ "crossover_rate must be between 0.0 and 1.0"
    end

    test "accepts valid parallelism", %{agent: agent} do
      result = GEPA.run(agent, test_inputs: ["input"], parallelism: 10)
      assert {:ok, _agent, _directives} = result
    end

    test "rejects zero parallelism", %{agent: agent} do
      assert {:error, error} = GEPA.run(agent, test_inputs: ["input"], parallelism: 0)
      assert error =~ "parallelism must be at least 1"
    end

    test "accepts valid objectives", %{agent: agent} do
      result = GEPA.run(agent, test_inputs: ["input"], objectives: [:accuracy, :cost])
      assert {:ok, _agent, _directives} = result
    end

    test "rejects invalid objectives", %{agent: agent} do
      assert {:error, error} =
               GEPA.run(agent, test_inputs: ["input"], objectives: [:accuracy, :invalid])

      assert error =~ "invalid objectives"
      assert error =~ "invalid"
    end

    test "requires test_inputs", %{agent: agent} do
      assert {:error, error} = GEPA.run(agent, test_inputs: [])
      assert error =~ "test_inputs cannot be empty"
    end

    test "accepts list of test_inputs", %{agent: agent} do
      result = GEPA.run(agent, test_inputs: ["input1", "input2", "input3"])
      assert {:ok, _agent, _directives} = result
    end
  end

  describe "agent state configuration" do
    test "uses configuration from agent state" do
      agent =
        build_test_agent_with_config(%{
          population_size: 15,
          max_generations: 30,
          test_inputs: ["test input"]
        })

      result = GEPA.run(agent)
      # Should not fail on missing test_inputs since it's in state
      assert {:ok, _agent, _directives} = result
    end

    test "runtime opts override agent state config" do
      agent =
        build_test_agent_with_config(%{
          population_size: 15,
          max_generations: 30,
          test_inputs: ["test input"]
        })

      # Override with runtime opts
      opts = [
        population_size: 20,
        max_generations: 50
      ]

      result = GEPA.run(agent, opts)
      assert {:ok, _agent, _directives} = result
    end

    test "handles missing state config gracefully" do
      agent = build_test_agent()

      # Should require test_inputs since not in state
      assert {:error, error} = GEPA.run(agent)
      assert error =~ "test_inputs cannot be empty"
    end

    test "merges all configuration sources correctly" do
      # Agent state config
      agent =
        build_test_agent_with_config(%{
          population_size: 15,
          max_generations: 30,
          mutation_rate: 0.4,
          test_inputs: ["test"]
        })

      # Runtime opts (should override)
      opts = [
        max_generations: 50,
        model: "gpt-4"
      ]

      result = GEPA.run(agent, opts)
      assert {:ok, _agent, _directives} = result
    end
  end

  describe "run/2 with minimal config" do
    test "requires test_inputs parameter" do
      agent = build_test_agent()

      assert {:error, error} = GEPA.run(agent)
      assert error =~ "test_inputs cannot be empty"
    end

    test "accepts minimal valid configuration" do
      agent = build_test_agent()

      result = GEPA.run(agent, test_inputs: ["input1", "input2"])
      assert {:ok, updated_agent, directives} = result

      # Verify agent state updated
      assert Map.has_key?(updated_agent.state, :gepa_best_prompts)
      assert Map.has_key?(updated_agent.state, :gepa_pareto_frontier)
      assert Map.has_key?(updated_agent.state, :gepa_history)
      assert Map.has_key?(updated_agent.state, :gepa_config)
      assert Map.has_key?(updated_agent.state, :gepa_last_run)

      # Verify directives returned
      assert is_list(directives)
      assert length(directives) > 0
    end

    test "returns best prompts in agent state" do
      agent = build_test_agent()

      {:ok, updated_agent, _directives} = GEPA.run(agent, test_inputs: ["input"])

      best_prompts = updated_agent.state.gepa_best_prompts
      assert is_list(best_prompts)
      assert length(best_prompts) > 0

      # Verify prompt structure
      first_prompt = hd(best_prompts)
      assert Map.has_key?(first_prompt, :prompt)
      assert Map.has_key?(first_prompt, :fitness)
      assert Map.has_key?(first_prompt, :objectives)
      assert Map.has_key?(first_prompt, :generation)
    end

    test "returns Pareto frontier in agent state" do
      agent = build_test_agent()

      {:ok, updated_agent, _directives} = GEPA.run(agent, test_inputs: ["input"])

      frontier = updated_agent.state.gepa_pareto_frontier
      assert is_list(frontier)
      assert length(frontier) > 0
    end

    test "returns optimization history" do
      agent = build_test_agent()

      {:ok, updated_agent, _directives} =
        GEPA.run(agent, test_inputs: ["input"], max_generations: 5)

      history = updated_agent.state.gepa_history
      assert is_list(history)
      # Optimizer may converge early, so history length <= max_generations
      assert length(history) > 0
      assert length(history) <= 5

      # Verify history structure
      first_entry = hd(history)
      assert Map.has_key?(first_entry, :generation)
      assert Map.has_key?(first_entry, :best_fitness)
      assert Map.has_key?(first_entry, :avg_fitness)
    end

    test "returns directives with optimization results" do
      agent = build_test_agent()

      {:ok, _updated_agent, directives} = GEPA.run(agent, test_inputs: ["input"])

      # Should have optimization_complete directive
      assert Enum.any?(directives, fn
               {:optimization_complete, _} -> true
               _ -> false
             end)

      # Should have best_prompt directive
      assert Enum.any?(directives, fn
               {:best_prompt, _} -> true
               _ -> false
             end)
    end
  end

  describe "run/2 with seed prompts" do
    test "accepts seed prompts parameter" do
      agent = build_test_agent()

      result =
        GEPA.run(agent,
          test_inputs: ["input1", "input2"],
          seed_prompts: ["Solve step by step", "Think carefully"]
        )

      assert {:ok, updated_agent, _directives} = result

      # Should use seed prompts (at least some prompts returned)
      best_prompts = updated_agent.state.gepa_best_prompts
      assert length(best_prompts) >= 1

      # Prompts should be based on seeds (may have variations appended)
      # Check that at least one prompt contains the seed text
      prompt_texts = Enum.map(best_prompts, & &1.prompt)

      has_seed_1 =
        Enum.any?(prompt_texts, fn text ->
          String.contains?(text, "Solve step by step")
        end)

      assert has_seed_1, "Expected at least one prompt based on 'Solve step by step'"
    end

    test "accepts empty seed prompts" do
      agent = build_test_agent()

      result =
        GEPA.run(agent,
          test_inputs: ["input1", "input2"],
          seed_prompts: []
        )

      assert {:ok, updated_agent, _directives} = result

      # Should generate default prompts
      best_prompts = updated_agent.state.gepa_best_prompts
      assert length(best_prompts) > 0
    end

    test "uses seed prompts in population" do
      agent = build_test_agent()

      seeds = ["Prompt 1", "Prompt 2", "Prompt 3"]

      {:ok, updated_agent, _directives} =
        GEPA.run(agent,
          test_inputs: ["input"],
          seed_prompts: seeds,
          population_size: 10
        )

      best_prompts = updated_agent.state.gepa_best_prompts
      prompt_texts = Enum.map(best_prompts, & &1.prompt)

      # At least some prompts should be based on seeds
      # (Evolution may select out some seeds based on fitness)
      has_any_seed =
        Enum.any?(prompt_texts, fn text ->
          Enum.any?(seeds, fn seed -> String.contains?(text, seed) end)
        end)

      assert has_any_seed, "Expected at least one prompt based on seed prompts"
      assert length(best_prompts) > 0
    end
  end

  describe "multi-objective optimization" do
    test "accepts multiple objectives" do
      agent = build_test_agent()

      result =
        GEPA.run(agent,
          test_inputs: ["input"],
          objectives: [:accuracy, :cost, :latency]
        )

      assert {:ok, updated_agent, _directives} = result

      # Verify objectives are tracked
      best_prompts = updated_agent.state.gepa_best_prompts
      first_prompt = hd(best_prompts)
      assert Map.has_key?(first_prompt.objectives, :accuracy)
      assert Map.has_key?(first_prompt.objectives, :cost)
      assert Map.has_key?(first_prompt.objectives, :latency)
    end

    test "accepts single objective" do
      agent = build_test_agent()

      result =
        GEPA.run(agent,
          test_inputs: ["input"],
          objectives: [:accuracy]
        )

      assert {:ok, _updated_agent, _directives} = result
    end

    test "accepts objective weights" do
      agent = build_test_agent()

      result =
        GEPA.run(agent,
          test_inputs: ["input"],
          objectives: [:accuracy, :cost],
          objective_weights: %{accuracy: 2.0, cost: 1.0}
        )

      assert {:ok, _updated_agent, _directives} = result
    end

    test "returns Pareto frontier with trade-offs" do
      agent = build_test_agent()

      {:ok, updated_agent, _directives} =
        GEPA.run(agent,
          test_inputs: ["input"],
          objectives: [:accuracy, :cost],
          population_size: 10
        )

      frontier = updated_agent.state.gepa_pareto_frontier
      assert is_list(frontier)
      assert length(frontier) > 0
      # Limited to top 5
      assert length(frontier) <= 5
    end
  end

  describe "error handling" do
    test "handles invalid agent gracefully" do
      assert {:error, error} = GEPA.run("not an agent", test_inputs: ["input"])
      assert error =~ "invalid agent"
    end

    test "handles nil agent gracefully" do
      assert {:error, error} = GEPA.run(nil, test_inputs: ["input"])
      assert error =~ "invalid agent"
    end

    test "returns helpful error message for missing test_inputs" do
      agent = build_test_agent()
      assert {:error, error} = GEPA.run(agent)
      assert error =~ "test_inputs cannot be empty"
    end

    test "returns helpful error for invalid population_size" do
      agent = build_test_agent()

      assert {:error, error} = GEPA.run(agent, test_inputs: ["input"], population_size: 0)
      assert error =~ "population_size must be at least 2"
    end
  end

  # Test Helpers

  defp build_test_agent do
    %{
      id: "test-agent-#{:rand.uniform(10000)}",
      name: "GEPA Test Agent",
      state: %{},
      pending_instructions: :queue.new(),
      actions: [],
      runner: GEPA,
      result: nil
    }
  end

  defp build_test_agent_with_config(config) when is_map(config) do
    agent = build_test_agent()
    %{agent | state: Map.put(agent.state, :gepa_config, config)}
  end
end
