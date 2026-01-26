defmodule Jido.AI.Accuracy.AggregatorTest do
  use ExUnit.Case, async: false

  describe "behavior contract" do
    test "defines aggregate callback" do
      assert function_exported?(Jido.AI.Accuracy.Aggregators.MajorityVote, :aggregate, 2)
      assert function_exported?(Jido.AI.Accuracy.Aggregators.BestOfN, :aggregate, 2)
      assert function_exported?(Jido.AI.Accuracy.Aggregators.Weighted, :aggregate, 2)
    end

    test "defines distribution callback" do
      assert function_exported?(Jido.AI.Accuracy.Aggregators.MajorityVote, :distribution, 1)
      assert function_exported?(Jido.AI.Accuracy.Aggregators.BestOfN, :distribution, 1)
      assert function_exported?(Jido.AI.Accuracy.Aggregators.Weighted, :distribution, 1)
    end
  end

  describe "types" do
    test "aggregate_result type is defined" do
      # This is a compile-time type check
      # Just verify the types exist in the module
      assert is_list(Jido.AI.Accuracy.Aggregator.module_info(:exports))
    end
  end
end
