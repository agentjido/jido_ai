defmodule Jido.Eval.ResultTest do
  use ExUnit.Case, async: true

  alias Jido.Eval.{Result, Config}

  describe "new/2" do
    test "creates new result with run_id" do
      result = Result.new("test_run")

      assert result.run_id == "test_run"
      assert result.sample_count == 0
      assert result.completed_count == 0
      assert result.error_count == 0
      assert %DateTime{} = result.start_time
    end

    test "creates new result with config" do
      config = %Config{tags: %{"experiment" => "test"}}
      result = Result.new("test_run", config)

      assert result.config == config
      assert result.config.tags == %{"experiment" => "test"}
    end
  end

  describe "add_sample_result/2" do
    test "adds successful sample result" do
      result = Result.new("test_run")

      sample_result = %{
        sample_id: "sample_1",
        scores: %{faithfulness: 0.8, context_precision: 0.9},
        latency_ms: 1200,
        error: nil,
        tags: %{"category" => "qa"},
        metadata: %{}
      }

      updated = Result.add_sample_result(result, sample_result)

      assert updated.sample_count == 1
      assert updated.completed_count == 1
      assert updated.error_count == 0
      assert length(updated.sample_results) == 1
      assert hd(updated.sample_results) == sample_result
    end

    test "adds failed sample result" do
      result = Result.new("test_run")

      sample_result = %{
        sample_id: "sample_1",
        scores: %{},
        latency_ms: 500,
        error: "timeout after 30000ms",
        tags: %{},
        metadata: %{timeout: true}
      }

      updated = Result.add_sample_result(result, sample_result)

      assert updated.sample_count == 1
      assert updated.completed_count == 0
      assert updated.error_count == 1
      assert length(updated.errors) == 1

      error = hd(updated.errors)
      assert error.sample_id == "sample_1"
      assert error.error == "timeout after 30000ms"
      assert error.category == "timeout"
    end

    test "updates tag statistics" do
      result = Result.new("test_run")

      sample_result = %{
        sample_id: "sample_1",
        scores: %{faithfulness: 0.8},
        latency_ms: 1000,
        error: nil,
        tags: %{"difficulty" => "easy", "category" => "qa"},
        metadata: %{}
      }

      updated = Result.add_sample_result(result, sample_result)

      assert Map.has_key?(updated.by_tag, "difficulty:easy")
      assert Map.has_key?(updated.by_tag, "category:qa")

      difficulty_stats = updated.by_tag["difficulty:easy"]
      assert difficulty_stats[:total] == 1
      assert difficulty_stats[:completed] == 1
      assert difficulty_stats[:scores] == [0.8]
    end
  end

  describe "finalize/2" do
    test "calculates summary statistics" do
      result = Result.new("test_run")

      # Add multiple sample results
      samples = [
        %{
          sample_id: "s1",
          scores: %{faithfulness: 0.8},
          latency_ms: 1000,
          error: nil,
          tags: %{},
          metadata: %{}
        },
        %{
          sample_id: "s2",
          scores: %{faithfulness: 0.9},
          latency_ms: 1200,
          error: nil,
          tags: %{},
          metadata: %{}
        },
        %{
          sample_id: "s3",
          scores: %{faithfulness: 0.7},
          latency_ms: 800,
          error: nil,
          tags: %{},
          metadata: %{}
        }
      ]

      result_with_samples = Enum.reduce(samples, result, &Result.add_sample_result(&2, &1))
      finalized = Result.finalize(result_with_samples)

      assert finalized.finish_time != nil
      assert finalized.duration_ms != nil

      faithfulness_stats = finalized.summary_stats[:faithfulness]
      assert_in_delta faithfulness_stats.mean, 0.8, 0.001
      assert faithfulness_stats.median == 0.8
      assert faithfulness_stats.min == 0.7
      assert faithfulness_stats.max == 0.9
      assert faithfulness_stats.count == 3
    end

    test "calculates latency statistics" do
      result = Result.new("test_run")

      samples = [
        %{
          sample_id: "s1",
          scores: %{faithfulness: 0.8},
          latency_ms: 1000,
          error: nil,
          tags: %{},
          metadata: %{}
        },
        %{
          sample_id: "s2",
          scores: %{faithfulness: 0.9},
          latency_ms: 2000,
          error: nil,
          tags: %{},
          metadata: %{}
        },
        %{
          sample_id: "s3",
          scores: %{faithfulness: 0.7},
          latency_ms: 1500,
          error: nil,
          tags: %{},
          metadata: %{}
        }
      ]

      result_with_samples = Enum.reduce(samples, result, &Result.add_sample_result(&2, &1))
      finalized = Result.finalize(result_with_samples)

      assert finalized.latency.avg_ms == 1500.0
      assert finalized.latency.min_ms == 1000
      assert finalized.latency.max_ms == 2000
      assert finalized.latency.median_ms == 1500.0
    end

    test "calculates pass rate" do
      result = Result.new("test_run")

      # Mix of passing (>= 0.5) and failing (< 0.5) samples
      samples = [
        %{
          sample_id: "s1",
          scores: %{faithfulness: 0.8},
          latency_ms: 1000,
          error: nil,
          tags: %{},
          metadata: %{}
        },
        %{
          sample_id: "s2",
          scores: %{faithfulness: 0.3},
          latency_ms: 1000,
          error: nil,
          tags: %{},
          metadata: %{}
        },
        %{
          sample_id: "s3",
          scores: %{faithfulness: 0.7},
          latency_ms: 1000,
          error: nil,
          tags: %{},
          metadata: %{}
        }
      ]

      result_with_samples = Enum.reduce(samples, result, &Result.add_sample_result(&2, &1))
      finalized = Result.finalize(result_with_samples)

      # 2 out of 3 samples pass (scores >= 0.5)
      assert_in_delta finalized.pass_rate, 0.67, 0.01
    end

    test "categorizes errors" do
      result = Result.new("test_run")

      samples = [
        %{
          sample_id: "s1",
          scores: %{},
          latency_ms: 1000,
          error: "timeout",
          tags: %{},
          metadata: %{}
        },
        %{
          sample_id: "s2",
          scores: %{},
          latency_ms: 1000,
          error: "llm_error: rate limit",
          tags: %{},
          metadata: %{}
        },
        %{
          sample_id: "s3",
          scores: %{},
          latency_ms: 1000,
          error: "timeout",
          tags: %{},
          metadata: %{}
        }
      ]

      result_with_samples = Enum.reduce(samples, result, &Result.add_sample_result(&2, &1))
      finalized = Result.finalize(result_with_samples)

      assert finalized.error_categories["timeout"] == 2
      assert finalized.error_categories["llm_error"] == 1
    end

    test "finalizes tag statistics" do
      result = Result.new("test_run")

      samples = [
        %{
          sample_id: "s1",
          scores: %{faithfulness: 0.8},
          latency_ms: 1000,
          error: nil,
          tags: %{"difficulty" => "easy"},
          metadata: %{}
        },
        %{
          sample_id: "s2",
          scores: %{faithfulness: 0.9},
          latency_ms: 1000,
          error: nil,
          tags: %{"difficulty" => "easy"},
          metadata: %{}
        },
        %{
          sample_id: "s3",
          scores: %{},
          latency_ms: 1000,
          error: "timeout",
          tags: %{"difficulty" => "hard"},
          metadata: %{}
        }
      ]

      result_with_samples = Enum.reduce(samples, result, &Result.add_sample_result(&2, &1))
      finalized = Result.finalize(result_with_samples)

      easy_stats = finalized.by_tag["difficulty:easy"]
      assert easy_stats.sample_count == 2
      assert_in_delta easy_stats.avg_score, 0.85, 0.001
      assert easy_stats.pass_rate == 1.0
      assert easy_stats.error_rate == 0.0

      hard_stats = finalized.by_tag["difficulty:hard"]
      assert hard_stats.sample_count == 1
      assert hard_stats.avg_score == nil
      assert hard_stats.pass_rate == 0.0
      assert hard_stats.error_rate == 1.0
    end
  end

  describe "edge cases" do
    test "handles empty sample results" do
      result = Result.new("test_run")
      finalized = Result.finalize(result)

      assert finalized.summary_stats == %{}
      assert finalized.latency == %{}
      assert finalized.pass_rate == nil
      assert finalized.error_categories == %{}
    end

    test "handles samples with no scores" do
      result = Result.new("test_run")

      sample_result = %{
        sample_id: "sample_1",
        scores: %{},
        latency_ms: 1000,
        error: nil,
        tags: %{},
        metadata: %{}
      }

      result_with_sample = Result.add_sample_result(result, sample_result)
      finalized = Result.finalize(result_with_sample)

      assert finalized.summary_stats == %{}
      assert finalized.pass_rate == nil
    end

    test "handles mixed successful and failed samples" do
      result = Result.new("test_run")

      samples = [
        %{
          sample_id: "s1",
          scores: %{faithfulness: 0.8},
          latency_ms: 1000,
          error: nil,
          tags: %{},
          metadata: %{}
        },
        %{
          sample_id: "s2",
          scores: %{},
          latency_ms: 1000,
          error: "failed",
          tags: %{},
          metadata: %{}
        },
        %{
          sample_id: "s3",
          scores: %{faithfulness: 0.6},
          latency_ms: 1000,
          error: nil,
          tags: %{},
          metadata: %{}
        }
      ]

      result_with_samples = Enum.reduce(samples, result, &Result.add_sample_result(&2, &1))
      finalized = Result.finalize(result_with_samples)

      # Should only calculate stats from successful samples
      faithfulness_stats = finalized.summary_stats[:faithfulness]
      assert faithfulness_stats.count == 2
      assert faithfulness_stats.mean == 0.7

      assert finalized.completed_count == 2
      assert finalized.error_count == 1
    end
  end
end
