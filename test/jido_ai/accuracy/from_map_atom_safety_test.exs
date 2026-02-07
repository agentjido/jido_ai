defmodule Jido.AI.Accuracy.FromMapAtomSafetyTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Accuracy.{
    ConfidenceEstimate,
    DecisionResult,
    DifficultyEstimate,
    RoutingResult,
    UncertaintyResult
  }

  test "DecisionResult.from_map/1 does not create atoms for unknown keys" do
    assert_no_atom_creation(fn key ->
      assert {:ok, _result} = DecisionResult.from_map(%{"decision" => "answer", key => "value"})
    end)
  end

  test "RoutingResult.from_map/1 does not create atoms for unknown keys" do
    assert_no_atom_creation(fn key ->
      assert {:ok, _result} = RoutingResult.from_map(%{"action" => "direct", key => "value"})
    end)
  end

  test "ConfidenceEstimate.from_map/1 does not create atoms for unknown keys" do
    assert_no_atom_creation(fn key ->
      assert {:ok, _result} = ConfidenceEstimate.from_map(%{"score" => 0.9, "method" => "test", key => "value"})
    end)
  end

  test "UncertaintyResult.from_map/1 does not create atoms for unknown keys" do
    assert_no_atom_creation(fn key ->
      assert {:ok, _result} = UncertaintyResult.from_map(%{"uncertainty_type" => "none", key => "value"})
    end)
  end

  test "DifficultyEstimate.from_map/1 does not create atoms for unknown keys" do
    assert_no_atom_creation(fn key ->
      assert {:ok, _result} = DifficultyEstimate.from_map(%{"score" => 0.5, key => "value"})
    end)
  end

  defp assert_no_atom_creation(fun) do
    key = "unknown_key_#{System.unique_integer([:positive])}"

    assert_raise ArgumentError, fn ->
      String.to_existing_atom(key)
    end

    fun.(key)

    assert_raise ArgumentError, fn ->
      String.to_existing_atom(key)
    end
  end
end
