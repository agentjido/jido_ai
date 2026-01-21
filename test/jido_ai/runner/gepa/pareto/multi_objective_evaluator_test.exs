defmodule Jido.AI.Runner.GEPA.Pareto.MultiObjectiveEvaluatorTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Runner.GEPA.Pareto.MultiObjectiveEvaluator
  alias Jido.AI.Runner.GEPA.Population.Candidate

  describe "evaluate/2" do
    test "evaluates all standard objectives successfully" do
      results = create_trajectory_results(3)

      assert {:ok, objectives} = MultiObjectiveEvaluator.evaluate(results)

      assert Map.has_key?(objectives, :accuracy)
      assert Map.has_key?(objectives, :latency)
      assert Map.has_key?(objectives, :cost)
      assert Map.has_key?(objectives, :robustness)

      # All values should be floats
      assert is_float(objectives.accuracy)
      assert is_float(objectives.latency)
      assert is_float(objectives.cost)
      assert is_float(objectives.robustness)
    end

    test "returns error for empty trajectory results" do
      assert {:error, :no_trajectory_results} = MultiObjectiveEvaluator.evaluate([])
    end

    test "returns error for invalid trajectory results" do
      assert {:error, :invalid_trajectory_results} = MultiObjectiveEvaluator.evaluate("invalid")
    end

    test "evaluates only specified objectives" do
      results = create_trajectory_results(2)

      assert {:ok, objectives} =
               MultiObjectiveEvaluator.evaluate(results, objectives: [:accuracy, :latency])

      assert Enum.sort(Map.keys(objectives)) == [:accuracy, :latency]
    end

    test "evaluates custom objectives" do
      results = create_trajectory_results(2)

      custom_objectives = %{
        custom_metric: fn _results -> 0.75 end
      }

      assert {:ok, objectives} =
               MultiObjectiveEvaluator.evaluate(results,
                 objectives: [:custom_metric],
                 custom_objectives: custom_objectives
               )

      assert objectives.custom_metric == 0.75
    end

    test "uses custom model pricing for cost calculation" do
      results = [
        %{
          success: true,
          duration_ms: 1000,
          prompt_tokens: 100,
          completion_tokens: 50,
          quality_score: 0.9
        }
      ]

      pricing = %{cost_per_1k_tokens: 0.10}

      assert {:ok, objectives} =
               MultiObjectiveEvaluator.evaluate(results, model_pricing: pricing)

      # 150 tokens * $0.10 / 1000 = $0.015
      assert objectives.cost == 0.015
    end
  end

  describe "measure_accuracy/1" do
    test "calculates accuracy for all successful results" do
      results = [
        %{success: true},
        %{success: true},
        %{success: true}
      ]

      assert {:ok, objectives} =
               MultiObjectiveEvaluator.evaluate(results, objectives: [:accuracy])

      assert objectives.accuracy == 1.0
    end

    test "calculates accuracy for mixed results" do
      results = [
        %{success: true},
        %{success: false},
        %{success: true},
        %{success: false}
      ]

      assert {:ok, objectives} =
               MultiObjectiveEvaluator.evaluate(results, objectives: [:accuracy])

      assert objectives.accuracy == 0.5
    end

    test "calculates accuracy for all failed results" do
      results = [
        %{success: false},
        %{success: false}
      ]

      assert {:ok, objectives} =
               MultiObjectiveEvaluator.evaluate(results, objectives: [:accuracy])

      assert objectives.accuracy == 0.0
    end

    test "handles missing success field" do
      results = [
        %{duration_ms: 100},
        %{duration_ms: 200}
      ]

      assert {:ok, objectives} =
               MultiObjectiveEvaluator.evaluate(results, objectives: [:accuracy])

      # Should default to false
      assert objectives.accuracy == 0.0
    end
  end

  describe "measure_latency/1" do
    test "calculates average latency in seconds" do
      results = [
        %{duration_ms: 1000, success: true},
        %{duration_ms: 2000, success: true},
        %{duration_ms: 3000, success: true}
      ]

      assert {:ok, objectives} = MultiObjectiveEvaluator.evaluate(results, objectives: [:latency])
      # Average: 2000ms = 2.0 seconds
      assert objectives.latency == 2.0
    end

    test "handles single result" do
      results = [%{duration_ms: 1500, success: true}]

      assert {:ok, objectives} = MultiObjectiveEvaluator.evaluate(results, objectives: [:latency])
      assert objectives.latency == 1.5
    end

    test "handles missing duration_ms field" do
      results = [%{success: true}, %{success: true}]

      assert {:ok, objectives} = MultiObjectiveEvaluator.evaluate(results, objectives: [:latency])
      # Should default to 0
      assert objectives.latency == 0.0
    end

    test "rounds to 4 decimal places" do
      results = [%{duration_ms: 1234, success: true}]

      assert {:ok, objectives} = MultiObjectiveEvaluator.evaluate(results, objectives: [:latency])
      assert objectives.latency == 1.234
    end
  end

  describe "measure_cost/2" do
    test "calculates cost based on token usage" do
      results = [
        %{prompt_tokens: 100, completion_tokens: 50, success: true},
        %{prompt_tokens: 200, completion_tokens: 100, success: true}
      ]

      pricing = %{cost_per_1k_tokens: 0.03}

      assert {:ok, objectives} =
               MultiObjectiveEvaluator.evaluate(results,
                 objectives: [:cost],
                 model_pricing: pricing
               )

      # Total: (100+50) + (200+100) = 450 tokens
      # Cost: 450 * 0.03 / 1000 = 0.0135
      assert objectives.cost == 0.0135
    end

    test "handles missing token fields" do
      results = [%{success: true}, %{success: true}]

      assert {:ok, objectives} = MultiObjectiveEvaluator.evaluate(results, objectives: [:cost])
      assert objectives.cost == 0.0
    end

    test "uses default pricing when not specified" do
      results = [%{prompt_tokens: 1000, completion_tokens: 500, success: true}]

      assert {:ok, objectives} = MultiObjectiveEvaluator.evaluate(results, objectives: [:cost])
      # Default: 0.03 per 1k tokens
      # 1500 * 0.03 / 1000 = 0.045
      assert objectives.cost == 0.045
    end

    test "rounds to 4 decimal places" do
      results = [%{prompt_tokens: 123, completion_tokens: 456, success: true}]
      pricing = %{cost_per_1k_tokens: 0.03}

      assert {:ok, objectives} =
               MultiObjectiveEvaluator.evaluate(results,
                 objectives: [:cost],
                 model_pricing: pricing
               )

      # 579 * 0.03 / 1000 = 0.01737 -> rounded to 0.0174
      assert objectives.cost == 0.0174
    end
  end

  describe "measure_robustness/1" do
    test "calculates robustness for consistent performance" do
      results = [
        %{quality_score: 0.9, success: true},
        %{quality_score: 0.9, success: true},
        %{quality_score: 0.9, success: true}
      ]

      assert {:ok, objectives} =
               MultiObjectiveEvaluator.evaluate(results, objectives: [:robustness])

      # Zero variance = high robustness (e^0 = 1.0)
      assert objectives.robustness == 1.0
    end

    test "calculates robustness for varying performance" do
      results = [
        %{quality_score: 0.5, success: true},
        %{quality_score: 0.7, success: true},
        %{quality_score: 0.9, success: true}
      ]

      assert {:ok, objectives} =
               MultiObjectiveEvaluator.evaluate(results, objectives: [:robustness])

      # Higher variance = lower robustness
      assert objectives.robustness < 1.0
      assert objectives.robustness > 0.0
    end

    test "returns 1.0 for single result" do
      results = [%{quality_score: 0.8, success: true}]

      assert {:ok, objectives} =
               MultiObjectiveEvaluator.evaluate(results, objectives: [:robustness])

      # Single result = perfect consistency
      assert objectives.robustness == 1.0
    end

    test "handles missing quality_score field" do
      results = [%{success: true}, %{success: true}]

      assert {:ok, objectives} =
               MultiObjectiveEvaluator.evaluate(results, objectives: [:robustness])

      # Should default to 0.0, zero variance = high robustness
      assert objectives.robustness == 1.0
    end

    test "returns 0.0 for empty results" do
      results = []

      assert {:error, :no_trajectory_results} = MultiObjectiveEvaluator.evaluate(results)
    end
  end

  describe "normalize_objectives/3" do
    test "normalizes objectives to [0, 1] range" do
      objectives = %{
        accuracy: 0.8,
        latency: 2.0,
        cost: 0.05
      }

      population_stats = %{
        accuracy_min: 0.6,
        accuracy_max: 1.0,
        latency_min: 1.0,
        latency_max: 3.0,
        cost_min: 0.01,
        cost_max: 0.1
      }

      normalized = MultiObjectiveEvaluator.normalize_objectives(objectives, population_stats)

      # Accuracy: (0.8 - 0.6) / (1.0 - 0.6) = 0.5
      assert normalized.accuracy == 0.5

      # Latency (minimize, inverted): 1 - ((2.0 - 1.0) / (3.0 - 1.0)) = 0.5
      assert normalized.latency == 0.5

      # Cost (minimize, inverted): 1 - ((0.05 - 0.01) / (0.1 - 0.01)) = 0.5556
      assert normalized.cost == 0.5556
    end

    test "handles objectives with same min and max" do
      objectives = %{accuracy: 0.9}

      population_stats = %{
        accuracy_min: 0.9,
        accuracy_max: 0.9
      }

      normalized = MultiObjectiveEvaluator.normalize_objectives(objectives, population_stats)

      # When min == max, should return 0.5
      assert normalized.accuracy == 0.5
    end

    test "inverts minimization objectives" do
      objectives = %{latency: 1.0, cost: 0.01}

      population_stats = %{
        latency_min: 1.0,
        latency_max: 3.0,
        cost_min: 0.01,
        cost_max: 0.1
      }

      normalized = MultiObjectiveEvaluator.normalize_objectives(objectives, population_stats)

      # Latency at minimum = best = 1.0 after inversion
      assert normalized.latency == 1.0

      # Cost at minimum = best = 1.0 after inversion
      assert normalized.cost == 1.0
    end

    test "respects custom objective types" do
      objectives = %{custom_metric: 5.0}

      population_stats = %{
        custom_metric_min: 0.0,
        custom_metric_max: 10.0
      }

      # Treat custom_metric as minimization objective
      normalized =
        MultiObjectiveEvaluator.normalize_objectives(
          objectives,
          population_stats,
          objective_types: %{custom_metric: :minimize}
        )

      # 5.0 is halfway, so normalized = 0.5, inverted = 0.5
      assert normalized.custom_metric == 0.5
    end

    test "returns empty map for invalid inputs" do
      assert %{} = MultiObjectiveEvaluator.normalize_objectives("invalid", %{})
      assert %{} = MultiObjectiveEvaluator.normalize_objectives(%{}, "invalid")
    end
  end

  describe "calculate_population_stats/1" do
    test "calculates min and max for each objective" do
      candidates = [
        create_candidate(objectives: %{accuracy: 0.7, latency: 1.0, cost: 0.01}),
        create_candidate(objectives: %{accuracy: 0.9, latency: 2.5, cost: 0.05}),
        create_candidate(objectives: %{accuracy: 0.8, latency: 1.5, cost: 0.03})
      ]

      stats = MultiObjectiveEvaluator.calculate_population_stats(candidates)

      assert stats.accuracy_min == 0.7
      assert stats.accuracy_max == 0.9
      assert stats.latency_min == 1.0
      assert stats.latency_max == 2.5
      assert stats.cost_min == 0.01
      assert stats.cost_max == 0.05
    end

    test "handles empty population" do
      assert %{} = MultiObjectiveEvaluator.calculate_population_stats([])
    end

    test "handles candidates without objectives" do
      candidates = [
        create_candidate(objectives: nil),
        create_candidate(objectives: nil)
      ]

      assert %{} = MultiObjectiveEvaluator.calculate_population_stats(candidates)
    end

    test "handles mixed candidates with and without objectives" do
      candidates = [
        create_candidate(objectives: %{accuracy: 0.8}),
        create_candidate(objectives: nil),
        create_candidate(objectives: %{accuracy: 0.9})
      ]

      stats = MultiObjectiveEvaluator.calculate_population_stats(candidates)

      assert stats.accuracy_min == 0.8
      assert stats.accuracy_max == 0.9
    end

    test "handles single candidate" do
      candidates = [
        create_candidate(objectives: %{accuracy: 0.85, latency: 2.0})
      ]

      stats = MultiObjectiveEvaluator.calculate_population_stats(candidates)

      assert stats.accuracy_min == 0.85
      assert stats.accuracy_max == 0.85
      assert stats.latency_min == 2.0
      assert stats.latency_max == 2.0
    end
  end

  describe "aggregate_fitness/2" do
    test "computes weighted aggregate fitness" do
      normalized = %{
        accuracy: 0.9,
        latency: 0.7,
        cost: 0.8,
        robustness: 0.85
      }

      weights = %{
        accuracy: 0.5,
        latency: 0.2,
        cost: 0.2,
        robustness: 0.1
      }

      fitness = MultiObjectiveEvaluator.aggregate_fitness(normalized, weights: weights)

      # 0.9*0.5 + 0.7*0.2 + 0.8*0.2 + 0.85*0.1 = 0.835 (rounded to 4 decimals)
      assert fitness == 0.835
    end

    test "uses default weights when not specified" do
      normalized = %{
        accuracy: 1.0,
        latency: 0.5,
        cost: 0.5,
        robustness: 0.5
      }

      fitness = MultiObjectiveEvaluator.aggregate_fitness(normalized)

      # Default weights: accuracy: 0.5, latency: 0.2, cost: 0.2, robustness: 0.1
      # 1.0*0.5 + 0.5*0.2 + 0.5*0.2 + 0.5*0.1 = 0.75
      assert fitness == 0.75
    end

    test "handles partial objectives" do
      normalized = %{
        accuracy: 0.9,
        latency: 0.8
      }

      weights = %{
        accuracy: 0.6,
        latency: 0.4
      }

      fitness = MultiObjectiveEvaluator.aggregate_fitness(normalized, weights: weights)

      # 0.9*0.6 + 0.8*0.4 = 0.86
      assert fitness == 0.86
    end

    test "ignores objectives with zero weight" do
      normalized = %{
        accuracy: 0.9,
        latency: 0.5
      }

      weights = %{
        accuracy: 1.0,
        latency: 0.0
      }

      fitness = MultiObjectiveEvaluator.aggregate_fitness(normalized, weights: weights)

      # Only accuracy counts
      assert fitness == 0.9
    end

    test "returns 0.0 for invalid input" do
      assert 0.0 = MultiObjectiveEvaluator.aggregate_fitness("invalid")
      assert 0.0 = MultiObjectiveEvaluator.aggregate_fitness(nil)
    end

    test "rounds to 4 decimal places" do
      normalized = %{
        accuracy: 0.333333,
        latency: 0.666666
      }

      weights = %{
        accuracy: 0.5,
        latency: 0.5
      }

      fitness = MultiObjectiveEvaluator.aggregate_fitness(normalized, weights: weights)

      # Should be rounded
      assert fitness == 0.5
    end
  end

  describe "helper functions" do
    test "standard_objectives/0 returns standard objective list" do
      objectives = MultiObjectiveEvaluator.standard_objectives()

      assert :accuracy in objectives
      assert :latency in objectives
      assert :cost in objectives
      assert :robustness in objectives
      assert length(objectives) == 4
    end

    test "default_objective_types/0 returns correct types" do
      types = MultiObjectiveEvaluator.default_objective_types()

      assert types.accuracy == :maximize
      assert types.latency == :minimize
      assert types.cost == :minimize
      assert types.robustness == :maximize
    end

    test "default_weights/0 returns balanced weights" do
      weights = MultiObjectiveEvaluator.default_weights()

      assert weights.accuracy == 0.5
      assert weights.latency == 0.2
      assert weights.cost == 0.2
      assert weights.robustness == 0.1

      # Weights should sum to ~1.0 (allow for floating point precision)
      total = Enum.sum(Map.values(weights))
      assert_in_delta total, 1.0, 0.0001
    end
  end

  # Helper functions

  defp create_trajectory_results(count) do
    Enum.map(1..count, fn i ->
      %{
        success: rem(i, 2) == 0,
        duration_ms: i * 1000,
        prompt_tokens: i * 100,
        completion_tokens: i * 50,
        quality_score: 0.5 + i * 0.1
      }
    end)
  end

  defp create_candidate(opts \\ []) do
    %Candidate{
      id: Keyword.get(opts, :id, "test_#{:rand.uniform(10000)}"),
      prompt: Keyword.get(opts, :prompt, "Test prompt"),
      generation: Keyword.get(opts, :generation, 0),
      created_at: System.system_time(:millisecond),
      objectives: Keyword.get(opts, :objectives, nil)
    }
  end
end
