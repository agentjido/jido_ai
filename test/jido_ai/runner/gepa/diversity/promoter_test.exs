defmodule Jido.AI.Runner.GEPA.Diversity.PromoterTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Runner.GEPA.Diversity.{DiversityMetrics, Promoter}

  describe "adaptive_mutation_rate/2" do
    test "increases rate for critical diversity" do
      metrics = %DiversityMetrics{
        pairwise_diversity: 0.1,
        diversity_level: :critical,
        convergence_risk: 0.9
      }

      rate = Promoter.adaptive_mutation_rate(metrics, 0.1)
      assert rate > 0.1
      assert rate <= 0.5
    end

    test "uses normal rate for healthy diversity" do
      metrics = %DiversityMetrics{
        pairwise_diversity: 0.6,
        diversity_level: :healthy,
        convergence_risk: 0.2
      }

      rate = Promoter.adaptive_mutation_rate(metrics, 0.1)
      assert rate == 0.1
    end
  end

  describe "injection_count/2" do
    test "suggests injection for critical diversity" do
      metrics = %DiversityMetrics{diversity_level: :critical}

      count = Promoter.injection_count(metrics, 10)
      assert count > 0
      # 30% of 10
      assert count <= 3
    end

    test "suggests no injection for healthy diversity" do
      metrics = %DiversityMetrics{diversity_level: :healthy}

      count = Promoter.injection_count(metrics, 10)
      assert count == 0
    end
  end

  describe "promote_diversity/3" do
    test "promotes diversity when needed" do
      prompts = ["prompt1", "prompt2", "prompt3"]
      metrics = %DiversityMetrics{diversity_level: :critical}

      assert {:ok, promoted} = Promoter.promote_diversity(prompts, metrics)
      assert is_list(promoted)
      assert length(promoted) >= length(prompts) - 1
    end

    test "returns error for empty population" do
      assert {:error, :empty_population} = Promoter.promote_diversity([], %DiversityMetrics{})
    end
  end
end
