defmodule Jido.AI.Runner.GEPA.Diversity.MetricsTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Runner.GEPA.Diversity.{DiversityMetrics, Metrics}

  describe "calculate/2" do
    test "calculates metrics for diverse population" do
      prompts = [
        "Solve this problem",
        "Calculate that equation",
        "Analyze the data",
        "Explain your reasoning"
      ]

      assert {:ok, %DiversityMetrics{} = metrics} = Metrics.calculate(prompts)
      assert metrics.pairwise_diversity >= 0.0
      assert metrics.pairwise_diversity <= 1.0
      assert metrics.diversity_level in [:critical, :low, :moderate, :healthy, :excellent]
    end

    test "handles single prompt" do
      prompts = ["Single prompt"]

      assert {:ok, metrics} = Metrics.calculate(prompts)
      assert metrics.pairwise_diversity == 1.0
      assert metrics.diversity_level == :excellent
    end

    test "returns error for empty population" do
      assert {:error, :empty_population} = Metrics.calculate([])
    end

    test "detects low diversity" do
      # Very similar prompts
      prompts = [
        "Solve this",
        "Solve this.",
        "Solve this!",
        "Solve this?"
      ]

      assert {:ok, metrics} = Metrics.calculate(prompts)
      # Should have lower diversity due to similarity
      assert is_float(metrics.pairwise_diversity)
    end
  end

  describe "acceptable?/2" do
    test "returns true for acceptable diversity" do
      metrics = %DiversityMetrics{pairwise_diversity: 0.5}
      assert Metrics.acceptable?(metrics, 0.3) == true
    end

    test "returns false for unacceptable diversity" do
      metrics = %DiversityMetrics{pairwise_diversity: 0.2}
      assert Metrics.acceptable?(metrics, 0.3) == false
    end
  end

  describe "needs_promotion?/2" do
    test "returns true for critical diversity" do
      metrics = %DiversityMetrics{
        pairwise_diversity: 0.1,
        diversity_level: :critical,
        convergence_risk: 0.8
      }

      assert Metrics.needs_promotion?(metrics) == true
    end

    test "returns false for healthy diversity" do
      metrics = %DiversityMetrics{
        pairwise_diversity: 0.6,
        diversity_level: :healthy,
        convergence_risk: 0.2
      }

      assert Metrics.needs_promotion?(metrics) == false
    end
  end
end
