defmodule Jido.AI.Runner.GEPA.Convergence.BudgetManagerTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Runner.GEPA.Convergence.BudgetManager

  describe "new/1" do
    test "creates manager with default configuration" do
      manager = BudgetManager.new()

      assert manager.max_evaluations == nil
      assert manager.max_cost == nil
      assert manager.max_generations == nil
      assert manager.max_time_seconds == nil
      assert manager.budget_per_generation == nil
      assert manager.allow_carryover == false
      assert manager.budget_exhausted == false
      assert manager.evaluations_consumed == 0
      assert manager.cost_consumed == 0.0
      assert manager.time_consumed == 0.0
      assert manager.current_generation == 0
      assert manager.consumption_history == []
    end

    test "accepts custom configuration" do
      manager =
        BudgetManager.new(
          max_evaluations: 1000,
          max_cost: 10.0,
          max_generations: 50,
          max_time_seconds: 3600.0
        )

      assert manager.max_evaluations == 1000
      assert manager.max_cost == 10.0
      assert manager.max_generations == 50
      assert manager.max_time_seconds == 3600.0
    end

    test "accepts per-generation budget configuration" do
      manager =
        BudgetManager.new(
          budget_per_generation: 50,
          allow_carryover: true
        )

      assert manager.budget_per_generation == 50
      assert manager.allow_carryover == true
    end

    test "stores configuration in config field" do
      manager = BudgetManager.new(custom_param: :value)

      assert manager.config[:custom_param] == :value
    end

    test "initializes start_time" do
      manager = BudgetManager.new()

      assert manager.start_time != nil
      assert DateTime.compare(manager.start_time, DateTime.utc_now()) in [:lt, :eq]
    end
  end

  describe "record_consumption/2" do
    test "records evaluation consumption" do
      manager = BudgetManager.new()
      manager = BudgetManager.record_consumption(manager, evaluations: 10)

      assert manager.evaluations_consumed == 10
      assert manager.current_generation == 1
      assert length(manager.consumption_history) == 1
    end

    test "records cost consumption" do
      manager = BudgetManager.new()
      manager = BudgetManager.record_consumption(manager, cost: 2.5)

      assert manager.cost_consumed == 2.5
    end

    test "records time consumption" do
      manager = BudgetManager.new()
      manager = BudgetManager.record_consumption(manager, time_elapsed: 120.5)

      assert manager.time_consumed == 120.5
    end

    test "records multiple consumption types together" do
      manager = BudgetManager.new()

      manager =
        BudgetManager.record_consumption(manager,
          evaluations: 10,
          cost: 0.5,
          time_elapsed: 30.0
        )

      assert manager.evaluations_consumed == 10
      assert manager.cost_consumed == 0.5
      assert manager.time_consumed == 30.0
    end

    test "accumulates consumption across multiple calls" do
      manager = BudgetManager.new()

      manager =
        manager
        |> BudgetManager.record_consumption(evaluations: 10, cost: 0.5)
        |> BudgetManager.record_consumption(evaluations: 15, cost: 0.8)
        |> BudgetManager.record_consumption(evaluations: 5, cost: 0.2)

      assert manager.evaluations_consumed == 30
      assert_in_delta manager.cost_consumed, 1.5, 0.001
      assert manager.current_generation == 3
    end

    test "maintains history in reverse chronological order" do
      manager = BudgetManager.new()

      manager =
        manager
        |> BudgetManager.record_consumption(evaluations: 10)
        |> BudgetManager.record_consumption(evaluations: 20)
        |> BudgetManager.record_consumption(evaluations: 30)

      assert length(manager.consumption_history) == 3
      assert hd(manager.consumption_history).generation == 3
      assert hd(manager.consumption_history).evaluations == 30
    end

    test "trims history to max_history size" do
      manager = BudgetManager.new(max_history: 3)

      manager =
        Enum.reduce(1..5, manager, fn gen, acc ->
          BudgetManager.record_consumption(acc, evaluations: gen * 10)
        end)

      assert length(manager.consumption_history) == 3
      assert hd(manager.consumption_history).generation == 5
      assert Enum.at(manager.consumption_history, -1).generation == 3
    end

    test "accepts explicit generation number" do
      manager = BudgetManager.new()
      manager = BudgetManager.record_consumption(manager, evaluations: 10, generation: 42)

      assert manager.current_generation == 42
      assert hd(manager.consumption_history).generation == 42
    end
  end

  describe "budget exhaustion detection - evaluations" do
    test "does not exhaust budget when under limit" do
      manager = BudgetManager.new(max_evaluations: 100)
      manager = BudgetManager.record_consumption(manager, evaluations: 50)

      refute BudgetManager.budget_exhausted?(manager)
    end

    test "exhausts budget when limit reached" do
      manager = BudgetManager.new(max_evaluations: 100)
      manager = BudgetManager.record_consumption(manager, evaluations: 100)

      assert BudgetManager.budget_exhausted?(manager)
    end

    test "exhausts budget when limit exceeded" do
      manager = BudgetManager.new(max_evaluations: 100)
      manager = BudgetManager.record_consumption(manager, evaluations: 150)

      assert BudgetManager.budget_exhausted?(manager)
    end

    test "gradually exhausts budget over multiple consumptions" do
      manager = BudgetManager.new(max_evaluations: 100)

      manager =
        manager
        |> BudgetManager.record_consumption(evaluations: 30)
        |> BudgetManager.record_consumption(evaluations: 30)

      refute BudgetManager.budget_exhausted?(manager)

      manager = BudgetManager.record_consumption(manager, evaluations: 40)

      assert BudgetManager.budget_exhausted?(manager)
    end
  end

  describe "budget exhaustion detection - cost" do
    test "does not exhaust budget when under cost limit" do
      manager = BudgetManager.new(max_cost: 10.0)
      manager = BudgetManager.record_consumption(manager, cost: 5.0)

      refute BudgetManager.budget_exhausted?(manager)
    end

    test "exhausts budget when cost limit reached" do
      manager = BudgetManager.new(max_cost: 10.0)
      manager = BudgetManager.record_consumption(manager, cost: 10.0)

      assert BudgetManager.budget_exhausted?(manager)
    end

    test "exhausts budget when cost limit exceeded" do
      manager = BudgetManager.new(max_cost: 10.0)
      manager = BudgetManager.record_consumption(manager, cost: 15.0)

      assert BudgetManager.budget_exhausted?(manager)
    end
  end

  describe "budget exhaustion detection - generations" do
    test "does not exhaust budget when under generation limit" do
      manager = BudgetManager.new(max_generations: 50)

      manager =
        Enum.reduce(1..30, manager, fn _gen, acc ->
          BudgetManager.record_consumption(acc, evaluations: 10)
        end)

      refute BudgetManager.budget_exhausted?(manager)
    end

    test "exhausts budget when generation limit reached" do
      manager = BudgetManager.new(max_generations: 50)

      manager =
        Enum.reduce(1..50, manager, fn _gen, acc ->
          BudgetManager.record_consumption(acc, evaluations: 10)
        end)

      assert BudgetManager.budget_exhausted?(manager)
    end

    test "exhausts budget when generation limit exceeded" do
      manager = BudgetManager.new(max_generations: 50)

      manager =
        Enum.reduce(1..60, manager, fn _gen, acc ->
          BudgetManager.record_consumption(acc, evaluations: 10)
        end)

      assert BudgetManager.budget_exhausted?(manager)
    end
  end

  describe "budget exhaustion detection - time" do
    test "does not exhaust budget when under time limit" do
      manager = BudgetManager.new(max_time_seconds: 3600.0)
      manager = BudgetManager.record_consumption(manager, time_elapsed: 1800.0)

      refute BudgetManager.budget_exhausted?(manager)
    end

    test "exhausts budget when time limit reached" do
      manager = BudgetManager.new(max_time_seconds: 3600.0)
      manager = BudgetManager.record_consumption(manager, time_elapsed: 3600.0)

      assert BudgetManager.budget_exhausted?(manager)
    end

    test "exhausts budget when time limit exceeded" do
      manager = BudgetManager.new(max_time_seconds: 3600.0)
      manager = BudgetManager.record_consumption(manager, time_elapsed: 4000.0)

      assert BudgetManager.budget_exhausted?(manager)
    end
  end

  describe "budget exhaustion - multiple limits" do
    test "exhausts when any limit reached" do
      manager =
        BudgetManager.new(
          max_evaluations: 1000,
          max_cost: 10.0,
          max_generations: 50
        )

      # Exhaust cost first
      manager = BudgetManager.record_consumption(manager, evaluations: 100, cost: 10.0)

      assert BudgetManager.budget_exhausted?(manager)
      assert manager.evaluations_consumed < manager.max_evaluations
    end

    test "does not exhaust until any limit reached" do
      manager =
        BudgetManager.new(
          max_evaluations: 1000,
          max_cost: 10.0,
          max_generations: 50
        )

      manager =
        Enum.reduce(1..30, manager, fn _gen, acc ->
          BudgetManager.record_consumption(acc, evaluations: 20, cost: 0.2)
        end)

      # 600 evaluations, 6.0 cost, 30 generations - none exhausted
      refute BudgetManager.budget_exhausted?(manager)
    end
  end

  describe "remaining budget queries" do
    test "remaining_evaluations/1 returns correct value" do
      manager = BudgetManager.new(max_evaluations: 100)
      assert BudgetManager.remaining_evaluations(manager) == 100

      manager = BudgetManager.record_consumption(manager, evaluations: 30)
      assert BudgetManager.remaining_evaluations(manager) == 70

      manager = BudgetManager.record_consumption(manager, evaluations: 70)
      assert BudgetManager.remaining_evaluations(manager) == 0
    end

    test "remaining_evaluations/1 returns :unlimited when no limit" do
      manager = BudgetManager.new()
      assert BudgetManager.remaining_evaluations(manager) == :unlimited
    end

    test "remaining_cost/1 returns correct value" do
      manager = BudgetManager.new(max_cost: 10.0)
      assert BudgetManager.remaining_cost(manager) == 10.0

      manager = BudgetManager.record_consumption(manager, cost: 3.5)
      assert_in_delta BudgetManager.remaining_cost(manager), 6.5, 0.001

      manager = BudgetManager.record_consumption(manager, cost: 6.5)
      assert_in_delta BudgetManager.remaining_cost(manager), 0.0, 0.001
    end

    test "remaining_cost/1 returns :unlimited when no limit" do
      manager = BudgetManager.new()
      assert BudgetManager.remaining_cost(manager) == :unlimited
    end

    test "remaining_generations/1 returns correct value" do
      manager = BudgetManager.new(max_generations: 50)
      assert BudgetManager.remaining_generations(manager) == 50

      manager = BudgetManager.record_consumption(manager, evaluations: 10)
      assert BudgetManager.remaining_generations(manager) == 49

      manager =
        Enum.reduce(1..49, manager, fn _gen, acc ->
          BudgetManager.record_consumption(acc, evaluations: 10)
        end)

      assert BudgetManager.remaining_generations(manager) == 0
    end

    test "remaining_generations/1 returns :unlimited when no limit" do
      manager = BudgetManager.new()
      assert BudgetManager.remaining_generations(manager) == :unlimited
    end

    test "remaining_time/1 returns correct value" do
      manager = BudgetManager.new(max_time_seconds: 3600.0)
      assert BudgetManager.remaining_time(manager) == 3600.0

      manager = BudgetManager.record_consumption(manager, time_elapsed: 1200.0)
      assert_in_delta BudgetManager.remaining_time(manager), 2400.0, 0.001
    end

    test "remaining_time/1 returns :unlimited when no limit" do
      manager = BudgetManager.new()
      assert BudgetManager.remaining_time(manager) == :unlimited
    end

    test "remaining values do not go negative" do
      manager = BudgetManager.new(max_evaluations: 100, max_cost: 10.0)
      manager = BudgetManager.record_consumption(manager, evaluations: 150, cost: 15.0)

      assert BudgetManager.remaining_evaluations(manager) == 0
      assert_in_delta BudgetManager.remaining_cost(manager), 0.0, 0.001
    end
  end

  describe "per-generation budget without carryover" do
    test "available_budget/1 returns per-generation allocation" do
      manager = BudgetManager.new(budget_per_generation: 50)
      assert BudgetManager.available_budget(manager) == 50
    end

    test "does not carry over unused budget" do
      manager = BudgetManager.new(budget_per_generation: 50, allow_carryover: false)

      # Use only 30 of 50 allocated
      manager = BudgetManager.record_consumption(manager, evaluations: 30)

      # Next generation gets base 50, not 50 + 20 unused
      assert BudgetManager.available_budget(manager) == 50
      assert manager.carryover_balance == 0
    end

    test "resets carryover each generation" do
      manager = BudgetManager.new(budget_per_generation: 50, allow_carryover: false)

      manager =
        manager
        |> BudgetManager.record_consumption(evaluations: 30)
        |> BudgetManager.record_consumption(evaluations: 20)
        |> BudgetManager.record_consumption(evaluations: 10)

      assert manager.carryover_balance == 0
    end
  end

  describe "per-generation budget with carryover" do
    test "carries over unused budget to next generation" do
      manager = BudgetManager.new(budget_per_generation: 50, allow_carryover: true)

      # Use only 30 of 50 allocated
      manager = BudgetManager.record_consumption(manager, evaluations: 30)

      # Next generation gets 50 + 20 unused = 70
      assert BudgetManager.available_budget(manager) == 70
      assert manager.carryover_balance == 20
    end

    test "accumulates carryover across multiple generations" do
      manager = BudgetManager.new(budget_per_generation: 50, allow_carryover: true)

      # Generation 1: use 20, save 30
      manager = BudgetManager.record_consumption(manager, evaluations: 20)
      assert manager.carryover_balance == 30

      # Generation 2: use 30, have 50+30=80, save 50
      manager = BudgetManager.record_consumption(manager, evaluations: 30)
      assert manager.carryover_balance == 50

      # Generation 3: available = 50 + 50 = 100
      assert BudgetManager.available_budget(manager) == 100
    end

    test "does not carry over when over budget" do
      manager = BudgetManager.new(budget_per_generation: 50, allow_carryover: true)

      # Use 60 (over the 50 allocated)
      manager = BudgetManager.record_consumption(manager, evaluations: 60)

      # No carryover when over budget
      assert manager.carryover_balance == 0
      assert BudgetManager.available_budget(manager) == 50
    end

    test "handles exact budget usage" do
      manager = BudgetManager.new(budget_per_generation: 50, allow_carryover: true)

      # Use exactly 50
      manager = BudgetManager.record_consumption(manager, evaluations: 50)

      assert manager.carryover_balance == 0
      assert BudgetManager.available_budget(manager) == 50
    end
  end

  describe "available_budget/1 with total budget" do
    test "returns total remaining when no per-generation limit" do
      manager = BudgetManager.new(max_evaluations: 1000)
      assert BudgetManager.available_budget(manager) == 1000

      manager = BudgetManager.record_consumption(manager, evaluations: 300)
      assert BudgetManager.available_budget(manager) == 700
    end

    test "returns :unlimited when no limits set" do
      manager = BudgetManager.new()
      assert BudgetManager.available_budget(manager) == :unlimited
    end
  end

  describe "total_time_elapsed/1" do
    test "returns time since start" do
      manager = BudgetManager.new()

      # Sleep a bit to ensure time passes
      Process.sleep(10)

      elapsed = BudgetManager.total_time_elapsed(manager)
      assert elapsed > 0
      # Should be very small
      assert elapsed < 1.0
    end

    test "returns 0.0 when start_time is nil" do
      manager = %BudgetManager{start_time: nil}
      assert BudgetManager.total_time_elapsed(manager) == 0.0
    end
  end

  describe "reset/1" do
    test "clears all consumption and counters" do
      manager =
        BudgetManager.new(max_evaluations: 100, max_cost: 10.0)
        |> BudgetManager.record_consumption(evaluations: 50, cost: 5.0)
        |> BudgetManager.record_consumption(evaluations: 60, cost: 6.0)

      assert manager.evaluations_consumed == 110
      assert BudgetManager.budget_exhausted?(manager)

      manager = BudgetManager.reset(manager)

      assert manager.evaluations_consumed == 0
      assert manager.cost_consumed == 0.0
      assert manager.time_consumed == 0.0
      assert manager.current_generation == 0
      assert manager.consumption_history == []
      assert manager.carryover_balance == 0
      refute manager.budget_exhausted
    end

    test "preserves configuration after reset" do
      manager =
        BudgetManager.new(
          max_evaluations: 100,
          max_cost: 10.0,
          budget_per_generation: 50,
          allow_carryover: true
        )

      manager =
        manager
        |> BudgetManager.record_consumption(evaluations: 80, cost: 8.0)
        |> BudgetManager.reset()

      assert manager.max_evaluations == 100
      assert manager.max_cost == 10.0
      assert manager.budget_per_generation == 50
      assert manager.allow_carryover == true
    end

    test "resets start_time" do
      manager = BudgetManager.new()
      original_start = manager.start_time

      Process.sleep(10)

      manager = BudgetManager.reset(manager)

      assert DateTime.compare(manager.start_time, original_start) == :gt
    end
  end

  describe "edge cases" do
    test "handles zero budget limits" do
      manager = BudgetManager.new(max_evaluations: 0)

      # With zero budget, any consumption exhausts it
      # But initially not exhausted since no consumption yet
      refute BudgetManager.budget_exhausted?(manager)
      assert BudgetManager.remaining_evaluations(manager) == 0

      # First consumption exhausts it
      manager = BudgetManager.record_consumption(manager, evaluations: 1)
      assert BudgetManager.budget_exhausted?(manager)
    end

    test "handles very large consumption values" do
      manager = BudgetManager.new(max_evaluations: 1_000_000_000)
      manager = BudgetManager.record_consumption(manager, evaluations: 500_000_000)

      assert manager.evaluations_consumed == 500_000_000
      assert BudgetManager.remaining_evaluations(manager) == 500_000_000
    end

    test "handles fractional costs" do
      manager = BudgetManager.new(max_cost: 10.0)

      manager =
        manager
        |> BudgetManager.record_consumption(cost: 0.001)
        |> BudgetManager.record_consumption(cost: 0.002)
        |> BudgetManager.record_consumption(cost: 0.003)

      assert_in_delta manager.cost_consumed, 0.006, 0.0001
    end

    test "handles mixed usage patterns" do
      manager =
        BudgetManager.new(
          max_evaluations: 1000,
          max_cost: 100.0,
          budget_per_generation: 50,
          allow_carryover: true
        )

      # Use different amounts each generation
      manager =
        manager
        |> BudgetManager.record_consumption(evaluations: 20, cost: 2.0)
        |> BudgetManager.record_consumption(evaluations: 60, cost: 6.0)
        |> BudgetManager.record_consumption(evaluations: 10, cost: 1.0)

      assert manager.evaluations_consumed == 90
      assert_in_delta manager.cost_consumed, 9.0, 0.001
      assert manager.current_generation == 3

      # Check carryover logic
      # Gen 1: 50 allocated, 20 used, 30 saved
      # Gen 2: 50+30=80 allocated, 60 used, 20 saved
      # Gen 3: 50+20=70 allocated, 10 used, 60 saved
      assert manager.carryover_balance == 60
    end

    test "handles consumption without any limits" do
      manager = BudgetManager.new()

      manager =
        Enum.reduce(1..100, manager, fn _gen, acc ->
          BudgetManager.record_consumption(acc, evaluations: 100, cost: 10.0)
        end)

      # Should not exhaust despite heavy usage
      refute BudgetManager.budget_exhausted?(manager)
      assert manager.evaluations_consumed == 10_000
      assert_in_delta manager.cost_consumed, 1000.0, 0.01
    end
  end
end
