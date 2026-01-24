defmodule Jido.AI.TRM.ACTTest do
  use ExUnit.Case, async: true

  alias Jido.AI.TRM.ACT

  describe "new/1" do
    test "creates default ACT state" do
      state = ACT.new()

      assert state.threshold == 0.9
      assert state.current_confidence == 0.0
      assert state.history == []
    end

    test "creates ACT state with custom threshold" do
      state = ACT.new(0.85)

      assert state.threshold == 0.85
      assert state.current_confidence == 0.0
      assert state.history == []
    end

    test "clamps threshold to valid range" do
      assert ACT.new(1.5).threshold == 1.0
      assert ACT.new(-0.1).threshold == 0.0
    end
  end

  describe "update/2" do
    test "updates current confidence" do
      state = ACT.new()
      updated = ACT.update(state, 0.7)

      assert updated.current_confidence == 0.7
    end

    test "adds confidence to history" do
      state = ACT.new()
      updated = state |> ACT.update(0.5) |> ACT.update(0.6) |> ACT.update(0.7)

      assert updated.history == [0.5, 0.6, 0.7]
      assert updated.current_confidence == 0.7
    end

    test "clamps confidence values" do
      state = ACT.new()
      updated = ACT.update(state, 1.5)

      assert updated.current_confidence == 1.0
      assert updated.history == [1.0]
    end
  end

  describe "calculate_confidence/2" do
    test "combines latent confidence and quality score" do
      latent_state = %{confidence_score: 0.8}
      quality_score = 0.9

      # 0.6 * 0.9 + 0.4 * 0.8 = 0.54 + 0.32 = 0.86
      confidence = ACT.calculate_confidence(latent_state, quality_score)

      assert_in_delta confidence, 0.86, 0.001
    end

    test "handles missing latent confidence" do
      latent_state = %{}
      quality_score = 0.8

      # 0.6 * 0.8 + 0.4 * 0.0 = 0.48
      confidence = ACT.calculate_confidence(latent_state, quality_score)

      assert_in_delta confidence, 0.48, 0.001
    end

    test "handles nil latent state" do
      confidence = ACT.calculate_confidence(nil, 0.8)

      assert confidence == 0.8
    end

    test "clamps result to valid range" do
      latent_state = %{confidence_score: 1.5}
      confidence = ACT.calculate_confidence(latent_state, 1.5)

      assert confidence <= 1.0
    end
  end

  describe "should_halt?/2" do
    test "returns true when confidence exceeds threshold" do
      assert ACT.should_halt?(0.95, 0.9) == true
      assert ACT.should_halt?(0.9, 0.9) == true
    end

    test "returns false when confidence below threshold" do
      assert ACT.should_halt?(0.85, 0.9) == false
      assert ACT.should_halt?(0.0, 0.9) == false
    end

    test "handles edge cases" do
      assert ACT.should_halt?(0.0, 0.0) == true
      assert ACT.should_halt?(1.0, 1.0) == true
    end
  end

  describe "update_confidence_history/2" do
    test "appends to existing history" do
      history = [0.5, 0.6]
      updated = ACT.update_confidence_history(history, 0.7)

      assert updated == [0.5, 0.6, 0.7]
    end

    test "starts new history from empty list" do
      updated = ACT.update_confidence_history([], 0.5)

      assert updated == [0.5]
    end

    test "handles nil history" do
      updated = ACT.update_confidence_history(nil, 0.5)

      assert updated == [0.5]
    end

    test "clamps values" do
      updated = ACT.update_confidence_history([0.5], 1.5)

      assert updated == [0.5, 1.0]
    end
  end

  describe "detect_convergence/1" do
    test "detects plateaued improvements" do
      # Very small range in last 3 values
      history = [0.5, 0.7, 0.72, 0.73, 0.73]

      assert ACT.detect_convergence(history) == true
    end

    test "returns false for improving history" do
      history = [0.5, 0.6, 0.7, 0.8]

      assert ACT.detect_convergence(history) == false
    end

    test "returns false for insufficient history" do
      assert ACT.detect_convergence([0.5]) == false
      assert ACT.detect_convergence([0.5, 0.5]) == false
    end

    test "returns false for empty history" do
      assert ACT.detect_convergence([]) == false
    end

    test "handles nil input" do
      assert ACT.detect_convergence(nil) == false
    end
  end

  describe "detect_convergence/3 with custom parameters" do
    test "uses custom window size" do
      history = [0.5, 0.6, 0.7, 0.71, 0.72]

      # With default window 3, last 3 values [0.7, 0.71, 0.72] have range 0.02
      assert ACT.detect_convergence(history, 3, 0.03) == true
      assert ACT.detect_convergence(history, 3, 0.01) == false
    end

    test "uses custom epsilon" do
      history = [0.7, 0.75, 0.8]

      # Range is 0.1
      assert ACT.detect_convergence(history, 3, 0.15) == true
      assert ACT.detect_convergence(history, 3, 0.05) == false
    end
  end

  describe "make_decision/2" do
    test "halts when threshold exceeded" do
      state = %{threshold: 0.9, current_confidence: 0.95, history: [0.8, 0.9, 0.95]}

      assert ACT.make_decision(state, %{}) == {:halt, :threshold_exceeded}
    end

    test "halts on convergence" do
      state = %{threshold: 0.95, current_confidence: 0.7, history: [0.68, 0.69, 0.7]}

      assert ACT.make_decision(state, %{}) == {:halt, :convergence_detected}
    end

    test "halts at max improvement" do
      state = %{threshold: 1.0, current_confidence: 0.99, history: [0.95, 0.97, 0.99]}

      assert ACT.make_decision(state, %{}) == {:halt, :max_improvement_reached}
    end

    test "continues with expected improvement" do
      state = %{threshold: 0.9, current_confidence: 0.7, history: [0.5, 0.6, 0.7]}

      assert {:continue, %{expected_improvement: improvement}} = ACT.make_decision(state, %{})
      assert is_float(improvement)
      assert improvement > 0
    end

    test "handles invalid state" do
      assert ACT.make_decision(nil, %{}) == {:continue, %{expected_improvement: 0.1}}
    end
  end

  describe "calculate_expected_improvement/1" do
    test "calculates from improvement trend" do
      # Each step improves by 0.1
      history = [0.5, 0.6, 0.7, 0.8]

      expected = ACT.calculate_expected_improvement(history)

      # Average improvement is 0.1, with decay factor 0.8 = 0.08
      assert_in_delta expected, 0.08, 0.01
    end

    test "handles decreasing improvements" do
      # Improvements are getting smaller
      history = [0.5, 0.7, 0.8, 0.85]

      expected = ACT.calculate_expected_improvement(history)

      assert expected > 0
      assert expected < 0.2
    end

    test "returns default for short history" do
      assert ACT.calculate_expected_improvement([0.5]) == 0.1
      assert ACT.calculate_expected_improvement([]) == 0.1
    end

    test "handles nil input" do
      assert ACT.calculate_expected_improvement(nil) == 0.1
    end
  end

  describe "get_halt_reason/1" do
    test "returns threshold_exceeded" do
      state = %{threshold: 0.9, current_confidence: 0.95, history: [0.8, 0.9, 0.95]}

      assert ACT.get_halt_reason(state) == :threshold_exceeded
    end

    test "returns convergence_detected" do
      state = %{threshold: 0.95, current_confidence: 0.7, history: [0.69, 0.695, 0.7]}

      assert ACT.get_halt_reason(state) == :convergence_detected
    end

    test "returns max_improvement_reached" do
      state = %{threshold: 1.0, current_confidence: 0.99, history: [0.9, 0.95, 0.99]}

      assert ACT.get_halt_reason(state) == :max_improvement_reached
    end

    test "returns nil when should continue" do
      state = %{threshold: 0.9, current_confidence: 0.7, history: [0.5, 0.6, 0.7]}

      assert ACT.get_halt_reason(state) == nil
    end

    test "handles invalid state" do
      assert ACT.get_halt_reason(nil) == nil
    end
  end

  describe "improvement_rate/1" do
    test "calculates average improvement" do
      # Each step improves by 0.1
      history = [0.5, 0.6, 0.7, 0.8]

      rate = ACT.improvement_rate(history)

      assert_in_delta rate, 0.1, 0.001
    end

    test "handles varying improvements" do
      history = [0.5, 0.7, 0.8, 0.85]
      # Deltas: 0.2, 0.1, 0.05 -> avg = 0.1167

      rate = ACT.improvement_rate(history)

      assert_in_delta rate, 0.1167, 0.01
    end

    test "returns 0 for insufficient history" do
      assert ACT.improvement_rate([0.5]) == 0.0
      assert ACT.improvement_rate([]) == 0.0
    end
  end

  describe "total_improvement/1" do
    test "calculates total gain" do
      history = [0.5, 0.6, 0.7, 0.8]

      assert_in_delta ACT.total_improvement(history), 0.3, 0.001
    end

    test "handles negative improvement" do
      history = [0.8, 0.7, 0.6]

      # Returns 0 for negative improvement
      assert ACT.total_improvement(history) == 0.0
    end

    test "returns 0 for insufficient history" do
      assert ACT.total_improvement([0.5]) == 0.0
      assert ACT.total_improvement([]) == 0.0
    end
  end

  describe "estimated_steps_remaining/3" do
    test "estimates steps to reach target" do
      # At 0.1 improvement per step, need steps to go from 0.7 to 0.9
      current = 0.7
      target = 0.9
      history = [0.5, 0.6, 0.7]

      steps = ACT.estimated_steps_remaining(current, target, history)

      # Should estimate 2-3 steps based on recent improvement rate
      assert steps >= 2 and steps <= 3
    end

    test "returns 0 when already at or above target" do
      assert ACT.estimated_steps_remaining(0.9, 0.9, [0.8, 0.9]) == 0
      assert ACT.estimated_steps_remaining(0.95, 0.9, [0.9, 0.95]) == 0
    end

    test "returns infinity for stalled improvement" do
      # Flat history, no improvement
      history = [0.5, 0.5, 0.5]

      steps = ACT.estimated_steps_remaining(0.5, 0.9, history)

      assert steps == :infinity
    end
  end

  describe "integration scenarios" do
    test "typical TRM session progression" do
      state = ACT.new(0.9)

      # Step 1: Initial reasoning
      state = ACT.update(state, 0.5)
      assert ACT.make_decision(state, %{}) == {:continue, %{expected_improvement: 0.1}}

      # Step 2: Improvement
      state = ACT.update(state, 0.65)
      assert {:continue, _} = ACT.make_decision(state, %{})

      # Step 3: More improvement
      state = ACT.update(state, 0.78)
      assert {:continue, _} = ACT.make_decision(state, %{})

      # Step 4: Near threshold
      state = ACT.update(state, 0.88)
      assert {:continue, _} = ACT.make_decision(state, %{})

      # Step 5: Exceeds threshold
      state = ACT.update(state, 0.92)
      assert ACT.make_decision(state, %{}) == {:halt, :threshold_exceeded}
    end

    test "convergence detection stops early" do
      state = ACT.new(0.95)

      # Very small improvements that trigger convergence (range < 0.02)
      state = ACT.update(state, 0.7)
      state = ACT.update(state, 0.705)
      state = ACT.update(state, 0.71)

      # Converged - improvements are minimal (range is 0.01)
      assert ACT.make_decision(state, %{}) == {:halt, :convergence_detected}
    end

    test "calculates expected improvement during session" do
      state = ACT.new(0.95)

      state = ACT.update(state, 0.5)
      state = ACT.update(state, 0.6)
      state = ACT.update(state, 0.7)
      state = ACT.update(state, 0.8)

      {:continue, %{expected_improvement: improvement}} = ACT.make_decision(state, %{})

      # With consistent 0.1 improvements, expected is 0.08 (0.1 * 0.8 decay)
      assert_in_delta improvement, 0.08, 0.01
    end
  end
end
