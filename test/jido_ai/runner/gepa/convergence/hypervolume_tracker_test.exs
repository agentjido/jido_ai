defmodule Jido.AI.Runner.GEPA.Convergence.HypervolumeTrackerTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Runner.GEPA.Convergence.HypervolumeTracker

  describe "new/1" do
    test "creates tracker with default configuration" do
      tracker = HypervolumeTracker.new()

      assert tracker.absolute_threshold == 0.001
      assert tracker.relative_threshold == 0.01
      assert tracker.average_threshold == 0.005
      assert tracker.window_size == 5
      assert tracker.patience == 5
      assert tracker.max_history == 100
      assert tracker.saturated == false
      assert tracker.patience_counter == 0
      assert tracker.hypervolume_history == []
    end

    test "accepts custom configuration" do
      tracker =
        HypervolumeTracker.new(
          absolute_threshold: 0.002,
          relative_threshold: 0.05,
          average_threshold: 0.01,
          window_size: 10,
          patience: 8
        )

      assert tracker.absolute_threshold == 0.002
      assert tracker.relative_threshold == 0.05
      assert tracker.average_threshold == 0.01
      assert tracker.window_size == 10
      assert tracker.patience == 8
    end

    test "stores configuration in config field" do
      tracker = HypervolumeTracker.new(custom_param: :value)

      assert tracker.config[:custom_param] == :value
    end
  end

  describe "update/2 with float values" do
    test "adds hypervolume record to history" do
      tracker = HypervolumeTracker.new()
      tracker = HypervolumeTracker.update(tracker, 0.5)

      assert length(tracker.hypervolume_history) == 1
      assert hd(tracker.hypervolume_history).generation == 1
      assert hd(tracker.hypervolume_history).hypervolume == 0.5
    end

    test "auto-increments generation numbers" do
      tracker = HypervolumeTracker.new()

      tracker =
        tracker
        |> HypervolumeTracker.update(0.5)
        |> HypervolumeTracker.update(0.52)
        |> HypervolumeTracker.update(0.54)

      assert length(tracker.hypervolume_history) == 3
      assert hd(tracker.hypervolume_history).generation == 3
      assert Enum.at(tracker.hypervolume_history, 1).generation == 2
      assert Enum.at(tracker.hypervolume_history, 2).generation == 1
    end

    test "accepts explicit generation numbers" do
      tracker = HypervolumeTracker.new()
      tracker = HypervolumeTracker.update(tracker, 0.5, 10)

      assert hd(tracker.hypervolume_history).generation == 10
    end

    test "maintains history in reverse chronological order" do
      tracker = HypervolumeTracker.new()

      tracker =
        tracker
        |> HypervolumeTracker.update(0.5)
        |> HypervolumeTracker.update(0.52)
        |> HypervolumeTracker.update(0.54)

      assert hd(tracker.hypervolume_history).hypervolume == 0.54
      assert Enum.at(tracker.hypervolume_history, -1).hypervolume == 0.5
    end

    test "trims history to max_history size" do
      tracker = HypervolumeTracker.new(max_history: 3)

      tracker =
        Enum.reduce(1..5, tracker, fn gen, acc ->
          HypervolumeTracker.update(acc, 0.5 + gen * 0.01)
        end)

      assert length(tracker.hypervolume_history) == 3
      assert hd(tracker.hypervolume_history).generation == 5
      assert Enum.at(tracker.hypervolume_history, -1).generation == 3
    end
  end

  describe "update/2 with map values" do
    test "accepts map with hypervolume key" do
      tracker = HypervolumeTracker.new()
      tracker = HypervolumeTracker.update(tracker, %{hypervolume: 0.65})

      assert length(tracker.hypervolume_history) == 1
      assert hd(tracker.hypervolume_history).hypervolume == 0.65
    end

    test "extracts generation from map if present" do
      tracker = HypervolumeTracker.new()
      tracker = HypervolumeTracker.update(tracker, %{hypervolume: 0.65, generation: 42})

      assert hd(tracker.hypervolume_history).generation == 42
    end
  end

  describe "saturation detection with improving hypervolume" do
    test "does not detect saturation when hypervolume consistently improving" do
      tracker = HypervolumeTracker.new(patience: 3)

      # Steadily improving hypervolume
      tracker =
        Enum.reduce(1..10, tracker, fn gen, acc ->
          HypervolumeTracker.update(acc, 0.5 + gen * 0.05)
        end)

      refute HypervolumeTracker.saturated?(tracker)
      assert tracker.patience_counter == 0
    end

    test "resets patience counter on improvement" do
      tracker = HypervolumeTracker.new(patience: 3)

      # Start with stagnant hypervolume
      tracker =
        tracker
        |> HypervolumeTracker.update(0.5)
        |> HypervolumeTracker.update(0.5)
        |> HypervolumeTracker.update(0.5)
        |> HypervolumeTracker.update(0.5)
        |> HypervolumeTracker.update(0.5)

      assert tracker.patience_counter > 0

      # Then improve significantly
      tracker =
        tracker
        |> HypervolumeTracker.update(0.6)
        |> HypervolumeTracker.update(0.65)

      # Patience should reset
      assert tracker.patience_counter == 0
      refute tracker.saturated
    end

    test "requires at least 2 records before detecting saturation" do
      tracker = HypervolumeTracker.new(patience: 1)

      tracker = HypervolumeTracker.update(tracker, 0.5)

      refute HypervolumeTracker.saturated?(tracker)
    end
  end

  describe "saturation detection with stagnant hypervolume" do
    test "detects saturation when hypervolume stops improving" do
      tracker = HypervolumeTracker.new(patience: 3)

      # Initial improvement
      tracker =
        Enum.reduce(1..5, tracker, fn gen, acc ->
          HypervolumeTracker.update(acc, 0.5 + gen * 0.05)
        end)

      # Then stagnation (same hypervolume)
      tracker =
        Enum.reduce(6..12, tracker, fn _gen, acc ->
          HypervolumeTracker.update(acc, 0.75)
        end)

      assert HypervolumeTracker.saturated?(tracker)
      assert tracker.patience_counter >= tracker.patience
    end

    test "detects saturation with minimal improvement below threshold" do
      tracker =
        HypervolumeTracker.new(
          patience: 3,
          absolute_threshold: 0.001,
          relative_threshold: 0.01,
          average_threshold: 0.005
        )

      # Improvements below all thresholds
      tracker =
        Enum.reduce(1..10, tracker, fn gen, acc ->
          hypervolume = 0.5 + gen * 0.0001
          HypervolumeTracker.update(acc, hypervolume)
        end)

      assert HypervolumeTracker.saturated?(tracker)
    end

    test "respects patience parameter" do
      tracker = HypervolumeTracker.new(patience: 5)

      # Stagnant hypervolume for exactly patience + 1 generations
      tracker =
        Enum.reduce(1..7, tracker, fn _gen, acc ->
          HypervolumeTracker.update(acc, 0.5)
        end)

      # Should be saturated
      assert HypervolumeTracker.saturated?(tracker)
      assert tracker.patience_counter >= 5
    end
  end

  describe "multi-criteria threshold testing" do
    test "uses absolute improvement threshold" do
      tracker =
        HypervolumeTracker.new(
          patience: 2,
          absolute_threshold: 0.01,
          relative_threshold: 1.0,
          average_threshold: 1.0
        )

      # 0.005 absolute improvement (below 0.01 threshold)
      # Other thresholds set high to only test absolute
      tracker =
        tracker
        |> HypervolumeTracker.update(1.000)
        |> HypervolumeTracker.update(1.000)
        |> HypervolumeTracker.update(1.005)
        |> HypervolumeTracker.update(1.005)
        |> HypervolumeTracker.update(1.005)
        |> HypervolumeTracker.update(1.005)

      assert HypervolumeTracker.saturated?(tracker)
    end

    test "uses relative improvement threshold" do
      tracker =
        HypervolumeTracker.new(
          patience: 2,
          absolute_threshold: 1.0,
          relative_threshold: 0.10,
          average_threshold: 1.0
        )

      # 5% relative improvement (below 10% threshold)
      # Other thresholds set high to only test relative
      tracker =
        tracker
        |> HypervolumeTracker.update(1.0)
        |> HypervolumeTracker.update(1.0)
        |> HypervolumeTracker.update(1.05)
        |> HypervolumeTracker.update(1.05)
        |> HypervolumeTracker.update(1.05)
        |> HypervolumeTracker.update(1.05)

      assert HypervolumeTracker.saturated?(tracker)
    end

    test "uses average improvement threshold" do
      tracker =
        HypervolumeTracker.new(
          patience: 3,
          absolute_threshold: 1.0,
          relative_threshold: 1.0,
          average_threshold: 0.01,
          window_size: 3
        )

      # Average improvement of 0.001 (below 0.01 threshold)
      # Other thresholds set high to only test average
      tracker =
        tracker
        |> HypervolumeTracker.update(1.000)
        |> HypervolumeTracker.update(1.001)
        |> HypervolumeTracker.update(1.002)
        |> HypervolumeTracker.update(1.003)
        |> HypervolumeTracker.update(1.004)
        |> HypervolumeTracker.update(1.005)
        |> HypervolumeTracker.update(1.006)

      assert HypervolumeTracker.saturated?(tracker)
    end

    test "detects improvement when any threshold exceeded" do
      tracker =
        HypervolumeTracker.new(
          patience: 2,
          absolute_threshold: 0.01,
          relative_threshold: 0.05,
          average_threshold: 0.005
        )

      # Small absolute but large relative improvement
      tracker =
        tracker
        |> HypervolumeTracker.update(0.01)
        |> HypervolumeTracker.update(0.01)
        |> HypervolumeTracker.update(0.015)
        |> HypervolumeTracker.update(0.015)

      # 50% relative improvement should prevent saturation
      refute HypervolumeTracker.saturated?(tracker)
    end

    test "requires ALL criteria below threshold for saturation" do
      tracker =
        HypervolumeTracker.new(
          patience: 2,
          absolute_threshold: 0.001,
          relative_threshold: 0.01,
          average_threshold: 0.005
        )

      # Exceeds absolute threshold but not others
      tracker =
        tracker
        |> HypervolumeTracker.update(1.0)
        |> HypervolumeTracker.update(1.0)
        |> HypervolumeTracker.update(1.002)
        |> HypervolumeTracker.update(1.002)

      # Should not saturate (relative improvement is 0.2%)
      refute HypervolumeTracker.saturated?(tracker)
    end
  end

  describe "average improvement rate calculation" do
    test "calculates average improvement over window" do
      tracker = HypervolumeTracker.new(window_size: 3)

      tracker =
        tracker
        |> HypervolumeTracker.update(0.5)
        |> HypervolumeTracker.update(0.52)
        |> HypervolumeTracker.update(0.54)
        |> HypervolumeTracker.update(0.56)

      avg_rate = HypervolumeTracker.get_average_improvement_rate(tracker)

      # Recent 3 records: 0.56, 0.54, 0.52
      # Improvements: 0.02, 0.02
      # Average: 0.02
      assert_in_delta avg_rate, 0.02, 0.0001
    end

    test "returns 0.0 for insufficient history" do
      tracker = HypervolumeTracker.new()
      assert HypervolumeTracker.get_average_improvement_rate(tracker) == 0.0

      tracker = HypervolumeTracker.update(tracker, 0.5)
      assert HypervolumeTracker.get_average_improvement_rate(tracker) == 0.0
    end

    test "ignores nil improvements in calculation" do
      tracker = HypervolumeTracker.new(window_size: 3)

      tracker =
        tracker
        |> HypervolumeTracker.update(0.5)
        |> HypervolumeTracker.update(0.52)

      avg_rate = HypervolumeTracker.get_average_improvement_rate(tracker)

      # Only one improvement value (0.02)
      assert_in_delta avg_rate, 0.02, 0.0001
    end
  end

  describe "query methods" do
    test "saturated?/1 returns false for new tracker" do
      tracker = HypervolumeTracker.new()
      refute HypervolumeTracker.saturated?(tracker)
    end

    test "saturated?/1 returns true when saturated" do
      tracker = HypervolumeTracker.new(patience: 2)

      tracker =
        Enum.reduce(1..5, tracker, fn _gen, acc ->
          HypervolumeTracker.update(acc, 0.5)
        end)

      assert HypervolumeTracker.saturated?(tracker)
    end

    test "get_current_hypervolume/1 returns nil for empty tracker" do
      tracker = HypervolumeTracker.new()
      assert HypervolumeTracker.get_current_hypervolume(tracker) == nil
    end

    test "get_current_hypervolume/1 returns latest hypervolume" do
      tracker = HypervolumeTracker.new()

      tracker =
        tracker
        |> HypervolumeTracker.update(0.5)
        |> HypervolumeTracker.update(0.52)
        |> HypervolumeTracker.update(0.54)

      assert HypervolumeTracker.get_current_hypervolume(tracker) == 0.54
    end

    test "get_recent_improvement/1 returns nil for empty tracker" do
      tracker = HypervolumeTracker.new()
      assert HypervolumeTracker.get_recent_improvement(tracker) == nil
    end

    test "get_recent_improvement/1 returns latest improvement" do
      tracker = HypervolumeTracker.new()

      tracker =
        tracker
        |> HypervolumeTracker.update(0.5)
        |> HypervolumeTracker.update(0.52)
        |> HypervolumeTracker.update(0.54)

      improvement = HypervolumeTracker.get_recent_improvement(tracker)
      assert_in_delta improvement, 0.02, 0.0001
    end

    test "get_recent_improvement/1 returns nil for first record" do
      tracker = HypervolumeTracker.new()
      tracker = HypervolumeTracker.update(tracker, 0.5)

      assert HypervolumeTracker.get_recent_improvement(tracker) == nil
    end
  end

  describe "reset/1" do
    test "clears all history and counters" do
      tracker = HypervolumeTracker.new(patience: 2)

      tracker =
        Enum.reduce(1..8, tracker, fn _gen, acc ->
          HypervolumeTracker.update(acc, 0.5)
        end)

      assert HypervolumeTracker.saturated?(tracker)
      assert length(tracker.hypervolume_history) > 0

      tracker = HypervolumeTracker.reset(tracker)

      refute HypervolumeTracker.saturated?(tracker)
      assert tracker.hypervolume_history == []
      assert tracker.patience_counter == 0
    end

    test "preserves configuration after reset" do
      tracker = HypervolumeTracker.new(window_size: 10, patience: 8, absolute_threshold: 0.002)

      tracker =
        Enum.reduce(1..12, tracker, fn _gen, acc ->
          HypervolumeTracker.update(acc, 0.5)
        end)

      tracker = HypervolumeTracker.reset(tracker)

      assert tracker.window_size == 10
      assert tracker.patience == 8
      assert tracker.absolute_threshold == 0.002
    end
  end

  describe "edge cases" do
    test "handles zero baseline hypervolume gracefully" do
      tracker = HypervolumeTracker.new(patience: 2)

      tracker =
        tracker
        |> HypervolumeTracker.update(0.0)
        |> HypervolumeTracker.update(0.0)
        |> HypervolumeTracker.update(0.0)
        |> HypervolumeTracker.update(0.0)
        |> HypervolumeTracker.update(0.0)

      # Should detect saturation even with zero hypervolume
      assert HypervolumeTracker.saturated?(tracker)
    end

    test "handles hypervolume declining" do
      tracker = HypervolumeTracker.new(patience: 2)

      # Declining hypervolume
      tracker =
        Enum.reduce(1..6, tracker, fn gen, acc ->
          hypervolume = 1.0 - gen * 0.05
          HypervolumeTracker.update(acc, hypervolume)
        end)

      # Declining hypervolume is not improving
      assert HypervolumeTracker.saturated?(tracker)
    end

    test "handles very small hypervolume differences" do
      tracker =
        HypervolumeTracker.new(
          patience: 2,
          absolute_threshold: 1.0e-10,
          relative_threshold: 1.0e-8,
          average_threshold: 1.0e-10
        )

      base = 0.123456789

      # Improvements of 1.0e-12 are well below all thresholds
      # Add sufficient generations to exceed patience
      tracker =
        Enum.reduce(1..10, tracker, fn gen, acc ->
          hypervolume = base + gen * 1.0e-12
          HypervolumeTracker.update(acc, hypervolume)
        end)

      # Should detect saturation with tiny improvements
      assert HypervolumeTracker.saturated?(tracker)
    end

    test "handles large hypervolume jumps" do
      tracker = HypervolumeTracker.new(patience: 2)

      tracker =
        tracker
        |> HypervolumeTracker.update(0.1)
        |> HypervolumeTracker.update(0.1)
        |> HypervolumeTracker.update(10.0)
        |> HypervolumeTracker.update(10.0)

      # Large jump should reset patience
      refute HypervolumeTracker.saturated?(tracker)
    end

    test "handles alternating hypervolume values" do
      tracker =
        HypervolumeTracker.new(patience: 3, absolute_threshold: 0.001, relative_threshold: 0.01)

      # Use small oscillations that don't exceed thresholds
      tracker =
        Enum.reduce(1..10, tracker, fn gen, acc ->
          # Oscillate by tiny amounts (0.0005) below thresholds
          hypervolume = if rem(gen, 2) == 0, do: 0.5005, else: 0.5
          HypervolumeTracker.update(acc, hypervolume)
        end)

      # Small oscillations below threshold should trigger saturation
      assert HypervolumeTracker.saturated?(tracker)
    end

    test "handles negative improvements (decreasing hypervolume)" do
      tracker = HypervolumeTracker.new(patience: 2)

      tracker =
        tracker
        |> HypervolumeTracker.update(1.0)
        |> HypervolumeTracker.update(0.9)
        |> HypervolumeTracker.update(0.8)
        |> HypervolumeTracker.update(0.7)

      # Negative improvements should trigger saturation
      assert HypervolumeTracker.saturated?(tracker)

      # Check that improvements are recorded as negative
      recent = HypervolumeTracker.get_recent_improvement(tracker)
      assert recent < 0
    end

    test "handles very large hypervolumes" do
      tracker = HypervolumeTracker.new(patience: 2)

      tracker =
        tracker
        |> HypervolumeTracker.update(1_000_000.0)
        |> HypervolumeTracker.update(1_000_001.0)
        |> HypervolumeTracker.update(1_000_002.0)

      # Should track improvements correctly
      refute HypervolumeTracker.saturated?(tracker)
      assert HypervolumeTracker.get_current_hypervolume(tracker) == 1_000_002.0
    end

    test "calculates relative improvement correctly when previous is zero" do
      tracker = HypervolumeTracker.new(patience: 2)

      tracker =
        tracker
        |> HypervolumeTracker.update(0.0)
        |> HypervolumeTracker.update(0.5)

      # Should not crash when dividing by zero
      assert HypervolumeTracker.get_current_hypervolume(tracker) == 0.5
      refute HypervolumeTracker.saturated?(tracker)
    end
  end

  describe "improvements tracking" do
    test "records absolute improvements in history" do
      tracker = HypervolumeTracker.new()

      tracker =
        tracker
        |> HypervolumeTracker.update(0.5)
        |> HypervolumeTracker.update(0.52)
        |> HypervolumeTracker.update(0.56)

      [latest, second, first] = tracker.hypervolume_history

      # First record has no improvement
      assert first.absolute_improvement == nil

      # Second record: 0.52 - 0.5 = 0.02
      assert_in_delta second.absolute_improvement, 0.02, 0.0001

      # Latest record: 0.56 - 0.52 = 0.04
      assert_in_delta latest.absolute_improvement, 0.04, 0.0001
    end

    test "records relative improvements in history" do
      tracker = HypervolumeTracker.new()

      tracker =
        tracker
        |> HypervolumeTracker.update(1.0)
        |> HypervolumeTracker.update(1.1)
        |> HypervolumeTracker.update(1.21)

      [latest, second, first] = tracker.hypervolume_history

      # First record has no improvement
      assert first.relative_improvement == nil

      # Second record: (1.1 - 1.0) / 1.0 = 0.1 (10%)
      assert_in_delta second.relative_improvement, 0.1, 0.0001

      # Latest record: (1.21 - 1.1) / 1.1 = 0.1 (10%)
      assert_in_delta latest.relative_improvement, 0.1, 0.0001
    end
  end
end
