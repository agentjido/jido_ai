defmodule Jido.AI.Runner.GEPA.MutationSchedulerTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Runner.GEPA.Diversity.DiversityMetrics
  alias Jido.AI.Runner.GEPA.MutationScheduler
  alias Jido.AI.Runner.GEPA.MutationScheduler.SchedulerState

  describe "new/1" do
    test "creates scheduler with default configuration" do
      scheduler = MutationScheduler.new()

      assert %SchedulerState{} = scheduler
      assert scheduler.strategy == :adaptive
      assert scheduler.base_rate == 0.15
      assert scheduler.min_rate == 0.05
      assert scheduler.max_rate == 0.5
      assert scheduler.current_rate == 0.15
      assert scheduler.manual_rate == nil
      assert scheduler.fitness_history == []
      assert scheduler.stagnation_generations == 0
    end

    test "creates scheduler with custom configuration" do
      scheduler =
        MutationScheduler.new(
          strategy: :linear_decay,
          base_rate: 0.3,
          min_rate: 0.1,
          max_rate: 0.6,
          improvement_threshold: 0.02
        )

      assert scheduler.strategy == :linear_decay
      assert scheduler.base_rate == 0.3
      assert scheduler.min_rate == 0.1
      assert scheduler.max_rate == 0.6
      assert scheduler.current_rate == 0.3
      assert scheduler.improvement_threshold == 0.02
    end

    test "accepts metadata" do
      scheduler = MutationScheduler.new(metadata: %{custom: "data"})
      assert scheduler.metadata == %{custom: "data"}
    end
  end

  describe "next_rate/2 - adaptive strategy" do
    test "computes adaptive rate based on progress" do
      scheduler = MutationScheduler.new(strategy: :adaptive)

      {:ok, rate, _scheduler} =
        MutationScheduler.next_rate(scheduler,
          current_generation: 5,
          max_generations: 50,
          best_fitness: 0.5
        )

      assert is_float(rate)
      assert rate >= scheduler.min_rate
      assert rate <= scheduler.max_rate
    end

    test "increases rate when population is stagnating" do
      scheduler = MutationScheduler.new(strategy: :adaptive, base_rate: 0.15)

      # Simulate stagnation by providing same fitness multiple times
      scheduler =
        Enum.reduce(0..5, scheduler, fn gen, sch ->
          {:ok, _rate, updated} =
            MutationScheduler.next_rate(sch,
              current_generation: gen,
              max_generations: 50,
              best_fitness: 0.5
            )

          updated
        end)

      # After stagnation, rate should be higher than base
      {:ok, stagnant_rate, _} =
        MutationScheduler.next_rate(scheduler,
          current_generation: 6,
          max_generations: 50,
          best_fitness: 0.5
        )

      assert stagnant_rate > 0.15
    end

    test "adjusts rate based on diversity metrics" do
      scheduler = MutationScheduler.new(strategy: :adaptive)

      critical_diversity = %DiversityMetrics{
        diversity_level: :critical,
        pairwise_diversity: 0.1
      }

      {:ok, critical_rate, _} =
        MutationScheduler.next_rate(scheduler,
          current_generation: 5,
          max_generations: 50,
          best_fitness: 0.5,
          diversity_metrics: critical_diversity
        )

      healthy_diversity = %DiversityMetrics{
        diversity_level: :healthy,
        pairwise_diversity: 0.6
      }

      {:ok, healthy_rate, _} =
        MutationScheduler.next_rate(scheduler,
          current_generation: 5,
          max_generations: 50,
          best_fitness: 0.5,
          diversity_metrics: healthy_diversity
        )

      # Critical diversity should result in higher mutation rate
      assert critical_rate > healthy_rate
    end

    test "reduces rate when fitness is improving rapidly" do
      scheduler = MutationScheduler.new(strategy: :adaptive, base_rate: 0.15)

      # Simulate rapid improvement
      scheduler =
        Enum.reduce(0..4, scheduler, fn gen, sch ->
          fitness = 0.5 + gen * 0.1

          {:ok, _rate, updated} =
            MutationScheduler.next_rate(sch,
              current_generation: gen,
              max_generations: 50,
              best_fitness: fitness
            )

          updated
        end)

      {:ok, improving_rate, _} =
        MutationScheduler.next_rate(scheduler,
          current_generation: 5,
          max_generations: 50,
          best_fitness: 1.0
        )

      # With rapid improvement, rate should be lower to exploit
      assert improving_rate < 0.15
    end

    test "increases rate when improvement slows" do
      scheduler = MutationScheduler.new(strategy: :adaptive, base_rate: 0.15)

      # Simulate slow improvement
      scheduler =
        Enum.reduce(0..4, scheduler, fn gen, sch ->
          fitness = 0.5 + gen * 0.002

          {:ok, _rate, updated} =
            MutationScheduler.next_rate(sch,
              current_generation: gen,
              max_generations: 50,
              best_fitness: fitness
            )

          updated
        end)

      {:ok, slow_improvement_rate, _} =
        MutationScheduler.next_rate(scheduler,
          current_generation: 5,
          max_generations: 50,
          best_fitness: 0.51
        )

      # With slow improvement, rate should increase to explore more
      assert slow_improvement_rate >= 0.15
    end
  end

  describe "next_rate/2 - linear_decay strategy" do
    test "linearly decreases rate from max to min" do
      scheduler =
        MutationScheduler.new(
          strategy: :linear_decay,
          min_rate: 0.05,
          max_rate: 0.5
        )

      {:ok, rate_gen_0, _} =
        MutationScheduler.next_rate(scheduler,
          current_generation: 0,
          max_generations: 100,
          best_fitness: 0.5
        )

      {:ok, rate_gen_50, _} =
        MutationScheduler.next_rate(scheduler,
          current_generation: 50,
          max_generations: 100,
          best_fitness: 0.5
        )

      {:ok, rate_gen_100, _} =
        MutationScheduler.next_rate(scheduler,
          current_generation: 100,
          max_generations: 100,
          best_fitness: 0.5
        )

      # Rate should decrease linearly
      assert rate_gen_0 > rate_gen_50
      assert rate_gen_50 > rate_gen_100
      assert_in_delta rate_gen_100, scheduler.min_rate, 0.01
    end
  end

  describe "next_rate/2 - exponential_decay strategy" do
    test "exponentially decreases rate" do
      scheduler =
        MutationScheduler.new(
          strategy: :exponential_decay,
          min_rate: 0.05,
          max_rate: 0.5
        )

      {:ok, rate_gen_0, _} =
        MutationScheduler.next_rate(scheduler,
          current_generation: 0,
          max_generations: 100,
          best_fitness: 0.5
        )

      {:ok, rate_gen_50, _} =
        MutationScheduler.next_rate(scheduler,
          current_generation: 50,
          max_generations: 100,
          best_fitness: 0.5
        )

      # Rate should decrease exponentially (faster decay early on)
      assert rate_gen_0 > rate_gen_50
    end
  end

  describe "next_rate/2 - constant strategy" do
    test "maintains constant rate" do
      scheduler = MutationScheduler.new(strategy: :constant, base_rate: 0.25)

      {:ok, rate_gen_0, _} =
        MutationScheduler.next_rate(scheduler,
          current_generation: 0,
          max_generations: 100,
          best_fitness: 0.5
        )

      {:ok, rate_gen_50, _} =
        MutationScheduler.next_rate(scheduler,
          current_generation: 50,
          max_generations: 100,
          best_fitness: 0.9
        )

      {:ok, rate_gen_100, _} =
        MutationScheduler.next_rate(scheduler,
          current_generation: 100,
          max_generations: 100,
          best_fitness: 0.95
        )

      # Rate should remain constant
      assert rate_gen_0 == 0.25
      assert rate_gen_50 == 0.25
      assert rate_gen_100 == 0.25
    end
  end

  describe "next_rate/2 - manual strategy" do
    test "uses manual rate when set" do
      scheduler = MutationScheduler.new(strategy: :manual)
      scheduler = MutationScheduler.set_manual_rate(scheduler, 0.35)

      {:ok, rate, _} =
        MutationScheduler.next_rate(scheduler,
          current_generation: 0,
          max_generations: 100,
          best_fitness: 0.5
        )

      assert rate == 0.35
    end

    test "uses manual rate even with adaptive strategy" do
      scheduler = MutationScheduler.new(strategy: :adaptive)
      scheduler = MutationScheduler.set_manual_rate(scheduler, 0.4)

      {:ok, rate, _} =
        MutationScheduler.next_rate(scheduler,
          current_generation: 0,
          max_generations: 100,
          best_fitness: 0.5
        )

      assert rate == 0.4
    end
  end

  describe "next_rate/2 - rate clamping" do
    test "clamps rate to min_rate" do
      scheduler =
        MutationScheduler.new(
          strategy: :linear_decay,
          min_rate: 0.05,
          max_rate: 0.5
        )

      # At the end of generations, should clamp to min
      {:ok, rate, _} =
        MutationScheduler.next_rate(scheduler,
          current_generation: 200,
          max_generations: 100,
          best_fitness: 0.95
        )

      assert rate >= scheduler.min_rate
    end

    test "clamps rate to max_rate" do
      scheduler =
        MutationScheduler.new(
          strategy: :adaptive,
          min_rate: 0.05,
          max_rate: 0.3,
          base_rate: 0.25
        )

      critical_diversity = %DiversityMetrics{
        diversity_level: :critical,
        pairwise_diversity: 0.05,
        convergence_risk: 0.95
      }

      # Even with critical diversity, should not exceed max
      {:ok, rate, _} =
        MutationScheduler.next_rate(scheduler,
          current_generation: 0,
          max_generations: 100,
          best_fitness: 0.5,
          diversity_metrics: critical_diversity
        )

      assert rate <= scheduler.max_rate
    end
  end

  describe "set_manual_rate/2" do
    test "sets manual rate override" do
      scheduler = MutationScheduler.new()
      updated = MutationScheduler.set_manual_rate(scheduler, 0.35)

      assert updated.manual_rate == 0.35
      assert updated.strategy == :manual
    end

    test "clears manual rate with nil" do
      scheduler = MutationScheduler.new()
      updated = MutationScheduler.set_manual_rate(scheduler, 0.35)
      cleared = MutationScheduler.set_manual_rate(updated, nil)

      assert cleared.manual_rate == nil
      assert cleared.strategy == :adaptive
    end

    test "clamps manual rate to bounds" do
      scheduler = MutationScheduler.new(min_rate: 0.1, max_rate: 0.4)

      too_high = MutationScheduler.set_manual_rate(scheduler, 0.8)
      assert too_high.manual_rate == 0.4

      too_low = MutationScheduler.set_manual_rate(scheduler, 0.01)
      assert too_low.manual_rate == 0.1
    end
  end

  describe "current_rate/1" do
    test "returns current computed rate" do
      scheduler = MutationScheduler.new()
      rate = MutationScheduler.current_rate(scheduler)

      assert rate == scheduler.current_rate
    end

    test "returns manual rate when set" do
      scheduler = MutationScheduler.new()
      scheduler = MutationScheduler.set_manual_rate(scheduler, 0.35)

      rate = MutationScheduler.current_rate(scheduler)
      assert rate == 0.35
    end
  end

  describe "reset/1" do
    test "resets scheduler to initial state" do
      scheduler = MutationScheduler.new(base_rate: 0.2)

      # Modify scheduler state
      scheduler = MutationScheduler.set_manual_rate(scheduler, 0.35)

      {:ok, _rate, scheduler} =
        MutationScheduler.next_rate(scheduler,
          current_generation: 10,
          max_generations: 100,
          best_fitness: 0.75
        )

      # Reset
      reset_scheduler = MutationScheduler.reset(scheduler)

      assert reset_scheduler.current_rate == reset_scheduler.base_rate
      assert reset_scheduler.fitness_history == []
      assert reset_scheduler.stagnation_generations == 0
      assert reset_scheduler.manual_rate == nil

      # Configuration should be preserved
      assert reset_scheduler.base_rate == 0.2
      assert reset_scheduler.strategy == :manual
    end
  end

  describe "fitness history tracking" do
    test "maintains fitness history" do
      scheduler = MutationScheduler.new()

      {:ok, _rate, scheduler} =
        MutationScheduler.next_rate(scheduler,
          current_generation: 0,
          max_generations: 100,
          best_fitness: 0.5
        )

      {:ok, _rate, scheduler} =
        MutationScheduler.next_rate(scheduler,
          current_generation: 1,
          max_generations: 100,
          best_fitness: 0.6
        )

      assert length(scheduler.fitness_history) == 2
      assert Enum.any?(scheduler.fitness_history, fn {gen, _fit} -> gen == 0 end)
      assert Enum.any?(scheduler.fitness_history, fn {gen, _fit} -> gen == 1 end)
    end

    test "limits fitness history to last 10 generations" do
      scheduler = MutationScheduler.new()

      scheduler =
        Enum.reduce(0..15, scheduler, fn gen, sch ->
          {:ok, _rate, updated} =
            MutationScheduler.next_rate(sch,
              current_generation: gen,
              max_generations: 100,
              best_fitness: 0.5 + gen * 0.01
            )

          updated
        end)

      assert length(scheduler.fitness_history) == 10
    end
  end

  describe "stagnation detection" do
    test "detects stagnation when fitness plateaus" do
      scheduler = MutationScheduler.new(improvement_threshold: 0.01)

      # Provide same fitness for multiple generations
      scheduler =
        Enum.reduce(0..6, scheduler, fn gen, sch ->
          {:ok, _rate, updated} =
            MutationScheduler.next_rate(sch,
              current_generation: gen,
              max_generations: 100,
              best_fitness: 0.5
            )

          updated
        end)

      assert scheduler.stagnation_generations > 0
    end

    test "resets stagnation when improvement occurs" do
      scheduler = MutationScheduler.new(improvement_threshold: 0.01)

      # Stagnate first
      scheduler =
        Enum.reduce(0..4, scheduler, fn gen, sch ->
          {:ok, _rate, updated} =
            MutationScheduler.next_rate(sch,
              current_generation: gen,
              max_generations: 100,
              best_fitness: 0.5
            )

          updated
        end)

      stagnation_count = scheduler.stagnation_generations

      # Then improve
      {:ok, _rate, scheduler} =
        MutationScheduler.next_rate(scheduler,
          current_generation: 5,
          max_generations: 100,
          best_fitness: 0.7
        )

      assert scheduler.stagnation_generations < stagnation_count
    end
  end

  describe "exploration/exploitation balance" do
    test "explores more at the beginning" do
      scheduler = MutationScheduler.new(strategy: :adaptive, base_rate: 0.15)

      {:ok, early_rate, _} =
        MutationScheduler.next_rate(scheduler,
          current_generation: 0,
          max_generations: 100,
          best_fitness: 0.5
        )

      {:ok, late_rate, _} =
        MutationScheduler.next_rate(scheduler,
          current_generation: 90,
          max_generations: 100,
          best_fitness: 0.9
        )

      # Early in optimization, should have higher rate (more exploration)
      # Late in optimization, should have lower rate (more exploitation)
      assert early_rate >= late_rate
    end

    test "balances diversity needs with progress" do
      scheduler = MutationScheduler.new(strategy: :adaptive)

      # High diversity, early generation - should still explore
      high_diversity = %DiversityMetrics{
        diversity_level: :excellent,
        pairwise_diversity: 0.8
      }

      {:ok, high_div_rate, _} =
        MutationScheduler.next_rate(scheduler,
          current_generation: 10,
          max_generations: 100,
          best_fitness: 0.5,
          diversity_metrics: high_diversity
        )

      # Low diversity, late generation - should still explore to find better solutions
      low_diversity = %DiversityMetrics{
        diversity_level: :low,
        pairwise_diversity: 0.2
      }

      {:ok, low_div_rate, _} =
        MutationScheduler.next_rate(scheduler,
          current_generation: 90,
          max_generations: 100,
          best_fitness: 0.9,
          diversity_metrics: low_diversity
        )

      # Low diversity should result in higher mutation rate regardless of generation
      assert low_div_rate > high_div_rate
    end
  end

  describe "edge cases" do
    test "handles first generation" do
      scheduler = MutationScheduler.new()

      {:ok, rate, scheduler} =
        MutationScheduler.next_rate(scheduler,
          current_generation: 0,
          max_generations: 100,
          best_fitness: 0.0
        )

      assert is_float(rate)
      assert rate >= scheduler.min_rate
      assert rate <= scheduler.max_rate
    end

    test "handles single generation optimization" do
      scheduler = MutationScheduler.new()

      {:ok, rate, _} =
        MutationScheduler.next_rate(scheduler,
          current_generation: 0,
          max_generations: 1,
          best_fitness: 0.5
        )

      assert is_float(rate)
    end

    test "handles max_generations = 0" do
      scheduler = MutationScheduler.new(strategy: :linear_decay)

      {:ok, rate, _} =
        MutationScheduler.next_rate(scheduler,
          current_generation: 0,
          max_generations: 0,
          best_fitness: 0.5
        )

      assert is_float(rate)
    end
  end

  describe "integration scenarios" do
    test "full optimization cycle with adaptive scheduling" do
      scheduler = MutationScheduler.new(strategy: :adaptive, base_rate: 0.2)

      {rates, _final_scheduler} =
        Enum.map_reduce(0..20, scheduler, fn gen, sch ->
          fitness = 0.3 + gen * 0.03

          {:ok, rate, updated_scheduler} =
            MutationScheduler.next_rate(sch,
              current_generation: gen,
              max_generations: 20,
              best_fitness: fitness
            )

          {{gen, rate}, updated_scheduler}
        end)

      # Rates should generally decrease as optimization progresses
      first_half_avg =
        rates
        |> Enum.take(10)
        |> Enum.map(fn {_gen, rate} -> rate end)
        |> Enum.sum()
        |> Kernel./(10)

      second_half_avg =
        rates
        |> Enum.drop(10)
        |> Enum.map(fn {_gen, rate} -> rate end)
        |> Enum.sum()
        |> Kernel./(10)

      assert first_half_avg >= second_half_avg
    end

    test "handles stagnation recovery scenario" do
      scheduler = MutationScheduler.new(strategy: :adaptive, base_rate: 0.15)

      # Simulate stagnation period
      scheduler =
        Enum.reduce(0..7, scheduler, fn gen, sch ->
          {:ok, _rate, updated} =
            MutationScheduler.next_rate(sch,
              current_generation: gen,
              max_generations: 50,
              best_fitness: 0.5
            )

          updated
        end)

      {:ok, stagnant_rate, _} =
        MutationScheduler.next_rate(scheduler,
          current_generation: 8,
          max_generations: 50,
          best_fitness: 0.5
        )

      # During stagnation, mutation rate should be elevated
      assert stagnant_rate > 0.15
    end
  end
end
