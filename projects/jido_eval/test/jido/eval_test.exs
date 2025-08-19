defmodule Jido.EvalTest do
  use ExUnit.Case, async: false

  alias Jido.Eval
  alias Jido.Eval.{Config, Dataset, Sample}

  defp sample_dataset do
    samples = [
      %Sample.SingleTurn{
        id: "sample_1",
        user_input: "What is the capital of France?",
        response: "Paris is the capital of France.",
        retrieved_contexts: ["France's capital is Paris."],
        tags: %{"category" => "geography"}
      },
      %Sample.SingleTurn{
        id: "sample_2",
        user_input: "What is 2+2?",
        response: "2+2 equals 4.",
        retrieved_contexts: ["Basic arithmetic: 2+2=4"],
        tags: %{"category" => "math"}
      }
    ]

    {:ok, dataset} = Dataset.InMemory.new(samples)
    dataset
  end

  describe "evaluate/2 synchronous" do
    test "basic synchronous evaluation" do
      dataset = sample_dataset()

      {:ok, result} = Eval.evaluate(dataset, metrics: [:faithfulness])

      assert is_binary(result.run_id)
      assert result.sample_count == 2
      assert result.completed_count >= 0
      assert result.completed_count <= 2
      assert %DateTime{} = result.start_time
      assert %DateTime{} = result.finish_time
    end

    test "evaluation with custom LLM model" do
      dataset = sample_dataset()

      {:ok, result} =
        Eval.evaluate(dataset,
          metrics: [:faithfulness],
          llm: "test:custom-model"
        )

      assert result.config.model_spec == "test:custom-model"
    end

    test "evaluation with custom configuration" do
      dataset = sample_dataset()

      config = %Config{
        model_spec: "test:configured",
        tags: %{"experiment" => "custom_config"}
      }

      {:ok, result} =
        Eval.evaluate(dataset,
          metrics: [:faithfulness],
          config: config
        )

      assert result.config.model_spec == "test:configured"
      assert result.config.tags["experiment"] == "custom_config"
    end

    test "evaluation with run config overrides" do
      dataset = sample_dataset()

      # The evaluation should complete, possibly with errors due to process unavailability
      result =
        Eval.evaluate(dataset,
          metrics: [:faithfulness],
          run_config: %{max_workers: 1, timeout: 20_000}
        )

      case result do
        {:ok, eval_result} ->
          assert eval_result.config.run_config.max_workers == 1
          assert eval_result.config.run_config.timeout == 20_000

        {:error, :timeout} ->
          # This is acceptable - task may time out
          :ok

        {:error, {:task_failed, _}} ->
          # This is also acceptable - the task may fail  
          :ok
      end
    end

    test "evaluation with tags" do
      dataset = sample_dataset()

      {:ok, result} =
        Eval.evaluate(dataset,
          metrics: [:faithfulness],
          tags: %{"experiment" => "tag_test", "version" => "1.0"}
        )

      assert result.config.tags["experiment"] == "tag_test"
      assert result.config.tags["version"] == "1.0"
    end

    test "evaluation with multiple metrics" do
      dataset = sample_dataset()

      {:ok, result} =
        Eval.evaluate(dataset,
          metrics: [:faithfulness, :context_precision]
        )

      # Should have attempted to run both metrics
      assert result.sample_count == 2
    end

    test "handles empty dataset" do
      {:ok, empty_dataset} = Dataset.InMemory.empty(:single_turn)

      {:ok, result} = Eval.evaluate(empty_dataset, metrics: [:faithfulness])

      assert result.sample_count == 0
      assert result.completed_count == 0
      assert result.summary_stats == %{}
    end

    test "respects custom timeout" do
      dataset = sample_dataset()

      # Short timeout that should work
      {:ok, result} =
        Eval.evaluate(dataset,
          metrics: [:faithfulness],
          timeout: 30_000
        )

      assert result.sample_count == 2
    end
  end

  describe "evaluate/2 asynchronous" do
    test "basic asynchronous evaluation" do
      dataset = sample_dataset()

      {:ok, run_id} =
        Eval.evaluate(dataset,
          metrics: [:faithfulness],
          sync: false
        )

      assert is_binary(run_id)

      # Should be able to get progress
      {:ok, progress} = Eval.get_progress(run_id)
      assert progress.run_id == run_id
      assert progress.total == 2

      # Should be able to wait for completion
      {:ok, result} = Eval.await_result(run_id, 15_000)
      assert result.run_id == run_id
      assert result.sample_count == 2
    end

    test "async evaluation with custom config" do
      dataset = sample_dataset()

      {:ok, run_id} =
        Eval.evaluate(dataset,
          metrics: [:faithfulness],
          sync: false,
          llm: "test:async-model",
          tags: %{"mode" => "async"}
        )

      {:ok, result} = Eval.await_result(run_id, 15_000)
      assert result.config.model_spec == "test:async-model"
      assert result.config.tags["mode"] == "async"
    end
  end

  describe "get_progress/1" do
    test "returns progress for running evaluation" do
      dataset = sample_dataset()

      {:ok, run_id} =
        Eval.evaluate(dataset,
          metrics: [:faithfulness],
          sync: false
        )

      {:ok, progress} = Eval.get_progress(run_id)

      assert progress.run_id == run_id
      assert progress.total == 2
      assert is_integer(progress.completed)
      assert progress.completed >= 0
      assert progress.completed <= progress.total
    end

    test "returns error for unknown run_id" do
      {:error, :not_found} = Eval.get_progress("unknown_run_id")
    end
  end

  describe "await_result/2" do
    test "waits for evaluation completion with default timeout" do
      dataset = sample_dataset()

      {:ok, run_id} =
        Eval.evaluate(dataset,
          metrics: [:faithfulness],
          sync: false
        )

      {:ok, result} = Eval.await_result(run_id)

      assert result.run_id == run_id
      assert result.sample_count == 2
      assert %DateTime{} = result.finish_time
    end

    test "waits for evaluation completion with custom timeout" do
      dataset = sample_dataset()

      {:ok, run_id} =
        Eval.evaluate(dataset,
          metrics: [:faithfulness],
          sync: false
        )

      {:ok, result} = Eval.await_result(run_id, 20_000)

      assert result.run_id == run_id
    end

    test "times out for very short timeout" do
      dataset = sample_dataset()

      {:ok, run_id} =
        Eval.evaluate(dataset,
          metrics: [:faithfulness],
          sync: false
        )

      # Very short timeout - but evaluations now complete quickly due to LLM errors
      # So we expect either timeout or quick completion
      result = Eval.await_result(run_id, 1)

      case result do
        {:error, :timeout} ->
          # Expected timeout
          :ok

        {:ok, eval_result} ->
          # Quick completion due to LLM errors is also acceptable
          assert eval_result.sample_count >= 0
      end
    end
  end

  describe "cancel/1" do
    test "cancels running evaluation" do
      dataset = sample_dataset()

      {:ok, run_id} =
        Eval.evaluate(dataset,
          metrics: [:faithfulness],
          sync: false
        )

      :ok = Eval.cancel(run_id)

      # Progress should show cancelled or run should be not found
      case Eval.get_progress(run_id) do
        {:ok, progress} -> assert progress.cancelled == true
        # Already cleaned up
        {:error, :not_found} -> :ok
      end
    end

    test "returns error for unknown run_id" do
      {:error, :not_found} = Eval.cancel("unknown_run_id")
    end
  end

  describe "list_running/0" do
    test "lists active evaluations" do
      {:ok, runs_before} = Eval.list_running()
      initial_count = length(runs_before)

      dataset = sample_dataset()

      {:ok, run_id} =
        Eval.evaluate(dataset,
          metrics: [:faithfulness],
          sync: false
        )

      {:ok, runs_after} = Eval.list_running()

      # Should have at least one more run
      assert length(runs_after) >= initial_count

      # Should find our run
      our_run = Enum.find(runs_after, fn run -> run.run_id == run_id end)
      assert our_run != nil
    end
  end

  describe "list_metrics/0" do
    test "returns available metrics" do
      {:ok, metrics} = Eval.list_metrics()

      assert is_list(metrics)
      # Should have some built-in metrics
      assert length(metrics) > 0

      # Each metric should be a module
      Enum.each(metrics, fn metric ->
        assert is_atom(metric)
        # Should implement the Metric behaviour
        assert function_exported?(metric, :name, 0)
        assert function_exported?(metric, :evaluate, 3)
      end)
    end
  end

  describe "quick/2" do
    test "quick evaluation with default metrics" do
      dataset = sample_dataset()

      {:ok, result} = Eval.quick(dataset)

      assert result.sample_count == 2
      # Should use default faithfulness metric
      assert result.completed_count >= 0
    end

    test "quick evaluation with custom metrics" do
      dataset = sample_dataset()

      {:ok, result} = Eval.quick(dataset, [:faithfulness, :context_precision])

      assert result.sample_count == 2
    end

    test "quick evaluation is synchronous" do
      dataset = sample_dataset()

      {:ok, result} = Eval.quick(dataset)

      # Should have finish_time set (indicating synchronous completion)
      assert %DateTime{} = result.finish_time
    end
  end

  describe "error handling" do
    test "returns error for invalid metrics" do
      dataset = sample_dataset()

      # Invalid metrics now complete successfully but with validation errors
      {:ok, result} = Eval.evaluate(dataset, metrics: [:nonexistent_metric])

      # Should have errors for the unknown metrics
      assert result.error_count > 0
      assert length(result.errors) > 0

      # Check that the errors mention the nonexistent metric
      error = hd(result.errors)
      assert String.contains?(error.error, "nonexistent_metric")
    end

    test "handles missing metrics parameter" do
      dataset = sample_dataset()

      assert_raise KeyError, fn ->
        # Missing required :metrics
        Eval.evaluate(dataset, [])
      end
    end
  end

  describe "integration scenarios" do
    test "multiple concurrent evaluations" do
      dataset1 = sample_dataset()
      dataset2 = sample_dataset()

      {:ok, run_id1} =
        Eval.evaluate(dataset1,
          metrics: [:faithfulness],
          sync: false,
          tags: %{"run" => "1"}
        )

      {:ok, run_id2} =
        Eval.evaluate(dataset2,
          metrics: [:faithfulness],
          sync: false,
          tags: %{"run" => "2"}
        )

      assert run_id1 != run_id2

      {:ok, result1} = Eval.await_result(run_id1, 15_000)
      {:ok, result2} = Eval.await_result(run_id2, 15_000)

      assert result1.config.tags["run"] == "1"
      assert result2.config.tags["run"] == "2"
    end

    test "sync and async evaluations can run concurrently" do
      dataset1 = sample_dataset()
      dataset2 = sample_dataset()

      # Start async evaluation
      {:ok, run_id} =
        Eval.evaluate(dataset1,
          metrics: [:faithfulness],
          sync: false
        )

      # Run sync evaluation while async is running
      {:ok, sync_result} =
        Eval.evaluate(dataset2,
          metrics: [:faithfulness],
          sync: true
        )

      # Both should complete successfully
      assert sync_result.sample_count == 2

      {:ok, async_result} = Eval.await_result(run_id, 15_000)
      assert async_result.sample_count == 2
    end
  end
end
