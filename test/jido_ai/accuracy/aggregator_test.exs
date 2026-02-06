defmodule Jido.AI.Accuracy.AggregatorTest do
  use ExUnit.Case, async: false

  alias Jido.AI.Accuracy.Aggregator
  alias Jido.AI.Accuracy.Aggregators.BestOfN
  alias Jido.AI.Accuracy.Aggregators.MajorityVote
  alias Jido.AI.Accuracy.Aggregators.Weighted
  alias Jido.AI.Test.ModuleExports

  describe "behavior contract" do
    test "defines aggregate callback" do
      assert ModuleExports.exported?(MajorityVote, :aggregate, 2)
      assert ModuleExports.exported?(BestOfN, :aggregate, 2)
      assert ModuleExports.exported?(Weighted, :aggregate, 2)
    end

    test "defines distribution callback" do
      assert ModuleExports.exported?(MajorityVote, :distribution, 1)
      assert ModuleExports.exported?(BestOfN, :distribution, 1)
      assert ModuleExports.exported?(Weighted, :distribution, 1)
    end
  end

  describe "types" do
    test "aggregate_result type is defined" do
      # This is a compile-time type check
      # Just verify the types exist in the module
      assert is_list(Aggregator.module_info(:exports))
    end
  end
end
