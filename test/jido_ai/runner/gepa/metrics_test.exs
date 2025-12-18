defmodule Jido.AI.Runner.GEPA.MetricsTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Runner.GEPA.Metrics
  alias Jido.AI.Runner.GEPA.Metrics.MetricValue

  describe "new/1" do
    test "creates a new metrics collector with default values" do
      metrics = Metrics.new()

      assert %Metrics{} = metrics
      assert metrics.values == %{}
      assert MapSet.size(metrics.task_ids) == 0
      assert metrics.metadata == %{}
      assert %DateTime{} = metrics.created_at
    end

    test "creates metrics with custom metadata" do
      metadata = %{prompt: "Test prompt", task_type: :reasoning}
      metrics = Metrics.new(metadata: metadata)

      assert metrics.metadata == metadata
    end

    test "sets created_at to current time" do
      before = DateTime.utc_now()
      metrics = Metrics.new()
      after_time = DateTime.utc_now()

      assert DateTime.compare(metrics.created_at, before) in [:gt, :eq]
      assert DateTime.compare(metrics.created_at, after_time) in [:lt, :eq]
    end
  end

  describe "add_metric/4" do
    test "adds a success_rate metric" do
      metrics = Metrics.new()
      metrics = Metrics.add_metric(metrics, :success_rate, 1.0)

      assert map_size(metrics.values) == 1
      assert Map.has_key?(metrics.values, :success_rate)

      [metric_value] = metrics.values[:success_rate]
      assert %MetricValue{} = metric_value
      assert metric_value.type == :success_rate
      assert metric_value.value == 1.0
      assert %DateTime{} = metric_value.timestamp
    end

    test "adds a latency metric" do
      metrics = Metrics.new()
      metrics = Metrics.add_metric(metrics, :latency, 1234)

      [metric_value] = metrics.values[:latency]
      assert metric_value.type == :latency
      assert metric_value.value == 1234
    end

    test "adds a quality_score metric" do
      metrics = Metrics.new()
      metrics = Metrics.add_metric(metrics, :quality_score, 0.85)

      [metric_value] = metrics.values[:quality_score]
      assert metric_value.type == :quality_score
      assert metric_value.value == 0.85
    end

    test "adds an accuracy metric" do
      metrics = Metrics.new()
      metrics = Metrics.add_metric(metrics, :accuracy, 0.92)

      [metric_value] = metrics.values[:accuracy]
      assert metric_value.type == :accuracy
      assert metric_value.value == 0.92
    end

    test "adds a custom metric" do
      metrics = Metrics.new()
      metrics = Metrics.add_metric(metrics, :custom, 42.5)

      [metric_value] = metrics.values[:custom]
      assert metric_value.type == :custom
      assert metric_value.value == 42.5
    end

    test "adds metric with task_id" do
      metrics = Metrics.new()
      metrics = Metrics.add_metric(metrics, :success_rate, 1.0, task_id: "task_1")

      [metric_value] = metrics.values[:success_rate]
      assert metric_value.task_id == "task_1"
      assert MapSet.member?(metrics.task_ids, "task_1")
    end

    test "adds metric with metadata" do
      metrics = Metrics.new()

      metrics =
        Metrics.add_metric(metrics, :latency, 1500, metadata: %{model: "gpt-4", attempt: 1})

      [metric_value] = metrics.values[:latency]
      assert metric_value.metadata == %{model: "gpt-4", attempt: 1}
    end

    test "adds metric with custom timestamp" do
      metrics = Metrics.new()
      custom_time = DateTime.utc_now()

      metrics = Metrics.add_metric(metrics, :success_rate, 1.0, timestamp: custom_time)

      [metric_value] = metrics.values[:success_rate]
      assert metric_value.timestamp == custom_time
    end

    test "accumulates multiple metrics of same type" do
      metrics = Metrics.new()

      metrics =
        metrics
        |> Metrics.add_metric(:success_rate, 1.0)
        |> Metrics.add_metric(:success_rate, 0.8)
        |> Metrics.add_metric(:success_rate, 0.9)

      assert length(metrics.values[:success_rate]) == 3

      values = Enum.map(metrics.values[:success_rate], & &1.value)
      assert values == [1.0, 0.8, 0.9]
    end

    test "accumulates multiple metrics of different types" do
      metrics = Metrics.new()

      metrics =
        metrics
        |> Metrics.add_metric(:success_rate, 1.0)
        |> Metrics.add_metric(:latency, 1234)
        |> Metrics.add_metric(:quality_score, 0.85)

      assert map_size(metrics.values) == 3
      assert Map.has_key?(metrics.values, :success_rate)
      assert Map.has_key?(metrics.values, :latency)
      assert Map.has_key?(metrics.values, :quality_score)
    end

    test "tracks multiple task IDs" do
      metrics = Metrics.new()

      metrics =
        metrics
        |> Metrics.add_metric(:success_rate, 1.0, task_id: "task_1")
        |> Metrics.add_metric(:success_rate, 0.9, task_id: "task_2")
        |> Metrics.add_metric(:latency, 1000, task_id: "task_1")

      assert MapSet.size(metrics.task_ids) == 2
      assert MapSet.member?(metrics.task_ids, "task_1")
      assert MapSet.member?(metrics.task_ids, "task_2")
    end

    test "preserves metric order" do
      metrics = Metrics.new()

      metrics =
        metrics
        |> Metrics.add_metric(:success_rate, 1.0, metadata: %{order: 1})
        |> Metrics.add_metric(:success_rate, 0.8, metadata: %{order: 2})
        |> Metrics.add_metric(:success_rate, 0.9, metadata: %{order: 3})

      orders = Enum.map(metrics.values[:success_rate], fn m -> m.metadata.order end)
      assert orders == [1, 2, 3]
    end
  end

  describe "aggregate/2" do
    test "aggregates statistics for single metric type" do
      metrics =
        Metrics.new()
        |> Metrics.add_metric(:success_rate, 1.0)
        |> Metrics.add_metric(:success_rate, 0.8)
        |> Metrics.add_metric(:success_rate, 0.9)

      aggregated = Metrics.aggregate(metrics)

      assert Map.has_key?(aggregated, :success_rate)
      stats = aggregated[:success_rate]

      assert stats.mean == 0.9
      assert stats.median == 0.9
      assert stats.min == 0.8
      assert stats.max == 1.0
      assert stats.count == 3
      assert is_float(stats.variance)
      assert is_float(stats.std_dev)
    end

    test "aggregates statistics for multiple metric types" do
      metrics =
        Metrics.new()
        |> Metrics.add_metric(:success_rate, 1.0)
        |> Metrics.add_metric(:success_rate, 0.9)
        |> Metrics.add_metric(:latency, 1000)
        |> Metrics.add_metric(:latency, 1500)
        |> Metrics.add_metric(:quality_score, 0.85)

      aggregated = Metrics.aggregate(metrics)

      assert map_size(aggregated) == 3
      assert Map.has_key?(aggregated, :success_rate)
      assert Map.has_key?(aggregated, :latency)
      assert Map.has_key?(aggregated, :quality_score)
    end

    test "filters by specific metric types" do
      metrics =
        Metrics.new()
        |> Metrics.add_metric(:success_rate, 1.0)
        |> Metrics.add_metric(:latency, 1000)
        |> Metrics.add_metric(:quality_score, 0.85)

      aggregated = Metrics.aggregate(metrics, types: [:success_rate, :quality_score])

      assert map_size(aggregated) == 2
      assert Map.has_key?(aggregated, :success_rate)
      assert Map.has_key?(aggregated, :quality_score)
      refute Map.has_key?(aggregated, :latency)
    end

    test "filters by task_id" do
      metrics =
        Metrics.new()
        |> Metrics.add_metric(:success_rate, 1.0, task_id: "task_1")
        |> Metrics.add_metric(:success_rate, 0.5, task_id: "task_2")
        |> Metrics.add_metric(:success_rate, 0.8, task_id: "task_1")

      aggregated = Metrics.aggregate(metrics, task_id: "task_1")

      stats = aggregated[:success_rate]
      assert stats.count == 2
      assert stats.mean == 0.9
    end

    test "calculates median for odd number of values" do
      metrics =
        Metrics.new()
        |> Metrics.add_metric(:quality_score, 0.7)
        |> Metrics.add_metric(:quality_score, 0.8)
        |> Metrics.add_metric(:quality_score, 0.9)

      aggregated = Metrics.aggregate(metrics)
      stats = aggregated[:quality_score]

      assert stats.median == 0.8
    end

    test "calculates median for even number of values" do
      metrics =
        Metrics.new()
        |> Metrics.add_metric(:quality_score, 0.7)
        |> Metrics.add_metric(:quality_score, 0.8)
        |> Metrics.add_metric(:quality_score, 0.9)
        |> Metrics.add_metric(:quality_score, 1.0)

      aggregated = Metrics.aggregate(metrics)
      stats = aggregated[:quality_score]

      assert_in_delta stats.median, 0.85, 0.0001
    end

    test "handles empty metrics collection" do
      metrics = Metrics.new()
      aggregated = Metrics.aggregate(metrics)

      assert aggregated == %{}
    end

    test "handles single value correctly" do
      metrics = Metrics.new() |> Metrics.add_metric(:success_rate, 0.95)

      aggregated = Metrics.aggregate(metrics)
      stats = aggregated[:success_rate]

      assert stats.mean == 0.95
      assert stats.median == 0.95
      assert stats.min == 0.95
      assert stats.max == 0.95
      assert stats.count == 1
      assert stats.variance == 0.0
      assert stats.std_dev == 0.0
    end
  end

  describe "confidence_interval/3" do
    test "calculates confidence interval for sufficient data" do
      metrics =
        Metrics.new()
        |> Metrics.add_metric(:success_rate, 0.9)
        |> Metrics.add_metric(:success_rate, 0.95)
        |> Metrics.add_metric(:success_rate, 0.92)
        |> Metrics.add_metric(:success_rate, 0.88)
        |> Metrics.add_metric(:success_rate, 0.93)

      ci = Metrics.confidence_interval(metrics, :success_rate)

      assert is_map(ci)
      assert is_float(ci.lower)
      assert is_float(ci.upper)
      assert is_float(ci.mean)
      assert ci.confidence == 0.95
      assert ci.sample_size == 5
      assert ci.lower <= ci.mean
      assert ci.mean <= ci.upper
    end

    test "calculates confidence interval with custom confidence level" do
      metrics =
        Metrics.new()
        |> Metrics.add_metric(:success_rate, 0.9)
        |> Metrics.add_metric(:success_rate, 0.95)
        |> Metrics.add_metric(:success_rate, 0.92)

      ci = Metrics.confidence_interval(metrics, :success_rate, confidence_level: 0.99)

      assert ci.confidence == 0.99
      # 99% CI should be wider than 95% CI
      ci_95 = Metrics.confidence_interval(metrics, :success_rate, confidence_level: 0.95)
      assert ci.upper - ci.lower >= ci_95.upper - ci_95.lower
    end

    test "returns nil for insufficient data (< 2 values)" do
      metrics = Metrics.new() |> Metrics.add_metric(:success_rate, 0.95)

      ci = Metrics.confidence_interval(metrics, :success_rate)

      assert is_nil(ci)
    end

    test "returns nil for empty metric type" do
      metrics = Metrics.new()

      ci = Metrics.confidence_interval(metrics, :success_rate)

      assert is_nil(ci)
    end

    test "filters by task_id" do
      metrics =
        Metrics.new()
        |> Metrics.add_metric(:success_rate, 0.9, task_id: "task_1")
        |> Metrics.add_metric(:success_rate, 0.95, task_id: "task_1")
        |> Metrics.add_metric(:success_rate, 0.5, task_id: "task_2")

      ci = Metrics.confidence_interval(metrics, :success_rate, task_id: "task_1")

      assert ci.sample_size == 2
      assert ci.mean == 0.925
    end

    test "clamps confidence interval to [0.0, 1.0] for rates" do
      # Values very close to 1.0 should not exceed 1.0 in upper bound
      metrics =
        Metrics.new()
        |> Metrics.add_metric(:success_rate, 0.99)
        |> Metrics.add_metric(:success_rate, 1.0)
        |> Metrics.add_metric(:success_rate, 1.0)

      ci = Metrics.confidence_interval(metrics, :success_rate)

      assert ci.lower >= 0.0
      assert ci.upper <= 1.0
    end
  end

  describe "calculate_fitness/2" do
    test "calculates fitness from multiple metric types with default weights" do
      metrics =
        Metrics.new()
        |> Metrics.add_metric(:success_rate, 1.0)
        |> Metrics.add_metric(:quality_score, 0.8)
        |> Metrics.add_metric(:accuracy, 0.9)
        |> Metrics.add_metric(:latency, 1000)

      fitness = Metrics.calculate_fitness(metrics)

      assert is_float(fitness)
      assert fitness >= 0.0
      assert fitness <= 1.0
    end

    test "calculates fitness with custom weights" do
      metrics =
        Metrics.new()
        |> Metrics.add_metric(:success_rate, 1.0)
        |> Metrics.add_metric(:quality_score, 0.5)

      # Heavily weight quality_score
      fitness =
        Metrics.calculate_fitness(metrics, weights: %{success_rate: 0.2, quality_score: 0.8})

      # Should be closer to 0.5 than 1.0 due to quality_score weight
      assert fitness < 0.7
    end

    test "normalizes latency (lower is better)" do
      # Low latency should contribute positively
      metrics_fast = Metrics.new() |> Metrics.add_metric(:latency, 100)
      fitness_fast = Metrics.calculate_fitness(metrics_fast)

      # High latency should contribute negatively
      metrics_slow = Metrics.new() |> Metrics.add_metric(:latency, 5000)
      fitness_slow = Metrics.calculate_fitness(metrics_slow)

      assert fitness_fast > fitness_slow
    end

    test "returns nil for empty metrics" do
      metrics = Metrics.new()
      fitness = Metrics.calculate_fitness(metrics)

      assert is_nil(fitness)
    end

    test "filters by task_id" do
      metrics =
        Metrics.new()
        |> Metrics.add_metric(:success_rate, 1.0, task_id: "task_1")
        |> Metrics.add_metric(:success_rate, 0.5, task_id: "task_2")
        |> Metrics.add_metric(:quality_score, 0.9, task_id: "task_1")
        |> Metrics.add_metric(:quality_score, 0.4, task_id: "task_2")

      fitness_task_1 = Metrics.calculate_fitness(metrics, task_id: "task_1")
      fitness_task_2 = Metrics.calculate_fitness(metrics, task_id: "task_2")

      assert fitness_task_1 > fitness_task_2
    end

    test "uses geometric mean when specified" do
      metrics =
        Metrics.new()
        |> Metrics.add_metric(:success_rate, 1.0)
        |> Metrics.add_metric(:quality_score, 0.8)

      fitness = Metrics.calculate_fitness(metrics, aggregation_method: :geometric_mean)

      assert is_float(fitness)
      assert fitness >= 0.0
      assert fitness <= 1.0
      # Geometric mean should be <= arithmetic mean
      fitness_weighted = Metrics.calculate_fitness(metrics, aggregation_method: :weighted_mean)
      assert fitness <= fitness_weighted + 0.01
    end

    test "handles single metric type" do
      metrics = Metrics.new() |> Metrics.add_metric(:success_rate, 0.95)

      fitness = Metrics.calculate_fitness(metrics)

      assert fitness == 0.95
    end
  end

  describe "get_stats/3" do
    test "returns statistics for specified metric type" do
      metrics =
        Metrics.new()
        |> Metrics.add_metric(:success_rate, 0.8)
        |> Metrics.add_metric(:success_rate, 0.9)
        |> Metrics.add_metric(:success_rate, 1.0)

      stats = Metrics.get_stats(metrics, :success_rate)

      assert is_map(stats)
      assert stats.mean == 0.9
      assert stats.count == 3
    end

    test "returns nil for non-existent metric type" do
      metrics = Metrics.new()

      stats = Metrics.get_stats(metrics, :success_rate)

      assert is_nil(stats)
    end

    test "filters by task_id" do
      metrics =
        Metrics.new()
        |> Metrics.add_metric(:success_rate, 1.0, task_id: "task_1")
        |> Metrics.add_metric(:success_rate, 0.5, task_id: "task_2")

      stats = Metrics.get_stats(metrics, :success_rate, task_id: "task_1")

      assert stats.count == 1
      assert stats.mean == 1.0
    end
  end

  describe "count/2" do
    test "returns count of metrics for a type" do
      metrics =
        Metrics.new()
        |> Metrics.add_metric(:success_rate, 1.0)
        |> Metrics.add_metric(:success_rate, 0.9)
        |> Metrics.add_metric(:success_rate, 0.8)

      count = Metrics.count(metrics, :success_rate)

      assert count == 3
    end

    test "returns 0 for non-existent metric type" do
      metrics = Metrics.new()

      count = Metrics.count(metrics, :success_rate)

      assert count == 0
    end

    test "counts across all tasks" do
      metrics =
        Metrics.new()
        |> Metrics.add_metric(:success_rate, 1.0, task_id: "task_1")
        |> Metrics.add_metric(:success_rate, 0.9, task_id: "task_2")

      count = Metrics.count(metrics, :success_rate)

      assert count == 2
    end
  end

  describe "task_ids/1" do
    test "returns all task IDs in metrics" do
      metrics =
        Metrics.new()
        |> Metrics.add_metric(:success_rate, 1.0, task_id: "task_1")
        |> Metrics.add_metric(:latency, 1000, task_id: "task_2")
        |> Metrics.add_metric(:quality_score, 0.85, task_id: "task_1")

      task_ids = Metrics.task_ids(metrics)

      assert MapSet.size(task_ids) == 2
      assert MapSet.member?(task_ids, "task_1")
      assert MapSet.member?(task_ids, "task_2")
    end

    test "returns empty set for metrics without task IDs" do
      metrics =
        Metrics.new()
        |> Metrics.add_metric(:success_rate, 1.0)

      task_ids = Metrics.task_ids(metrics)

      assert MapSet.size(task_ids) == 0
    end
  end

  describe "merge/1" do
    test "merges multiple metrics collections" do
      metrics1 =
        Metrics.new()
        |> Metrics.add_metric(:success_rate, 1.0, task_id: "task_1")
        |> Metrics.add_metric(:latency, 1000)

      metrics2 =
        Metrics.new()
        |> Metrics.add_metric(:success_rate, 0.9, task_id: "task_2")
        |> Metrics.add_metric(:quality_score, 0.85)

      merged = Metrics.merge([metrics1, metrics2])

      assert Metrics.count(merged, :success_rate) == 2
      assert Metrics.count(merged, :latency) == 1
      assert Metrics.count(merged, :quality_score) == 1
      assert MapSet.size(merged.task_ids) == 2
    end

    test "merges metrics of same type" do
      metrics1 = Metrics.new() |> Metrics.add_metric(:success_rate, 1.0)
      metrics2 = Metrics.new() |> Metrics.add_metric(:success_rate, 0.9)
      metrics3 = Metrics.new() |> Metrics.add_metric(:success_rate, 0.8)

      merged = Metrics.merge([metrics1, metrics2, metrics3])

      assert Metrics.count(merged, :success_rate) == 3

      stats = Metrics.get_stats(merged, :success_rate)
      assert stats.mean == 0.9
    end

    test "handles empty list" do
      merged = Metrics.merge([])

      assert %Metrics{} = merged
      assert merged.values == %{}
    end

    test "handles single metrics collection" do
      metrics = Metrics.new() |> Metrics.add_metric(:success_rate, 1.0)

      merged = Metrics.merge([metrics])

      assert Metrics.count(merged, :success_rate) == 1
    end

    test "merges metadata" do
      metrics1 = Metrics.new(metadata: %{source: "evaluator_1"})
      metrics2 = Metrics.new(metadata: %{source: "evaluator_2", extra: "data"})

      merged = Metrics.merge([metrics1, metrics2])

      assert is_map(merged.metadata)
    end
  end

  describe "integration scenarios" do
    test "complete evaluation metrics workflow" do
      # Collect metrics from multiple evaluation runs
      metrics = Metrics.new(metadata: %{prompt: "Solve this problem", task_type: :reasoning})

      # Run 1: Successful
      metrics =
        metrics
        |> Metrics.add_metric(:success_rate, 1.0, task_id: "task_1")
        |> Metrics.add_metric(:latency, 1200, task_id: "task_1")
        |> Metrics.add_metric(:quality_score, 0.9, task_id: "task_1")
        |> Metrics.add_metric(:accuracy, 0.95, task_id: "task_1")

      # Run 2: Partially successful
      metrics =
        metrics
        |> Metrics.add_metric(:success_rate, 0.8, task_id: "task_1")
        |> Metrics.add_metric(:latency, 1500, task_id: "task_1")
        |> Metrics.add_metric(:quality_score, 0.75, task_id: "task_1")
        |> Metrics.add_metric(:accuracy, 0.85, task_id: "task_1")

      # Run 3: Successful
      metrics =
        metrics
        |> Metrics.add_metric(:success_rate, 1.0, task_id: "task_1")
        |> Metrics.add_metric(:latency, 1100, task_id: "task_1")
        |> Metrics.add_metric(:quality_score, 0.85, task_id: "task_1")
        |> Metrics.add_metric(:accuracy, 0.9, task_id: "task_1")

      # Aggregate statistics
      aggregated = Metrics.aggregate(metrics, task_id: "task_1")

      assert_in_delta aggregated[:success_rate].mean, 0.9333333333333333, 0.0000001
      assert aggregated[:quality_score].count == 3

      # Calculate confidence intervals
      ci = Metrics.confidence_interval(metrics, :success_rate, task_id: "task_1")

      assert ci.sample_size == 3
      assert ci.confidence == 0.95

      # Calculate overall fitness
      fitness = Metrics.calculate_fitness(metrics, task_id: "task_1")

      assert is_float(fitness)
      assert fitness > 0.7
      assert fitness <= 1.0
    end

    test "multi-task evaluation workflow" do
      metrics = Metrics.new()

      # Task 1: Math problems (high success)
      metrics =
        metrics
        |> Metrics.add_metric(:success_rate, 1.0, task_id: "math_task")
        |> Metrics.add_metric(:success_rate, 0.9, task_id: "math_task")
        |> Metrics.add_metric(:quality_score, 0.95, task_id: "math_task")

      # Task 2: Reasoning problems (medium success)
      metrics =
        metrics
        |> Metrics.add_metric(:success_rate, 0.7, task_id: "reasoning_task")
        |> Metrics.add_metric(:success_rate, 0.8, task_id: "reasoning_task")
        |> Metrics.add_metric(:quality_score, 0.75, task_id: "reasoning_task")

      # Task 3: Code generation (low success)
      metrics =
        metrics
        |> Metrics.add_metric(:success_rate, 0.6, task_id: "code_task")
        |> Metrics.add_metric(:success_rate, 0.5, task_id: "code_task")
        |> Metrics.add_metric(:quality_score, 0.65, task_id: "code_task")

      # Verify task tracking
      task_ids = Metrics.task_ids(metrics)
      assert MapSet.size(task_ids) == 3

      # Calculate per-task fitness
      fitness_math = Metrics.calculate_fitness(metrics, task_id: "math_task")
      fitness_reasoning = Metrics.calculate_fitness(metrics, task_id: "reasoning_task")
      fitness_code = Metrics.calculate_fitness(metrics, task_id: "code_task")

      assert fitness_math > fitness_reasoning
      assert fitness_reasoning > fitness_code

      # Calculate overall fitness across all tasks
      overall_fitness = Metrics.calculate_fitness(metrics)
      assert is_float(overall_fitness)
    end

    test "statistical reliability with large sample" do
      metrics = Metrics.new()

      # Simulate 30 evaluation runs with varying success
      values = [
        0.95,
        0.92,
        0.88,
        0.91,
        0.94,
        0.87,
        0.93,
        0.90,
        0.89,
        0.96,
        0.91,
        0.93,
        0.88,
        0.92,
        0.94,
        0.90,
        0.91,
        0.89,
        0.93,
        0.92,
        0.90,
        0.91,
        0.94,
        0.88,
        0.92,
        0.93,
        0.91,
        0.89,
        0.92,
        0.90
      ]

      metrics =
        Enum.reduce(values, metrics, fn value, acc ->
          Metrics.add_metric(acc, :success_rate, value, task_id: "large_sample_task")
        end)

      # Aggregate statistics
      stats = Metrics.get_stats(metrics, :success_rate, task_id: "large_sample_task")

      assert stats.count == 30
      assert stats.mean >= 0.90 and stats.mean <= 0.92

      # Confidence interval should be tight with large sample
      ci =
        Metrics.confidence_interval(metrics, :success_rate,
          task_id: "large_sample_task",
          confidence_level: 0.95
        )

      margin_of_error = ci.upper - ci.lower
      assert margin_of_error < 0.05
    end

    test "handles failure scenarios gracefully" do
      metrics = Metrics.new()

      # Multiple failed evaluations
      metrics =
        metrics
        |> Metrics.add_metric(:success_rate, 0.0, metadata: %{reason: :timeout})
        |> Metrics.add_metric(:success_rate, 0.0, metadata: %{reason: :error})
        |> Metrics.add_metric(:success_rate, 0.0, metadata: %{reason: :crash})
        |> Metrics.add_metric(:quality_score, 0.0)
        |> Metrics.add_metric(:accuracy, 0.0)

      # Should still calculate valid statistics
      stats = Metrics.get_stats(metrics, :success_rate)
      assert stats.mean == 0.0
      assert stats.variance == 0.0

      # Fitness should reflect failures
      fitness = Metrics.calculate_fitness(metrics)
      assert fitness < 0.3
    end
  end
end
