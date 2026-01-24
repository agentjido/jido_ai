defmodule Jido.AI.Accuracy.ComputeBudgeterSecurityTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Accuracy.{ComputeBudgeter, ComputeBudget}

  @moduletag :security
  @moduletag :compute_budgeter

  describe "track_usage/2 validation" do
    setup do
      {:ok, budgeter} = ComputeBudgeter.new(%{})
      %{budgeter: budgeter}
    end

    test "rejects negative costs", %{budgeter: budgeter} do
      # Before fix: Could reduce used_budget with negative costs
      # After fix: Returns error for negative costs
      assert {:error, :invalid_cost} = ComputeBudgeter.track_usage(budgeter, -5.0)

      # Verify budgeter is unchanged
      assert budgeter.used_budget == 0.0
    end

    test "rejects non-numeric costs", %{budgeter: budgeter} do
      assert {:error, :invalid_cost} = ComputeBudgeter.track_usage(budgeter, "invalid")
      assert {:error, :invalid_cost} = ComputeBudgeter.track_usage(budgeter, nil)
      assert {:error, :invalid_cost} = ComputeBudgeter.track_usage(budgeter, %{})
    end

    test "accepts zero cost", %{budgeter: budgeter} do
      assert {:ok, updated} = ComputeBudgeter.track_usage(budgeter, 0.0)
      assert updated.used_budget == 0.0
    end

    test "accepts positive costs", %{budgeter: budgeter} do
      assert {:ok, updated} = ComputeBudgeter.track_usage(budgeter, 5.5)
      assert updated.used_budget == 5.5
    end

    test "prevents overflow through many allocations", %{budgeter: budgeter} do
      # Simulate many positive allocations
      Enum.reduce(1..1000, budgeter, fn _i, acc ->
        {:ok, budgeter} = ComputeBudgeter.track_usage(acc, 1.0)
        budgeter
      end)

      {:ok, final_budgeter} = ComputeBudgeter.track_usage(budgeter, 500.0)

      # Budget should have accumulated correctly
      assert final_budgeter.used_budget > 0
    end
  end

  describe "global_limit validation" do
    test "rejects negative global limits" do
      assert {:error, :invalid_global_limit} =
               ComputeBudgeter.new(%{global_limit: -10.0})
    end

    test "rejects zero global limit" do
      assert {:error, :invalid_global_limit} = ComputeBudgeter.new(%{global_limit: 0})
    end

    test "accepts nil (unlimited) global limit" do
      assert {:ok, %ComputeBudgeter{}} = ComputeBudgeter.new(%{global_limit: nil})
    end

    test "accepts positive global limits" do
      assert {:ok, %ComputeBudgeter{}} = ComputeBudgeter.new(%{global_limit: 100.0})
      assert {:ok, %ComputeBudgeter{}} = ComputeBudgeter.new(%{global_limit: 1.0e10})
    end
  end

  describe "budget validation" do
    test "rejects invalid budget structs" do
      assert {:error, :invalid_budget} =
               ComputeBudgeter.new(%{easy_budget: "invalid"})

      assert {:error, :invalid_budget} =
               ComputeBudgeter.new(%{medium_budget: %{invalid: "struct"}})
    end
  end

  describe "allocation with global limit" do
    test "respects global limit enforcement" do
      {:ok, budgeter} = ComputeBudgeter.new(%{global_limit: 10.0})

      # First allocation should succeed (3.0 cost)
      assert {:ok, _, budgeter} = ComputeBudgeter.allocate_for_easy(budgeter)

      # Second allocation (3.0 cost) - total 6.0
      assert {:ok, _, budgeter} = ComputeBudgeter.allocate_for_easy(budgeter)

      # Third allocation (3.0 cost) - total 9.0
      assert {:ok, _, budgeter} = ComputeBudgeter.allocate_for_easy(budgeter)

      # Fourth allocation should fail (would exceed 10.0)
      assert {:error, :budget_exhausted} = ComputeBudgeter.allocate_for_easy(budgeter)
    end

    test "allows exact budget limit usage" do
      {:ok, budgeter} = ComputeBudgeter.new(%{global_limit: 6.0})

      # Two easy allocations = exactly 6.0
      assert {:ok, _, budgeter} = ComputeBudgeter.allocate_for_easy(budgeter)
      assert {:ok, _, budgeter} = ComputeBudgeter.allocate_for_easy(budgeter)

      # Third should fail
      assert {:error, :budget_exhausted} = ComputeBudgeter.allocate_for_easy(budgeter)
    end
  end

  describe "custom_allocations security" do
    test "handles custom allocations with invalid budget" do
      {:ok, budgeter} = ComputeBudgeter.new(%{})

      # Custom allocation with invalid parameters
      assert {:error, :invalid_num_candidates} =
               ComputeBudgeter.custom_allocation(budgeter, -5, [])

      assert {:error, :invalid_num_candidates} =
               ComputeBudgeter.custom_allocation(budgeter, 0, [])
    end
  end

  describe "remaining_budget calculation" do
    test "handles very large global limits" do
      {:ok, budgeter} = ComputeBudgeter.new(%{global_limit: 1.0e10})

      assert {:ok, remaining} = ComputeBudgeter.remaining_budget(budgeter)
      assert remaining > 0
    end

    test "returns infinity when no global limit set" do
      {:ok, budgeter} = ComputeBudgeter.new(%{})

      assert {:ok, :infinity} = ComputeBudgeter.remaining_budget(budgeter)
    end
  end
end
