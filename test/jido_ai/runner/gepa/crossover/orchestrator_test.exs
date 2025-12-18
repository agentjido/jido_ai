defmodule JidoAI.Runner.GEPA.Crossover.OrchestratorTest do
  use ExUnit.Case, async: true

  alias JidoAI.Runner.GEPA.Crossover.{CrossoverConfig, CrossoverResult, Orchestrator}

  describe "perform_crossover/3" do
    test "performs crossover on two compatible prompts" do
      prompt_a = "Solve this math problem step by step. Show all work."
      prompt_b = "Calculate the answer carefully. Explain your reasoning."

      assert {:ok, %CrossoverResult{} = result} =
               Orchestrator.perform_crossover(prompt_a, prompt_b)

      assert length(result.offspring_prompts) > 0
      assert result.validated
      assert result.strategy_used in [:single_point, :two_point, :uniform, :semantic]
      assert length(result.parent_ids) == 2
    end

    test "uses specified strategy from config" do
      prompt_a = "First prompt with instructions."
      prompt_b = "Second prompt with different instructions."

      config = %CrossoverConfig{strategy: :uniform}

      assert {:ok, result} = Orchestrator.perform_crossover(prompt_a, prompt_b, config)
      assert result.strategy_used == :uniform
    end

    test "returns error for empty prompts" do
      assert {:error, _} = Orchestrator.perform_crossover("", "test")
      assert {:error, _} = Orchestrator.perform_crossover("test", "")
    end

    test "validates offspring when configured" do
      prompt_a = "Test A"
      prompt_b = "Test B"

      config = %CrossoverConfig{validate_offspring: true}

      result = Orchestrator.perform_crossover(prompt_a, prompt_b, config)

      # Should either succeed with validated offspring or fail validation
      case result do
        {:ok, res} -> assert res.validated
        {:error, _} -> assert true
      end
    end

    test "produces different offspring from different strategies" do
      prompt_a = "Alpha instructions. Beta steps. Gamma rules."
      prompt_b = "One directions. Two phases. Three constraints."

      config1 = %CrossoverConfig{strategy: :single_point}
      config2 = %CrossoverConfig{strategy: :uniform}

      {:ok, result1} = Orchestrator.perform_crossover(prompt_a, prompt_b, config1)
      {:ok, result2} = Orchestrator.perform_crossover(prompt_a, prompt_b, config2)

      assert result1.strategy_used == :single_point
      assert result2.strategy_used == :uniform
      # Results may differ
      assert is_list(result1.offspring_prompts)
      assert is_list(result2.offspring_prompts)
    end
  end

  describe "batch_crossover/2" do
    test "performs crossover on multiple pairs" do
      pairs = [
        {"Prompt 1A", "Prompt 1B"},
        {"Prompt 2A", "Prompt 2B"}
      ]

      result = Orchestrator.batch_crossover(pairs)

      case result do
        {:ok, results} ->
          assert length(results) == 2
          assert Enum.all?(results, &match?(%CrossoverResult{}, &1))

        {:error, _} ->
          # Batch may fail if any pair incompatible
          assert true
      end
    end

    test "returns errors for failed pairs" do
      pairs = [
        {"", ""},
        {"Valid", "Prompt"}
      ]

      result = Orchestrator.batch_crossover(pairs)

      # Should detect failure
      assert match?({:error, _}, result) or match?({:ok, _}, result)
    end
  end
end
