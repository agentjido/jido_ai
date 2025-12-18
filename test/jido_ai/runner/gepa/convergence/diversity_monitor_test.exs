defmodule Jido.AI.Runner.GEPA.Convergence.DiversityMonitorTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Runner.GEPA.Convergence.DiversityMonitor
  alias Jido.AI.Runner.GEPA.Diversity.DiversityMetrics

  describe "new/1" do
    test "creates monitor with default configuration" do
      monitor = DiversityMonitor.new()

      assert monitor.critical_threshold == 0.15
      assert monitor.warning_threshold == 0.30
      assert monitor.trend_window == 5
      assert monitor.patience == 3
      assert monitor.max_history == 100
      assert monitor.diversity_collapsed == false
      assert monitor.patience_counter == 0
      assert monitor.trend == :unknown
      assert monitor.diversity_history == []
    end

    test "accepts custom configuration" do
      monitor =
        DiversityMonitor.new(
          critical_threshold: 0.10,
          warning_threshold: 0.25,
          trend_window: 10,
          patience: 5
        )

      assert monitor.critical_threshold == 0.10
      assert monitor.warning_threshold == 0.25
      assert monitor.trend_window == 10
      assert monitor.patience == 5
    end

    test "stores configuration in config field" do
      monitor = DiversityMonitor.new(custom_param: :value)

      assert monitor.config[:custom_param] == :value
    end
  end

  describe "update/2" do
    test "adds diversity record to history" do
      monitor = DiversityMonitor.new()
      metrics = create_diversity_metrics(1, 0.65, :healthy)

      monitor = DiversityMonitor.update(monitor, metrics)

      assert length(monitor.diversity_history) == 1
      assert hd(monitor.diversity_history).generation == 1
      assert hd(monitor.diversity_history).pairwise_diversity == 0.65
    end

    test "accepts map as diversity metrics" do
      monitor = DiversityMonitor.new()
      metrics_map = %{generation: 1, pairwise_diversity: 0.65, diversity_level: :healthy}

      monitor = DiversityMonitor.update(monitor, metrics_map)

      assert length(monitor.diversity_history) == 1
      assert hd(monitor.diversity_history).pairwise_diversity == 0.65
    end

    test "maintains history in reverse chronological order" do
      monitor = DiversityMonitor.new()

      monitor =
        monitor
        |> DiversityMonitor.update(create_diversity_metrics(1, 0.65, :healthy))
        |> DiversityMonitor.update(create_diversity_metrics(2, 0.60, :healthy))
        |> DiversityMonitor.update(create_diversity_metrics(3, 0.55, :moderate))

      assert length(monitor.diversity_history) == 3
      assert hd(monitor.diversity_history).generation == 3
      assert Enum.at(monitor.diversity_history, -1).generation == 1
    end

    test "trims history to max_history size" do
      monitor = DiversityMonitor.new(max_history: 3)

      monitor =
        Enum.reduce(1..5, monitor, fn gen, acc ->
          DiversityMonitor.update(acc, create_diversity_metrics(gen, 0.5, :moderate))
        end)

      assert length(monitor.diversity_history) == 3
      assert hd(monitor.diversity_history).generation == 5
      assert Enum.at(monitor.diversity_history, -1).generation == 3
    end
  end

  describe "collapse detection with healthy diversity" do
    test "does not detect collapse when diversity remains high" do
      monitor = DiversityMonitor.new(critical_threshold: 0.15, patience: 3)

      # Maintain healthy diversity
      monitor =
        Enum.reduce(1..10, monitor, fn gen, acc ->
          DiversityMonitor.update(acc, create_diversity_metrics(gen, 0.65, :healthy))
        end)

      refute DiversityMonitor.diversity_collapsed?(monitor)
      assert monitor.patience_counter == 0
    end

    test "resets patience counter when diversity improves" do
      monitor = DiversityMonitor.new(critical_threshold: 0.15, patience: 3)

      # Start with low diversity
      monitor =
        monitor
        |> DiversityMonitor.update(create_diversity_metrics(1, 0.10, :critical))
        |> DiversityMonitor.update(create_diversity_metrics(2, 0.10, :critical))

      assert monitor.patience_counter == 2

      # Then improve
      monitor =
        monitor
        |> DiversityMonitor.update(create_diversity_metrics(3, 0.50, :healthy))
        |> DiversityMonitor.update(create_diversity_metrics(4, 0.55, :healthy))

      # Patience should reset
      assert monitor.patience_counter == 0
      refute monitor.diversity_collapsed
    end

    test "does not trigger collapse without sufficient patience" do
      monitor = DiversityMonitor.new(critical_threshold: 0.15, patience: 5)

      # Low diversity but not enough generations
      monitor =
        Enum.reduce(1..3, monitor, fn gen, acc ->
          DiversityMonitor.update(acc, create_diversity_metrics(gen, 0.10, :critical))
        end)

      refute DiversityMonitor.diversity_collapsed?(monitor)
      assert monitor.patience_counter == 3
      assert monitor.patience_counter < monitor.patience
    end
  end

  describe "collapse detection with poor diversity" do
    test "detects collapse when diversity drops below threshold" do
      monitor = DiversityMonitor.new(critical_threshold: 0.15, patience: 3)

      # Initial good diversity
      monitor =
        Enum.reduce(1..3, monitor, fn gen, acc ->
          DiversityMonitor.update(acc, create_diversity_metrics(gen, 0.60, :healthy))
        end)

      # Then collapse
      monitor =
        Enum.reduce(4..8, monitor, fn gen, acc ->
          DiversityMonitor.update(acc, create_diversity_metrics(gen, 0.10, :critical))
        end)

      assert DiversityMonitor.diversity_collapsed?(monitor)
      assert monitor.patience_counter >= monitor.patience
    end

    test "respects patience parameter" do
      monitor = DiversityMonitor.new(critical_threshold: 0.15, patience: 5)

      # Low diversity for exactly patience generations
      monitor =
        Enum.reduce(1..5, monitor, fn gen, acc ->
          DiversityMonitor.update(acc, create_diversity_metrics(gen, 0.10, :critical))
        end)

      # Should be at patience threshold
      assert DiversityMonitor.diversity_collapsed?(monitor)
      assert monitor.patience_counter >= 5
    end

    test "detects gradual diversity decline" do
      monitor = DiversityMonitor.new(critical_threshold: 0.15, patience: 2)

      # Gradual decline from healthy to critical
      monitor =
        [0.70, 0.60, 0.50, 0.40, 0.30, 0.20, 0.10, 0.08, 0.05]
        |> Enum.with_index(1)
        |> Enum.reduce(monitor, fn {diversity, gen}, acc ->
          level = diversity_level(diversity)
          DiversityMonitor.update(acc, create_diversity_metrics(gen, diversity, level))
        end)

      assert DiversityMonitor.diversity_collapsed?(monitor)
    end
  end

  describe "threshold testing" do
    test "uses critical threshold for collapse detection" do
      monitor = DiversityMonitor.new(critical_threshold: 0.20, patience: 2)

      # Just below custom threshold
      monitor =
        Enum.reduce(1..4, monitor, fn gen, acc ->
          DiversityMonitor.update(acc, create_diversity_metrics(gen, 0.18, :low))
        end)

      assert DiversityMonitor.diversity_collapsed?(monitor)
    end

    test "does not collapse when above threshold" do
      monitor = DiversityMonitor.new(critical_threshold: 0.15, patience: 2)

      # Just above threshold
      monitor =
        Enum.reduce(1..5, monitor, fn gen, acc ->
          DiversityMonitor.update(acc, create_diversity_metrics(gen, 0.16, :low))
        end)

      refute DiversityMonitor.diversity_collapsed?(monitor)
      assert monitor.patience_counter == 0
    end

    test "warning threshold does not trigger collapse" do
      monitor =
        DiversityMonitor.new(critical_threshold: 0.15, warning_threshold: 0.30, patience: 2)

      # Between warning and critical
      monitor =
        Enum.reduce(1..5, monitor, fn gen, acc ->
          DiversityMonitor.update(acc, create_diversity_metrics(gen, 0.20, :low))
        end)

      refute DiversityMonitor.diversity_collapsed?(monitor)
      assert DiversityMonitor.in_warning_zone?(monitor)
    end
  end

  describe "trend analysis" do
    test "detects increasing diversity trend" do
      monitor = DiversityMonitor.new(trend_window: 5)

      # Increasing diversity
      monitor =
        [0.20, 0.25, 0.30, 0.35, 0.40, 0.45, 0.50]
        |> Enum.with_index(1)
        |> Enum.reduce(monitor, fn {diversity, gen}, acc ->
          level = diversity_level(diversity)
          DiversityMonitor.update(acc, create_diversity_metrics(gen, diversity, level))
        end)

      assert DiversityMonitor.get_trend(monitor) == :increasing
    end

    test "detects decreasing diversity trend" do
      monitor = DiversityMonitor.new(trend_window: 5)

      # Decreasing diversity
      monitor =
        [0.70, 0.65, 0.60, 0.55, 0.50, 0.45, 0.40]
        |> Enum.with_index(1)
        |> Enum.reduce(monitor, fn {diversity, gen}, acc ->
          level = diversity_level(diversity)
          DiversityMonitor.update(acc, create_diversity_metrics(gen, diversity, level))
        end)

      assert DiversityMonitor.get_trend(monitor) == :decreasing
    end

    test "detects stable diversity trend" do
      monitor = DiversityMonitor.new(trend_window: 5)

      # Stable diversity (small fluctuations)
      monitor =
        [0.50, 0.51, 0.49, 0.50, 0.51, 0.50, 0.49]
        |> Enum.with_index(1)
        |> Enum.reduce(monitor, fn {diversity, gen}, acc ->
          DiversityMonitor.update(acc, create_diversity_metrics(gen, diversity, :moderate))
        end)

      assert DiversityMonitor.get_trend(monitor) == :stable
    end

    test "returns unknown trend with insufficient history" do
      monitor = DiversityMonitor.new(trend_window: 5)

      # Only 3 data points
      monitor =
        Enum.reduce(1..3, monitor, fn gen, acc ->
          DiversityMonitor.update(acc, create_diversity_metrics(gen, 0.50, :moderate))
        end)

      assert DiversityMonitor.get_trend(monitor) == :unknown
    end

    test "uses configured trend window size" do
      small_window = DiversityMonitor.new(trend_window: 3)
      large_window = DiversityMonitor.new(trend_window: 7)

      # Same data
      data = [0.70, 0.65, 0.60, 0.55, 0.50, 0.45, 0.40, 0.35]

      small_monitor =
        data
        |> Enum.with_index(1)
        |> Enum.reduce(small_window, fn {diversity, gen}, acc ->
          level = diversity_level(diversity)
          DiversityMonitor.update(acc, create_diversity_metrics(gen, diversity, level))
        end)

      large_monitor =
        data
        |> Enum.with_index(1)
        |> Enum.reduce(large_window, fn {diversity, gen}, acc ->
          level = diversity_level(diversity)
          DiversityMonitor.update(acc, create_diversity_metrics(gen, diversity, level))
        end)

      # Both should detect decreasing trend
      assert DiversityMonitor.get_trend(small_monitor) == :decreasing
      assert DiversityMonitor.get_trend(large_monitor) == :decreasing
    end
  end

  describe "get_current_diversity/1" do
    test "returns nil for new monitor" do
      monitor = DiversityMonitor.new()
      assert DiversityMonitor.get_current_diversity(monitor) == nil
    end

    test "returns most recent diversity value" do
      monitor = DiversityMonitor.new()

      monitor =
        monitor
        |> DiversityMonitor.update(create_diversity_metrics(1, 0.50, :moderate))
        |> DiversityMonitor.update(create_diversity_metrics(2, 0.60, :healthy))
        |> DiversityMonitor.update(create_diversity_metrics(3, 0.55, :healthy))

      assert DiversityMonitor.get_current_diversity(monitor) == 0.55
    end
  end

  describe "in_warning_zone?/1" do
    test "returns false for healthy diversity" do
      monitor = DiversityMonitor.new(critical_threshold: 0.15, warning_threshold: 0.30)

      monitor = DiversityMonitor.update(monitor, create_diversity_metrics(1, 0.65, :healthy))

      refute DiversityMonitor.in_warning_zone?(monitor)
    end

    test "returns true when between warning and critical thresholds" do
      monitor = DiversityMonitor.new(critical_threshold: 0.15, warning_threshold: 0.30)

      monitor = DiversityMonitor.update(monitor, create_diversity_metrics(1, 0.20, :low))

      assert DiversityMonitor.in_warning_zone?(monitor)
    end

    test "returns false when below critical threshold" do
      monitor = DiversityMonitor.new(critical_threshold: 0.15, warning_threshold: 0.30)

      monitor = DiversityMonitor.update(monitor, create_diversity_metrics(1, 0.10, :critical))

      refute DiversityMonitor.in_warning_zone?(monitor)
    end

    test "returns false when above warning threshold" do
      monitor = DiversityMonitor.new(critical_threshold: 0.15, warning_threshold: 0.30)

      monitor = DiversityMonitor.update(monitor, create_diversity_metrics(1, 0.45, :moderate))

      refute DiversityMonitor.in_warning_zone?(monitor)
    end

    test "returns false for new monitor" do
      monitor = DiversityMonitor.new()
      refute DiversityMonitor.in_warning_zone?(monitor)
    end
  end

  describe "diversity_collapsed?/1" do
    test "returns false for new monitor" do
      monitor = DiversityMonitor.new()
      refute DiversityMonitor.diversity_collapsed?(monitor)
    end

    test "returns true when collapse detected" do
      monitor = DiversityMonitor.new(critical_threshold: 0.15, patience: 2)

      monitor =
        Enum.reduce(1..4, monitor, fn gen, acc ->
          DiversityMonitor.update(acc, create_diversity_metrics(gen, 0.10, :critical))
        end)

      assert DiversityMonitor.diversity_collapsed?(monitor)
    end
  end

  describe "reset/1" do
    test "clears all history and counters" do
      monitor = DiversityMonitor.new(critical_threshold: 0.15, patience: 2)

      monitor =
        Enum.reduce(1..5, monitor, fn gen, acc ->
          DiversityMonitor.update(acc, create_diversity_metrics(gen, 0.10, :critical))
        end)

      assert DiversityMonitor.diversity_collapsed?(monitor)
      assert length(monitor.diversity_history) > 0

      monitor = DiversityMonitor.reset(monitor)

      refute DiversityMonitor.diversity_collapsed?(monitor)
      assert monitor.diversity_history == []
      assert monitor.patience_counter == 0
      assert monitor.trend == :unknown
    end

    test "preserves configuration after reset" do
      monitor = DiversityMonitor.new(critical_threshold: 0.20, patience: 5, trend_window: 8)

      monitor =
        Enum.reduce(1..10, monitor, fn gen, acc ->
          DiversityMonitor.update(acc, create_diversity_metrics(gen, 0.10, :critical))
        end)

      monitor = DiversityMonitor.reset(monitor)

      assert monitor.critical_threshold == 0.20
      assert monitor.patience == 5
      assert monitor.trend_window == 8
    end
  end

  describe "edge cases" do
    test "handles zero diversity gracefully" do
      monitor = DiversityMonitor.new(critical_threshold: 0.15, patience: 2)

      monitor =
        Enum.reduce(1..4, monitor, fn gen, acc ->
          DiversityMonitor.update(acc, create_diversity_metrics(gen, 0.0, :critical))
        end)

      # Should detect collapse with zero diversity
      assert DiversityMonitor.diversity_collapsed?(monitor)
      assert DiversityMonitor.get_current_diversity(monitor) == 0.0
    end

    test "handles perfect diversity" do
      monitor = DiversityMonitor.new()

      monitor =
        Enum.reduce(1..5, monitor, fn gen, acc ->
          DiversityMonitor.update(acc, create_diversity_metrics(gen, 1.0, :excellent))
        end)

      refute DiversityMonitor.diversity_collapsed?(monitor)
      assert DiversityMonitor.get_trend(monitor) == :stable
    end

    test "handles diversity at exact threshold" do
      monitor = DiversityMonitor.new(critical_threshold: 0.15, patience: 2)

      # Exactly at threshold
      monitor =
        Enum.reduce(1..4, monitor, fn gen, acc ->
          DiversityMonitor.update(acc, create_diversity_metrics(gen, 0.15, :low))
        end)

      # Should not trigger (threshold is exclusive: < not <=)
      refute DiversityMonitor.diversity_collapsed?(monitor)
    end

    test "handles oscillating diversity" do
      monitor = DiversityMonitor.new(trend_window: 5)

      # Oscillating between high and low
      monitor =
        [0.70, 0.20, 0.65, 0.25, 0.70, 0.20, 0.65]
        |> Enum.with_index(1)
        |> Enum.reduce(monitor, fn {diversity, gen}, acc ->
          level = diversity_level(diversity)
          DiversityMonitor.update(acc, create_diversity_metrics(gen, diversity, level))
        end)

      # Trend should be relatively stable (oscillations cancel out)
      assert DiversityMonitor.get_trend(monitor) in [:stable, :increasing, :decreasing]
    end

    test "handles very small diversity differences" do
      monitor = DiversityMonitor.new(trend_window: 5)

      # Very small changes
      base = 0.5

      monitor =
        Enum.reduce(1..8, monitor, fn gen, acc ->
          diversity = base + gen * 0.001
          DiversityMonitor.update(acc, create_diversity_metrics(gen, diversity, :moderate))
        end)

      # Small positive slope should still be detected as stable (< 0.01)
      assert DiversityMonitor.get_trend(monitor) == :stable
    end

    test "handles rapid diversity recovery" do
      monitor = DiversityMonitor.new(critical_threshold: 0.15, patience: 3)

      # Crash then recover
      monitor =
        monitor
        |> DiversityMonitor.update(create_diversity_metrics(1, 0.05, :critical))
        |> DiversityMonitor.update(create_diversity_metrics(2, 0.05, :critical))
        |> DiversityMonitor.update(create_diversity_metrics(3, 0.70, :excellent))

      # Should not declare collapse due to quick recovery
      refute DiversityMonitor.diversity_collapsed?(monitor)
      assert monitor.patience_counter == 0
    end
  end

  describe "integration with DiversityMetrics" do
    test "accepts full DiversityMetrics struct" do
      monitor = DiversityMonitor.new()

      metrics = %DiversityMetrics{
        pairwise_diversity: 0.65,
        entropy: 1.2,
        coverage: 0.85,
        uniqueness_ratio: 0.90,
        clustering_coefficient: 0.15,
        convergence_risk: 0.20,
        diversity_level: :healthy,
        metadata: %{generation: 5, population_size: 20}
      }

      monitor = DiversityMonitor.update(monitor, metrics)

      assert length(monitor.diversity_history) == 1
      record = hd(monitor.diversity_history)
      assert record.pairwise_diversity == 0.65
      assert record.diversity_level == :healthy
      assert record.convergence_risk == 0.20
      assert record.generation == 5
    end

    test "extracts generation from metrics metadata" do
      monitor = DiversityMonitor.new()

      metrics = %DiversityMetrics{
        pairwise_diversity: 0.55,
        diversity_level: :moderate,
        metadata: %{generation: 42}
      }

      monitor = DiversityMonitor.update(monitor, metrics)

      assert hd(monitor.diversity_history).generation == 42
    end
  end

  # Helper functions

  defp create_diversity_metrics(generation, pairwise_diversity, diversity_level) do
    %{
      generation: generation,
      pairwise_diversity: pairwise_diversity,
      diversity_level: diversity_level,
      convergence_risk: 1.0 - pairwise_diversity
    }
  end

  defp diversity_level(diversity) when diversity >= 0.70, do: :excellent
  defp diversity_level(diversity) when diversity >= 0.50, do: :healthy
  defp diversity_level(diversity) when diversity >= 0.30, do: :moderate
  defp diversity_level(diversity) when diversity >= 0.15, do: :low
  defp diversity_level(_diversity), do: :critical
end
