defmodule Jido.AI.Runner.GEPA.Convergence.PlateauDetectorTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Runner.GEPA.Convergence.{FitnessRecord, PlateauDetector}

  describe "new/1" do
    test "creates detector with default configuration" do
      detector = PlateauDetector.new()

      assert detector.window_size == 5
      assert detector.patience == 5
      assert detector.improvement_threshold == 0.01
      assert detector.absolute_threshold == 0.001
      assert detector.max_history == 100
      assert detector.plateau_detected == false
      assert detector.patience_counter == 0
      assert detector.fitness_history == []
    end

    test "accepts custom configuration" do
      detector =
        PlateauDetector.new(
          window_size: 10,
          patience: 8,
          improvement_threshold: 0.05,
          absolute_threshold: 0.002
        )

      assert detector.window_size == 10
      assert detector.patience == 8
      assert detector.improvement_threshold == 0.05
      assert detector.absolute_threshold == 0.002
    end

    test "stores configuration in config field" do
      detector = PlateauDetector.new(custom_param: :value)

      assert detector.config[:custom_param] == :value
    end
  end

  describe "update/2" do
    test "adds fitness record to history" do
      detector = PlateauDetector.new()
      record = create_fitness_record(1, 0.5)

      detector = PlateauDetector.update(detector, record)

      assert length(detector.fitness_history) == 1
      assert hd(detector.fitness_history).generation == 1
      assert hd(detector.fitness_history).best_fitness == 0.5
    end

    test "accepts map as fitness record" do
      detector = PlateauDetector.new()
      record_map = %{generation: 1, best_fitness: 0.5, mean_fitness: 0.45}

      detector = PlateauDetector.update(detector, record_map)

      assert length(detector.fitness_history) == 1
      assert hd(detector.fitness_history).generation == 1
    end

    test "maintains history in reverse chronological order" do
      detector = PlateauDetector.new()

      detector =
        detector
        |> PlateauDetector.update(create_fitness_record(1, 0.5))
        |> PlateauDetector.update(create_fitness_record(2, 0.52))
        |> PlateauDetector.update(create_fitness_record(3, 0.54))

      assert length(detector.fitness_history) == 3
      assert hd(detector.fitness_history).generation == 3
      assert Enum.at(detector.fitness_history, -1).generation == 1
    end

    test "trims history to max_history size" do
      detector = PlateauDetector.new(max_history: 3)

      detector =
        Enum.reduce(1..5, detector, fn gen, acc ->
          PlateauDetector.update(acc, create_fitness_record(gen, 0.5 + gen * 0.01))
        end)

      assert length(detector.fitness_history) == 3
      assert hd(detector.fitness_history).generation == 5
      assert Enum.at(detector.fitness_history, -1).generation == 3
    end
  end

  describe "plateau detection with improving fitness" do
    test "does not detect plateau when fitness consistently improving" do
      detector = PlateauDetector.new(window_size: 3, patience: 3)

      # Steadily improving fitness
      detector =
        Enum.reduce(1..10, detector, fn gen, acc ->
          PlateauDetector.update(acc, create_fitness_record(gen, 0.5 + gen * 0.05))
        end)

      refute PlateauDetector.plateau_detected?(detector)
      assert detector.patience_counter == 0
    end

    test "resets patience counter on improvement" do
      detector = PlateauDetector.new(window_size: 2, patience: 3)

      # Start with stagnant fitness (need window_size * 2 = 4 records minimum)
      detector =
        detector
        |> PlateauDetector.update(create_fitness_record(1, 0.5))
        |> PlateauDetector.update(create_fitness_record(2, 0.5))
        |> PlateauDetector.update(create_fitness_record(3, 0.5))
        |> PlateauDetector.update(create_fitness_record(4, 0.5))
        |> PlateauDetector.update(create_fitness_record(5, 0.5))

      assert detector.patience_counter > 0

      # Then improve
      detector =
        detector
        |> PlateauDetector.update(create_fitness_record(6, 0.6))
        |> PlateauDetector.update(create_fitness_record(7, 0.65))

      # Patience should reset
      assert detector.patience_counter == 0
      refute detector.plateau_detected
    end

    test "requires sufficient history before detecting plateau" do
      detector = PlateauDetector.new(window_size: 5, patience: 3)

      # Not enough history (need window_size * 2 = 10)
      detector =
        Enum.reduce(1..8, detector, fn gen, acc ->
          PlateauDetector.update(acc, create_fitness_record(gen, 0.5))
        end)

      refute PlateauDetector.plateau_detected?(detector)
    end
  end

  describe "plateau detection with stagnant fitness" do
    test "detects plateau when fitness stops improving" do
      detector = PlateauDetector.new(window_size: 3, patience: 3)

      # Initial improvement
      detector =
        Enum.reduce(1..5, detector, fn gen, acc ->
          PlateauDetector.update(acc, create_fitness_record(gen, 0.5 + gen * 0.05))
        end)

      # Then stagnation (same fitness)
      detector =
        Enum.reduce(6..12, detector, fn gen, acc ->
          PlateauDetector.update(acc, create_fitness_record(gen, 0.75))
        end)

      assert PlateauDetector.plateau_detected?(detector)
      assert detector.patience_counter >= detector.patience
    end

    test "detects plateau with minimal improvement below threshold" do
      detector =
        PlateauDetector.new(
          window_size: 3,
          patience: 3,
          improvement_threshold: 0.01,
          absolute_threshold: 0.001
        )

      # Improvements below threshold (< 0.001 absolute, < 1% relative)
      detector =
        Enum.reduce(1..15, detector, fn gen, acc ->
          fitness = 0.5 + gen * 0.0001
          PlateauDetector.update(acc, create_fitness_record(gen, fitness))
        end)

      assert PlateauDetector.plateau_detected?(detector)
    end

    test "respects patience parameter" do
      detector = PlateauDetector.new(window_size: 2, patience: 5)

      # Stagnant fitness for exactly patience generations
      detector =
        Enum.reduce(1..10, detector, fn gen, acc ->
          PlateauDetector.update(acc, create_fitness_record(gen, 0.5))
        end)

      # Should be at patience threshold (window_size * 2 + patience = 9 generations)
      assert PlateauDetector.plateau_detected?(detector)
      assert detector.patience_counter >= 5
    end
  end

  describe "threshold testing" do
    test "uses relative improvement threshold" do
      detector =
        PlateauDetector.new(
          window_size: 2,
          patience: 2,
          improvement_threshold: 0.10
        )

      # 5% improvement (below 10% threshold)
      # Need sustained stagnation to trigger patience
      detector =
        detector
        |> PlateauDetector.update(create_fitness_record(1, 1.0))
        |> PlateauDetector.update(create_fitness_record(2, 1.0))
        |> PlateauDetector.update(create_fitness_record(3, 1.05))
        |> PlateauDetector.update(create_fitness_record(4, 1.05))
        |> PlateauDetector.update(create_fitness_record(5, 1.05))
        |> PlateauDetector.update(create_fitness_record(6, 1.05))
        |> PlateauDetector.update(create_fitness_record(7, 1.05))
        |> PlateauDetector.update(create_fitness_record(8, 1.05))

      assert PlateauDetector.plateau_detected?(detector)
    end

    test "uses absolute improvement threshold" do
      detector =
        PlateauDetector.new(
          window_size: 2,
          patience: 2,
          absolute_threshold: 0.01,
          improvement_threshold: 0.0
        )

      # 0.005 absolute improvement (below 0.01 threshold)
      # Need sustained stagnation to trigger patience
      detector =
        detector
        |> PlateauDetector.update(create_fitness_record(1, 0.500))
        |> PlateauDetector.update(create_fitness_record(2, 0.500))
        |> PlateauDetector.update(create_fitness_record(3, 0.505))
        |> PlateauDetector.update(create_fitness_record(4, 0.505))
        |> PlateauDetector.update(create_fitness_record(5, 0.505))
        |> PlateauDetector.update(create_fitness_record(6, 0.505))
        |> PlateauDetector.update(create_fitness_record(7, 0.505))
        |> PlateauDetector.update(create_fitness_record(8, 0.505))

      assert PlateauDetector.plateau_detected?(detector)
    end

    test "detects improvement when either threshold exceeded" do
      detector =
        PlateauDetector.new(
          window_size: 2,
          patience: 2,
          improvement_threshold: 0.05,
          absolute_threshold: 0.01
        )

      # Small absolute but large relative improvement
      detector =
        detector
        |> PlateauDetector.update(create_fitness_record(1, 0.01))
        |> PlateauDetector.update(create_fitness_record(2, 0.01))
        |> PlateauDetector.update(create_fitness_record(3, 0.015))
        |> PlateauDetector.update(create_fitness_record(4, 0.015))

      # 50% relative improvement should prevent plateau
      refute PlateauDetector.plateau_detected?(detector)
    end
  end

  describe "window size variations" do
    test "larger window size requires more stable plateau" do
      small_window = PlateauDetector.new(window_size: 2, patience: 2)
      large_window = PlateauDetector.new(window_size: 5, patience: 2)

      # Same stagnant data
      records =
        Enum.map(1..12, fn gen ->
          create_fitness_record(gen, 0.5)
        end)

      small_detector = Enum.reduce(records, small_window, &PlateauDetector.update(&2, &1))
      large_detector = Enum.reduce(records, large_window, &PlateauDetector.update(&2, &1))

      # Both should detect plateau but at different rates
      assert PlateauDetector.plateau_detected?(small_detector)
      assert PlateauDetector.plateau_detected?(large_detector)

      # Small window detects earlier (less history needed)
      assert small_detector.patience_counter >= large_detector.patience_counter
    end

    test "small window is more sensitive to recent changes" do
      detector = PlateauDetector.new(window_size: 2, patience: 2)

      # Long stagnation
      detector =
        Enum.reduce(1..8, detector, fn gen, acc ->
          PlateauDetector.update(acc, create_fitness_record(gen, 0.5))
        end)

      # Recent improvement
      detector =
        detector
        |> PlateauDetector.update(create_fitness_record(9, 0.6))
        |> PlateauDetector.update(create_fitness_record(10, 0.65))

      # Should reset quickly with small window
      assert detector.patience_counter == 0
      refute detector.plateau_detected
    end
  end

  describe "plateau_detected?/1" do
    test "returns false for new detector" do
      detector = PlateauDetector.new()
      refute PlateauDetector.plateau_detected?(detector)
    end

    test "returns true when plateau detected" do
      detector = PlateauDetector.new(window_size: 2, patience: 2)

      detector =
        Enum.reduce(1..8, detector, fn gen, acc ->
          PlateauDetector.update(acc, create_fitness_record(gen, 0.5))
        end)

      assert PlateauDetector.plateau_detected?(detector)
    end
  end

  describe "get_patience_count/1" do
    test "returns current patience counter" do
      detector = PlateauDetector.new()
      assert PlateauDetector.get_patience_count(detector) == 0
    end

    test "tracks patience counter as plateau develops" do
      detector = PlateauDetector.new(window_size: 2, patience: 5)

      detector =
        Enum.reduce(1..6, detector, fn gen, acc ->
          PlateauDetector.update(acc, create_fitness_record(gen, 0.5))
        end)

      patience_count = PlateauDetector.get_patience_count(detector)
      assert patience_count > 0
      assert patience_count <= 5
    end
  end

  describe "reset/1" do
    test "clears all history and counters" do
      detector = PlateauDetector.new(window_size: 2, patience: 2)

      detector =
        Enum.reduce(1..10, detector, fn gen, acc ->
          PlateauDetector.update(acc, create_fitness_record(gen, 0.5))
        end)

      assert PlateauDetector.plateau_detected?(detector)
      assert length(detector.fitness_history) > 0

      detector = PlateauDetector.reset(detector)

      refute PlateauDetector.plateau_detected?(detector)
      assert detector.fitness_history == []
      assert detector.patience_counter == 0
    end

    test "preserves configuration after reset" do
      detector = PlateauDetector.new(window_size: 10, patience: 8)

      detector =
        Enum.reduce(1..15, detector, fn gen, acc ->
          PlateauDetector.update(acc, create_fitness_record(gen, 0.5))
        end)

      detector = PlateauDetector.reset(detector)

      assert detector.window_size == 10
      assert detector.patience == 8
    end
  end

  describe "edge cases" do
    test "handles zero baseline fitness gracefully" do
      detector = PlateauDetector.new(window_size: 2, patience: 2)

      detector =
        detector
        |> PlateauDetector.update(create_fitness_record(1, 0.0))
        |> PlateauDetector.update(create_fitness_record(2, 0.0))
        |> PlateauDetector.update(create_fitness_record(3, 0.0))
        |> PlateauDetector.update(create_fitness_record(4, 0.0))
        |> PlateauDetector.update(create_fitness_record(5, 0.0))
        |> PlateauDetector.update(create_fitness_record(6, 0.0))

      # Should detect plateau even with zero fitness
      assert PlateauDetector.plateau_detected?(detector)
    end

    test "handles negative fitness values" do
      detector = PlateauDetector.new(window_size: 2, patience: 2)

      detector =
        Enum.reduce(1..8, detector, fn gen, acc ->
          PlateauDetector.update(acc, create_fitness_record(gen, -0.5))
        end)

      # Should still detect plateau
      assert PlateauDetector.plateau_detected?(detector)
    end

    test "handles fitness declining" do
      detector = PlateauDetector.new(window_size: 2, patience: 2)

      # Declining fitness
      detector =
        Enum.reduce(1..8, detector, fn gen, acc ->
          fitness = 1.0 - gen * 0.05
          PlateauDetector.update(acc, create_fitness_record(gen, fitness))
        end)

      # Declining fitness is not improving
      assert PlateauDetector.plateau_detected?(detector)
    end

    test "handles very small fitness differences" do
      detector =
        PlateauDetector.new(
          window_size: 2,
          patience: 2,
          absolute_threshold: 1.0e-10,
          improvement_threshold: 1.0e-10
        )

      base = 0.123456789

      detector =
        Enum.reduce(1..8, detector, fn gen, acc ->
          fitness = base + gen * 1.0e-12
          PlateauDetector.update(acc, create_fitness_record(gen, fitness))
        end)

      # Should detect plateau with tiny improvements
      assert PlateauDetector.plateau_detected?(detector)
    end

    test "handles large fitness jumps" do
      detector = PlateauDetector.new(window_size: 2, patience: 2)

      detector =
        detector
        |> PlateauDetector.update(create_fitness_record(1, 0.1))
        |> PlateauDetector.update(create_fitness_record(2, 0.1))
        |> PlateauDetector.update(create_fitness_record(3, 10.0))
        |> PlateauDetector.update(create_fitness_record(4, 10.0))

      # Large jump should reset patience
      refute PlateauDetector.plateau_detected?(detector)
    end

    test "handles alternating fitness values" do
      detector = PlateauDetector.new(window_size: 2, patience: 3)

      detector =
        Enum.reduce(1..10, detector, fn gen, acc ->
          fitness = if rem(gen, 2) == 0, do: 0.6, else: 0.5
          PlateauDetector.update(acc, create_fitness_record(gen, fitness))
        end)

      # Oscillation should not show clear improvement
      assert PlateauDetector.plateau_detected?(detector)
    end
  end

  # Helper functions

  defp create_fitness_record(generation, best_fitness) do
    %FitnessRecord{
      generation: generation,
      best_fitness: best_fitness,
      mean_fitness: best_fitness * 0.9,
      median_fitness: best_fitness * 0.92,
      std_dev: 0.05
    }
  end
end
