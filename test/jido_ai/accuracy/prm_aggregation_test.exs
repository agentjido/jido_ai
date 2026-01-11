defmodule Jido.AI.Accuracy.PrmAggregationTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Accuracy.PrmAggregation

  @moduletag :capture_log

  describe "aggregate/3" do
    test "aggregates with :sum strategy" do
      scores = [0.8, 0.9, 0.7]
      result = PrmAggregation.aggregate(scores, :sum)
      assert_in_delta result, 2.4, 0.001
    end

    test "aggregates with :product strategy" do
      scores = [0.8, 0.9, 0.7]
      result = PrmAggregation.aggregate(scores, :product)
      assert_in_delta result, 0.504, 0.001
    end

    test "aggregates with :min strategy" do
      scores = [0.8, 0.9, 0.7]
      result = PrmAggregation.aggregate(scores, :min)
      assert result == 0.7
    end

    test "aggregates with :max strategy" do
      scores = [0.8, 0.9, 0.7]
      result = PrmAggregation.aggregate(scores, :max)
      assert result == 0.9
    end

    test "aggregates with :average strategy" do
      scores = [0.8, 0.9, 0.7]
      result = PrmAggregation.aggregate(scores, :average)
      assert_in_delta result, 0.8, 0.001
    end

    test "aggregates with :weighted_average strategy" do
      scores = [0.8, 0.9, 0.7]
      result = PrmAggregation.aggregate(scores, :weighted_average, weights: [0.2, 0.3, 0.5])
      assert_in_delta result, 0.78, 0.001
    end

    test "raises error for unknown strategy" do
      scores = [0.8, 0.9, 0.7]

      assert_raise ArgumentError, ~r/Unknown aggregation strategy/, fn ->
        PrmAggregation.aggregate(scores, :unknown)
      end
    end
  end

  describe "sum_scores/1" do
    test "returns sum of positive scores" do
      result = PrmAggregation.sum_scores([0.8, 0.9, 0.7])
      assert_in_delta result, 2.4, 0.001
    end

    test "returns sum with negative scores" do
      assert PrmAggregation.sum_scores([0.8, -0.2, 0.9]) == 1.5
    end

    test "returns 0 for empty list" do
      assert PrmAggregation.sum_scores([]) == 0
    end

    test "returns 0 for single zero score" do
      assert PrmAggregation.sum_scores([0]) == 0
    end

    test "handles large scores" do
      assert PrmAggregation.sum_scores([100, 200, 300]) == 600
    end

    test "handles decimal precision" do
      result = PrmAggregation.sum_scores([0.1, 0.2, 0.3])
      assert_in_delta result, 0.6, 0.0001
    end
  end

  describe "product_scores/1" do
    test "returns product of scores" do
      result = PrmAggregation.product_scores([0.8, 0.9, 0.7])
      assert_in_delta result, 0.504, 0.001
    end

    test "returns 1 for empty list" do
      assert PrmAggregation.product_scores([]) == 1
    end

    test "returns 0 when any score is 0" do
      assert PrmAggregation.product_scores([0.8, 0.0, 0.9]) == 0
    end

    test "handles single score" do
      assert PrmAggregation.product_scores([0.5]) == 0.5
    end

    test "handles all 1s" do
      assert PrmAggregation.product_scores([1, 1, 1]) == 1
    end

    test "handles values less than 1" do
      result = PrmAggregation.product_scores([0.5, 0.5, 0.5])
      assert_in_delta result, 0.125, 0.001
    end
  end

  describe "min_score/1" do
    test "returns minimum score" do
      assert PrmAggregation.min_score([0.8, 0.9, 0.7]) == 0.7
    end

    test "returns nil for empty list" do
      assert PrmAggregation.min_score([]) == nil
    end

    test "handles negative scores" do
      assert PrmAggregation.min_score([0.8, -0.2, 0.9]) == -0.2
    end

    test "handles single score" do
      assert PrmAggregation.min_score([0.5]) == 0.5
    end

    test "handles all same scores" do
      assert PrmAggregation.min_score([0.8, 0.8, 0.8]) == 0.8
    end
  end

  describe "max_score/1" do
    test "returns maximum score" do
      assert PrmAggregation.max_score([0.8, 0.9, 0.7]) == 0.9
    end

    test "returns nil for empty list" do
      assert PrmAggregation.max_score([]) == nil
    end

    test "handles negative scores" do
      assert PrmAggregation.max_score([-0.8, -0.2, -0.9]) == -0.2
    end

    test "handles single score" do
      assert PrmAggregation.max_score([0.5]) == 0.5
    end

    test "handles all same scores" do
      assert PrmAggregation.max_score([0.8, 0.8, 0.8]) == 0.8
    end
  end

  describe "average_score/1" do
    test "returns arithmetic mean" do
      result = PrmAggregation.average_score([0.8, 0.9, 0.7])
      assert_in_delta result, 0.8, 0.001
    end

    test "returns nil for empty list" do
      assert PrmAggregation.average_score([]) == nil
    end

    test "handles two scores" do
      assert PrmAggregation.average_score([0.0, 1.0]) == 0.5
    end

    test "handles single score" do
      assert PrmAggregation.average_score([0.5]) == 0.5
    end

    test "handles mixed quality" do
      result = PrmAggregation.average_score([1.0, 0.0, 1.0])
      assert_in_delta result, 0.666, 0.001
    end

    test "handles all zeros" do
      assert PrmAggregation.average_score([0, 0, 0]) == 0
    end

    test "handles integer scores" do
      assert PrmAggregation.average_score([1, 2, 3, 4, 5]) == 3
    end
  end

  describe "weighted_average/2" do
    test "computes weighted average correctly" do
      result = PrmAggregation.weighted_average([0.8, 0.9, 0.7], [0.2, 0.3, 0.5])
      # 0.8 * 0.2 + 0.9 * 0.3 + 0.7 * 0.5 = 0.16 + 0.27 + 0.35 = 0.78
      assert_in_delta result, 0.78, 0.001
    end

    test "returns nil for empty scores" do
      assert PrmAggregation.weighted_average([], []) == nil
    end

    test "weights later steps more heavily" do
      # Later steps more important: [0.2, 0.3, 0.5]
      result_later = PrmAggregation.weighted_average([0.8, 0.9, 0.7], [0.2, 0.3, 0.5])

      # Earlier steps more important: [0.5, 0.3, 0.2]
      result_earlier = PrmAggregation.weighted_average([0.8, 0.9, 0.7], [0.5, 0.3, 0.2])

      # Later-weighted should be lower (0.7 has highest weight)
      # Earlier-weighted should be higher (0.8 has highest weight)
      assert result_earlier > result_later
    end

    test "handles uniform weights (same as average)" do
      scores = [0.8, 0.9, 0.7]
      uniform_weights = [1 / 3, 1 / 3, 1 / 3]

      result = PrmAggregation.weighted_average(scores, uniform_weights)
      expected = PrmAggregation.average_score(scores)

      assert_in_delta result, expected, 0.001
    end

    test "raises error when lengths don't match" do
      assert_raise ArgumentError, ~r/same length/, fn ->
        PrmAggregation.weighted_average([0.8, 0.9], [0.5, 0.3, 0.2])
      end
    end

    test "raises error when weights don't sum to 1" do
      assert_raise ArgumentError, ~r/sum to 1\.0/, fn ->
        PrmAggregation.weighted_average([0.8, 0.9, 0.7], [0.5, 0.5, 0.5])
      end
    end

    test "handles single score with weight 1.0" do
      assert PrmAggregation.weighted_average([0.8], [1.0]) == 0.8
    end

    test "handles extreme weighting (one step dominates)" do
      # First step gets all weight
      result = PrmAggregation.weighted_average([0.8, 0.0, 0.0], [1.0, 0.0, 0.0])
      assert result == 0.8
    end
  end

  describe "normalize_weights/1" do
    test "normalizes weights to sum to 1.0" do
      result = PrmAggregation.normalize_weights([2, 3, 5])
      assert result == [0.2, 0.3, 0.5]
    end

    test "normalizes uniform weights" do
      result = PrmAggregation.normalize_weights([1, 1, 1])

      assert Enum.all?(result, fn w -> w == 1 / 3 end)
    end

    test "returns empty list for empty input" do
      assert PrmAggregation.normalize_weights([]) == []
    end

    test "handles single weight" do
      assert PrmAggregation.normalize_weights([5]) == [1.0]
    end

    test "handles fractional weights" do
      result = PrmAggregation.normalize_weights([0.5, 0.5, 1.0])
      expected = [0.25, 0.25, 0.5]

      Enum.zip(result, expected)
      |> Enum.all?(fn {r, e} -> r == e end)
      |> assert()
    end

    test "handles all zeros by returning single zero" do
      result = PrmAggregation.normalize_weights([0, 0, 0])
      assert result == [0.0]
    end
  end

  describe "normalize_scores/2" do
    test "normalizes to 0-1 range" do
      result = PrmAggregation.normalize_scores([5, 8, 10], {0.0, 1.0})
      # 5 is min -> 0.0, 8 is 60% -> 0.6, 10 is max -> 1.0
      assert result == [0.0, 0.6, 1.0]
    end

    test "normalizes negative scores" do
      result = PrmAggregation.normalize_scores([-1, 0, 1], {0.0, 1.0})
      assert result == [0.0, 0.5, 1.0]
    end

    test "returns empty list for empty input" do
      assert PrmAggregation.normalize_scores([], {0.0, 1.0}) == []
    end

    test "handles single score" do
      result = PrmAggregation.normalize_scores([5], {0.0, 1.0})
      # Midpoint of target range
      assert result == [0.5]
    end

    test "handles all same scores" do
      result = PrmAggregation.normalize_scores([5, 5, 5], {0.0, 1.0})
      assert Enum.all?(result, fn s -> s == 0.5 end)
    end

    test "normalizes to custom range" do
      result = PrmAggregation.normalize_scores([1, 2, 3], {-1, 1})
      assert result == [-1.0, 0.0, 1.0]
    end

    test "preserves order when normalizing" do
      original = [1, 2, 3, 4, 5]
      result = PrmAggregation.normalize_scores(original, {0.0, 1.0})

      # Check that order is preserved (should be monotonic increasing)
      assert result == Enum.sort(result)
    end
  end

  describe "softmax/1" do
    test "computes softmax correctly" do
      result = PrmAggregation.softmax([1.0, 2.0, 3.0])

      # Check that they sum to 1
      assert_in_delta Enum.sum(result), 1.0, 0.0001

      # Check that higher input gets higher probability
      assert Enum.at(result, 2) > Enum.at(result, 1)
      assert Enum.at(result, 1) > Enum.at(result, 0)
    end

    test "returns empty list for empty input" do
      assert PrmAggregation.softmax([]) == []
    end

    test "returns uniform distribution for identical inputs" do
      result = PrmAggregation.softmax([1.0, 1.0, 1.0])

      assert Enum.all?(result, fn r -> r == 1 / 3 end)
    end

    test "handles single value" do
      assert PrmAggregation.softmax([5.0]) == [1.0]
    end

    test "handles negative values" do
      result = PrmAggregation.softmax([-1.0, 0.0, 1.0])

      assert_in_delta Enum.sum(result), 1.0, 0.0001
      # Highest value should have highest probability
      assert Enum.at(result, 2) == Enum.max(result)
    end

    test "handles very large values (numerical stability)" do
      result = PrmAggregation.softmax([1000.0, 2000.0, 3000.0])

      # Should not overflow and still sum to 1
      assert_in_delta Enum.sum(result), 1.0, 0.0001
    end
  end

  describe "edge cases" do
    test "handles mix of positive and zero scores with product" do
      assert PrmAggregation.product_scores([1.0, 0.0, 1.0]) == 0.0
    end

    test "handles very small scores with product" do
      result = PrmAggregation.product_scores([0.1, 0.1, 0.1])
      assert_in_delta result, 0.001, 0.0001
    end

    test "handles extreme values with sum" do
      result = PrmAggregation.sum_scores([1.0e10, 2.0e10, 3.0e10])
      assert_in_delta result, 6.0e10, 1.0e5
    end

    test "weighted_average handles very small weights" do
      result = PrmAggregation.weighted_average([0.8, 0.9, 0.7], [0.01, 0.98, 0.01])
      # Should be very close to 0.9 since it has 98% weight
      assert_in_delta result, 0.898, 0.01
    end
  end
end
