defmodule Jido.AI.Accuracy.ComputeBudgeterTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Accuracy.{ComputeBudget, ComputeBudgeter, DifficultyEstimate}

  doctest ComputeBudgeter

  describe "new/1" do
    test "creates budgeter with default settings" do
      assert {:ok, budgeter} = ComputeBudgeter.new(%{})
      assert budgeter.global_limit == nil
      assert budgeter.used_budget == 0.0
      assert budgeter.allocation_count == 0
    end

    test "creates budgeter with global limit" do
      assert {:ok, budgeter} = ComputeBudgeter.new(%{global_limit: 100.0})
      assert budgeter.global_limit == 100.0
    end

    test "creates budgeter with custom budgets" do
      custom_hard = ComputeBudget.new!(%{num_candidates: 15})
      assert {:ok, budgeter} = ComputeBudgeter.new(%{hard_budget: custom_hard})

      assert budgeter.hard_budget.num_candidates == 15
    end

    test "creates budgeter with custom allocations" do
      custom_budget = ComputeBudget.new!(%{num_candidates: 20})
      assert {:ok, budgeter} = ComputeBudgeter.new(%{custom_allocations: %{very_hard: custom_budget}})

      assert Map.get(budgeter.custom_allocations, :very_hard) == custom_budget
    end

    test "returns error for invalid global limit" do
      assert {:error, :invalid_global_limit} = ComputeBudgeter.new(%{global_limit: 0})
      assert {:error, :invalid_global_limit} = ComputeBudgeter.new(%{global_limit: -10})
    end

    test "returns error for invalid budget" do
      assert {:error, :invalid_budget} = ComputeBudgeter.new(%{easy_budget: "invalid"})
    end
  end

  describe "new!/1" do
    test "returns budgeter with valid settings" do
      budgeter = ComputeBudgeter.new!(%{global_limit: 100.0})
      assert budgeter.global_limit == 100.0
    end

    test "raises on invalid settings" do
      assert_raise ArgumentError, ~r/Invalid ComputeBudgeter/, fn ->
        ComputeBudgeter.new!(%{global_limit: -1})
      end
    end
  end

  describe "allocate/3 with difficulty estimate" do
    setup do
      {:ok, budgeter} = ComputeBudgeter.new(%{})
      {:ok, budgeter: budgeter}
    end

    test "allocates easy budget for easy difficulty", context do
      {:ok, estimate} = DifficultyEstimate.new(%{level: :easy, score: 0.2})
      assert {:ok, budget, updated_budgeter} = ComputeBudgeter.allocate(context.budgeter, estimate)

      assert budget.num_candidates == 3
      assert budget.use_prm == false
      assert updated_budgeter.used_budget == 3.0
      assert updated_budgeter.allocation_count == 1
    end

    test "allocates medium budget for medium difficulty", context do
      {:ok, estimate} = DifficultyEstimate.new(%{level: :medium, score: 0.5})
      assert {:ok, budget, updated_budgeter} = ComputeBudgeter.allocate(context.budgeter, estimate)

      assert budget.num_candidates == 5
      assert budget.use_prm == true
      assert_in_delta updated_budgeter.used_budget, 8.5, 0.01
      assert updated_budgeter.allocation_count == 1
    end

    test "allocates hard budget for hard difficulty", context do
      {:ok, estimate} = DifficultyEstimate.new(%{level: :hard, score: 0.8})
      assert {:ok, budget, updated_budgeter} = ComputeBudgeter.allocate(context.budgeter, estimate)

      assert budget.num_candidates == 10
      assert budget.use_prm == true
      assert budget.use_search == true
      assert_in_delta updated_budgeter.used_budget, 17.5, 0.01
      assert updated_budgeter.allocation_count == 1
    end
  end

  describe "allocate/3 with level atom" do
    setup do
      {:ok, budgeter} = ComputeBudgeter.new(%{})
      {:ok, budgeter: budgeter}
    end

    test "allocates easy budget for :easy", context do
      assert {:ok, budget, updated_budgeter} = ComputeBudgeter.allocate(context.budgeter, :easy)

      assert budget.num_candidates == 3
      assert budget.use_prm == false
      assert updated_budgeter.used_budget == 3.0
    end

    test "allocates medium budget for :medium", context do
      assert {:ok, budget, updated_budgeter} = ComputeBudgeter.allocate(context.budgeter, :medium)

      assert budget.num_candidates == 5
      assert budget.use_prm == true
      assert_in_delta updated_budgeter.used_budget, 8.5, 0.01
    end

    test "allocates hard budget for :hard", context do
      assert {:ok, budget, updated_budgeter} = ComputeBudgeter.allocate(context.budgeter, :hard)

      assert budget.num_candidates == 10
      assert budget.use_prm == true
      assert budget.use_search == true
      assert_in_delta updated_budgeter.used_budget, 17.5, 0.01
    end
  end

  describe "allocate_for_easy/1" do
    test "allocates easy budget" do
      {:ok, budgeter} = ComputeBudgeter.new(%{})
      assert {:ok, budget, updated} = ComputeBudgeter.allocate_for_easy(budgeter)

      assert budget.num_candidates == 3
      assert updated.used_budget == 3.0
    end
  end

  describe "allocate_for_medium/1" do
    test "allocates medium budget" do
      {:ok, budgeter} = ComputeBudgeter.new(%{})
      assert {:ok, budget, updated} = ComputeBudgeter.allocate_for_medium(budgeter)

      assert budget.num_candidates == 5
      assert budget.use_prm == true
      assert_in_delta updated.used_budget, 8.5, 0.01
    end
  end

  describe "allocate_for_hard/1" do
    test "allocates hard budget" do
      {:ok, budgeter} = ComputeBudgeter.new(%{})
      assert {:ok, budget, updated} = ComputeBudgeter.allocate_for_hard(budgeter)

      assert budget.num_candidates == 10
      assert budget.use_prm == true
      assert budget.use_search == true
      assert_in_delta updated.used_budget, 17.5, 0.01
    end
  end

  describe "custom_allocation/3" do
    setup do
      {:ok, budgeter} = ComputeBudgeter.new(%{})
      {:ok, budgeter: budgeter}
    end

    test "allocates custom number of candidates", context do
      assert {:ok, budget, updated} = ComputeBudgeter.custom_allocation(context.budgeter, 7, [])

      assert budget.num_candidates == 7
      assert budget.use_prm == false
      assert updated.used_budget == 7.0
    end

    test "allocates with PRM enabled", context do
      assert {:ok, budget, updated} =
               ComputeBudgeter.custom_allocation(context.budgeter, 7, use_prm: true)

      assert budget.num_candidates == 7
      assert budget.use_prm == true
      assert_in_delta updated.used_budget, 10.5, 0.01
    end

    test "allocates with search enabled", context do
      assert {:ok, budget, updated} =
               ComputeBudgeter.custom_allocation(context.budgeter, 7, use_search: true)

      assert budget.num_candidates == 7
      assert budget.use_search == true
      # 7 (candidates) + 0.5 (search) = 7.5
      assert_in_delta updated.used_budget, 7.5, 0.01
    end

    test "allocates with refinements", context do
      assert {:ok, budget, updated} =
               ComputeBudgeter.custom_allocation(context.budgeter, 7, max_refinements: 3)

      assert budget.max_refinements == 3
      assert updated.used_budget == 10.0
    end

    test "allocates with all options", context do
      assert {:ok, budget, updated} =
               ComputeBudgeter.custom_allocation(context.budgeter, 10,
                 use_prm: true,
                 use_search: true,
                 max_refinements: 2,
                 search_iterations: 100
               )

      assert budget.num_candidates == 10
      assert budget.use_prm == true
      assert budget.use_search == true
      # 10 (candidates) + 5 (PRM) + 1 (search) + 2 (refinements) = 18.0
      assert_in_delta updated.used_budget, 18.0, 0.01
    end

    test "returns error for invalid num_candidates", context do
      assert {:error, :invalid_num_candidates} =
               ComputeBudgeter.custom_allocation(context.budgeter, 0, [])
    end
  end

  describe "global limit enforcement" do
    test "prevents allocation when limit would be exceeded" do
      {:ok, budgeter} = ComputeBudgeter.new(%{global_limit: 10.0})

      # First allocation (easy: 3.0)
      assert {:ok, _budget, budgeter} = ComputeBudgeter.allocate_for_easy(budgeter)

      # Second allocation (easy: 3.0)
      assert {:ok, _budget, budgeter} = ComputeBudgeter.allocate_for_easy(budgeter)

      # Third allocation would exceed limit (3.0 + 3.0 + 3.0 = 9.0, still OK)
      assert {:ok, _budget, budgeter} = ComputeBudgeter.allocate_for_easy(budgeter)

      # Used: 9.0, remaining: 1.0
      # Hard allocation (17.5) would exceed
      assert {:error, :budget_exhausted} = ComputeBudgeter.allocate_for_hard(budgeter)
    end

    test "allows allocation within limit" do
      {:ok, budgeter} = ComputeBudgeter.new(%{global_limit: 20.0})

      # Easy: 3.0
      assert {:ok, _, budgeter} = ComputeBudgeter.allocate_for_easy(budgeter)

      # Used: 3.0, remaining: 17.0
      # Medium: 8.5
      assert {:ok, _, budgeter} = ComputeBudgeter.allocate_for_medium(budgeter)

      # Used: 11.5, remaining: 8.5
      # Another medium: 8.5 would exactly hit limit
      assert {:ok, _, budgeter} = ComputeBudgeter.allocate_for_medium(budgeter)

      # Used: 20.0, exactly at limit
      assert ComputeBudgeter.budget_exhausted?(budgeter) == true
    end

    test "custom allocation respects limit" do
      {:ok, budgeter} = ComputeBudgeter.new(%{global_limit: 15.0})

      # Custom: 10 candidates = 10.0
      assert {:ok, _, budgeter} = ComputeBudgeter.custom_allocation(budgeter, 10, [])

      # Used: 10.0, remaining: 5.0
      # Custom: 7 candidates = 7.0 would exceed
      assert {:error, :budget_exhausted} = ComputeBudgeter.custom_allocation(budgeter, 7, [])
    end
  end

  describe "check_budget/2" do
    test "returns :within_limit for sufficient budget" do
      {:ok, budgeter} = ComputeBudgeter.new(%{global_limit: 100.0})
      assert {:ok, :within_limit} = ComputeBudgeter.check_budget(budgeter, 50.0)
    end

    test "returns :would_exceed_limit for insufficient budget" do
      {:ok, budgeter} = ComputeBudgeter.new(%{global_limit: 20.0})

      # Hard allocation (17.5) succeeds
      assert {:ok, _, budgeter} = ComputeBudgeter.allocate_for_hard(budgeter)
      # Remaining: 2.5
      assert {:ok, :within_limit} = ComputeBudgeter.check_budget(budgeter, 2.0)
      assert {:error, :would_exceed_limit} = ComputeBudgeter.check_budget(budgeter, 3.0)
    end

    test "always returns :within_limit when no global limit" do
      {:ok, budgeter} = ComputeBudgeter.new(%{})
      assert {:ok, :within_limit} = ComputeBudgeter.check_budget(budgeter, 1_000_000.0)
    end
  end

  describe "remaining_budget/1" do
    test "returns infinity when no global limit" do
      {:ok, budgeter} = ComputeBudgeter.new(%{})
      assert {:ok, :infinity} = ComputeBudgeter.remaining_budget(budgeter)
    end

    test "returns remaining budget when limit set" do
      {:ok, budgeter} = ComputeBudgeter.new(%{global_limit: 100.0})
      assert {:ok, _, budgeter} = ComputeBudgeter.allocate_for_medium(budgeter)

      assert {:ok, remaining} = ComputeBudgeter.remaining_budget(budgeter)
      assert_in_delta remaining, 91.5, 0.01
    end

    test "returns zero when budget exhausted" do
      {:ok, budgeter} = ComputeBudgeter.new(%{global_limit: 3.0})
      assert {:ok, _, budgeter} = ComputeBudgeter.allocate_for_easy(budgeter)

      assert {:ok, remaining} = ComputeBudgeter.remaining_budget(budgeter)
      assert remaining == 0.0
    end
  end

  describe "budget_exhausted?/1" do
    test "returns false when no global limit" do
      {:ok, budgeter} = ComputeBudgeter.new(%{})
      assert ComputeBudgeter.budget_exhausted?(budgeter) == false
    end

    test "returns false when budget available" do
      {:ok, budgeter} = ComputeBudgeter.new(%{global_limit: 100.0})
      assert ComputeBudgeter.budget_exhausted?(budgeter) == false
    end

    test "returns false when partially used" do
      {:ok, budgeter} = ComputeBudgeter.new(%{global_limit: 100.0})
      assert {:ok, _, budgeter} = ComputeBudgeter.allocate_for_easy(budgeter)

      assert ComputeBudgeter.budget_exhausted?(budgeter) == false
    end

    test "returns true when budget exhausted" do
      {:ok, budgeter} = ComputeBudgeter.new(%{global_limit: 3.0})
      assert {:ok, _, budgeter} = ComputeBudgeter.allocate_for_easy(budgeter)

      assert ComputeBudgeter.budget_exhausted?(budgeter) == true
    end
  end

  describe "track_usage/2" do
    test "tracks usage without allocation" do
      {:ok, budgeter} = ComputeBudgeter.new(%{})
      updated = ComputeBudgeter.track_usage(budgeter, 5.0)

      assert updated.used_budget == 5.0
      assert updated.allocation_count == 0
    end
  end

  describe "reset_budget/1" do
    test "resets budget tracking" do
      {:ok, budgeter} = ComputeBudgeter.new(%{global_limit: 100.0})
      assert {:ok, _, budgeter} = ComputeBudgeter.allocate_for_hard(budgeter)
      assert {:ok, _, budgeter} = ComputeBudgeter.allocate_for_medium(budgeter)

      assert budgeter.used_budget > 0
      assert budgeter.allocation_count == 2

      reset = ComputeBudgeter.reset_budget(budgeter)
      assert reset.used_budget == 0.0
      assert reset.allocation_count == 0
      assert reset.global_limit == 100.0
    end
  end

  describe "get_usage_stats/1" do
    test "returns usage statistics" do
      {:ok, budgeter} = ComputeBudgeter.new(%{global_limit: 100.0})
      assert {:ok, _, budgeter} = ComputeBudgeter.allocate_for_easy(budgeter)
      assert {:ok, _, budgeter} = ComputeBudgeter.allocate_for_medium(budgeter)

      stats = ComputeBudgeter.get_usage_stats(budgeter)

      assert_in_delta stats.used_budget, 11.5, 0.01
      assert stats.allocation_count == 2
      assert_in_delta stats.average_cost, 5.75, 0.01
      assert_in_delta stats.remaining_budget, 88.5, 0.01
    end

    test "returns infinity for remaining when no limit" do
      {:ok, budgeter} = ComputeBudgeter.new(%{})
      assert {:ok, _, budgeter} = ComputeBudgeter.allocate_for_easy(budgeter)

      stats = ComputeBudgeter.get_usage_stats(budgeter)
      assert stats.remaining_budget == :infinity
    end

    test "returns zero average cost when no allocations" do
      {:ok, budgeter} = ComputeBudgeter.new(%{})
      stats = ComputeBudgeter.get_usage_stats(budgeter)

      assert stats.average_cost == 0.0
    end
  end

  describe "budget_for_level/2" do
    test "returns easy budget for :easy" do
      {:ok, budgeter} = ComputeBudgeter.new(%{})
      budget = ComputeBudgeter.budget_for_level(budgeter, :easy)

      assert budget.num_candidates == 3
      assert budget.use_prm == false
    end

    test "returns medium budget for :medium" do
      {:ok, budgeter} = ComputeBudgeter.new(%{})
      budget = ComputeBudgeter.budget_for_level(budgeter, :medium)

      assert budget.num_candidates == 5
      assert budget.use_prm == true
    end

    test "returns hard budget for :hard" do
      {:ok, budgeter} = ComputeBudgeter.new(%{})
      budget = ComputeBudgeter.budget_for_level(budgeter, :hard)

      assert budget.num_candidates == 10
      assert budget.use_prm == true
      assert budget.use_search == true
    end

    test "returns custom budget when configured" do
      custom_hard = ComputeBudget.new!(%{num_candidates: 15})
      {:ok, budgeter} = ComputeBudgeter.new(%{hard_budget: custom_hard})

      budget = ComputeBudgeter.budget_for_level(budgeter, :hard)
      assert budget.num_candidates == 15
    end
  end

  describe "custom allocation levels" do
    test "allocates custom level from custom_allocations" do
      custom_budget = ComputeBudget.new!(%{num_candidates: 20})
      {:ok, budgeter} = ComputeBudgeter.new(%{custom_allocations: %{very_hard: custom_budget}})

      assert {:ok, budget, updated} = ComputeBudgeter.allocate(budgeter, :very_hard)
      assert budget.num_candidates == 20
      assert updated.used_budget == 20.0
    end

    test "returns error for unknown custom level" do
      {:ok, budgeter} = ComputeBudgeter.new(%{})
      assert {:error, {:unknown_level, :unknown}} = ComputeBudgeter.allocate(budgeter, :unknown)
    end

    test "respects global limit for custom allocations" do
      custom_budget = ComputeBudget.new!(%{num_candidates: 20})
      {:ok, budgeter} = ComputeBudgeter.new(%{global_limit: 15.0, custom_allocations: %{very_hard: custom_budget}})

      assert {:error, :budget_exhausted} = ComputeBudgeter.allocate(budgeter, :very_hard)
    end
  end

  describe "accumulation tracking" do
    test "accumulates budget across multiple allocations" do
      {:ok, budgeter} = ComputeBudgeter.new(%{})

      assert {:ok, _, budgeter} = ComputeBudgeter.allocate_for_easy(budgeter)
      assert budgeter.allocation_count == 1

      assert {:ok, _, budgeter} = ComputeBudgeter.allocate_for_medium(budgeter)
      assert budgeter.allocation_count == 2

      assert {:ok, _, budgeter} = ComputeBudgeter.allocate_for_hard(budgeter)
      assert budgeter.allocation_count == 3

      assert_in_delta budgeter.used_budget, 29.0, 0.01
    end

    test "tracks individual allocation costs" do
      {:ok, budgeter} = ComputeBudgeter.new(%{global_limit: 100.0})

      # Track each allocation
      assert {:ok, b1, budgeter} = ComputeBudgeter.allocate_for_easy(budgeter)
      assert ComputeBudget.cost(b1) == 3.0

      assert {:ok, b2, budgeter} = ComputeBudgeter.allocate_for_medium(budgeter)
      assert_in_delta ComputeBudget.cost(b2), 8.5, 0.01

      assert {:ok, b3, budgeter} = ComputeBudgeter.allocate_for_hard(budgeter)
      assert_in_delta ComputeBudget.cost(b3), 17.5, 0.01

      # Total should match sum
      assert_in_delta budgeter.used_budget, 29.0, 0.01
    end
  end
end
