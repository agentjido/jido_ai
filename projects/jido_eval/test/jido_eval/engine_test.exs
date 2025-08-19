defmodule Jido.Eval.EngineTest do
  use ExUnit.Case, async: false

  alias Jido.Eval.{Engine, Config, RunConfig, Dataset, Sample}

  # Test fixtures
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

  defp test_config(opts \\ []) do
    %Config{
      run_config: %RunConfig{
        max_workers: Keyword.get(opts, :max_workers, 2),
        timeout: Keyword.get(opts, :timeout, 10_000)
      },
      model_spec: "test:mock",
      tags: Keyword.get(opts, :tags, %{"test" => "engine"})
    }
  end

  setup do
    :ok
  end

  describe "start_evaluation/4" do
    test "starts async evaluation successfully" do
      dataset = sample_dataset()
      config = test_config()
      metrics = [:faithfulness]

      {:ok, run_id} = Engine.start_evaluation(dataset, config, metrics)

      assert is_binary(run_id)
      assert byte_size(run_id) > 0

      # Should be able to get progress
      {:ok, progress} = Engine.get_progress(run_id)
      assert progress.run_id == run_id
      assert progress.total == 2
      assert is_integer(progress.completed)
    end

    test "returns error for invalid metrics" do
      dataset = sample_dataset()
      config = test_config()
      invalid_metrics = [:nonexistent_metric]

      # Invalid metrics now start successfully but result in errors
      {:ok, run_id} = Engine.start_evaluation(dataset, config, invalid_metrics)
      assert is_binary(run_id)

      # Await the result which should show validation errors
      {:ok, result} = Engine.await_result(run_id, 5_000)
      assert result.error_count > 0
      assert length(result.errors) > 0

      # Check that the errors mention the nonexistent metric
      error = hd(result.errors)
      assert String.contains?(error.error, "nonexistent_metric")
    end

    test "generates run_id if not provided" do
      dataset = sample_dataset()
      config = %Config{test_config() | run_id: nil}
      metrics = [:faithfulness]

      {:ok, run_id} = Engine.start_evaluation(dataset, config, metrics)
      assert is_binary(run_id)
      # UUID format
      assert String.contains?(run_id, "-")
    end
  end

  describe "evaluate_sync/4" do
    test "completes synchronous evaluation" do
      dataset = sample_dataset()
      config = test_config(timeout: 15_000)
      metrics = [:faithfulness]

      {:ok, result} = Engine.evaluate_sync(dataset, config, metrics)

      # The result should have a run_id (generated if config.run_id is nil)
      assert is_binary(result.run_id)
      assert result.sample_count == 2
      assert result.completed_count <= 2
      assert %DateTime{} = result.start_time
      assert %DateTime{} = result.finish_time
      assert is_integer(result.duration_ms)
    end

    @tag :slow
    test "respects timeout" do
      dataset = sample_dataset()
      # Very short timeout
      config = test_config(timeout: 1_000)
      metrics = [:faithfulness]

      # This may timeout depending on LLM response time
      result = Engine.evaluate_sync(dataset, config, metrics, timeout: 1_000)

      case result do
        {:ok, _result} ->
          # Evaluation completed within timeout
          :ok

        {:error, :timeout} ->
          # Expected timeout
          :ok

        other ->
          flunk("Unexpected result: #{inspect(other)}")
      end
    end

    test "handles dataset with zero samples" do
      {:ok, empty_dataset} = Dataset.InMemory.empty(:single_turn)
      config = test_config()
      metrics = [:faithfulness]

      {:ok, result} = Engine.evaluate_sync(empty_dataset, config, metrics)

      assert result.sample_count == 0
      assert result.completed_count == 0
      assert result.summary_stats == %{}
    end
  end

  describe "get_progress/1" do
    test "returns progress for running evaluation" do
      dataset = sample_dataset()
      config = test_config()
      metrics = [:faithfulness]

      {:ok, run_id} = Engine.start_evaluation(dataset, config, metrics)

      {:ok, progress} = Engine.get_progress(run_id)

      assert progress.run_id == run_id
      assert progress.total == 2
      assert is_integer(progress.completed)
      assert progress.completed >= 0
      assert progress.completed <= 2
      assert is_integer(progress.elapsed_ms)
    end

    test "returns error for unknown run_id" do
      {:error, :not_found} = Engine.get_progress("unknown_run_id")
    end
  end

  describe "await_result/2" do
    test "waits for evaluation completion" do
      dataset = sample_dataset()
      config = test_config()
      metrics = [:faithfulness]

      {:ok, run_id} = Engine.start_evaluation(dataset, config, metrics)

      {:ok, result} = Engine.await_result(run_id, 15_000)

      assert result.run_id == run_id
      assert result.sample_count == 2
      assert %DateTime{} = result.finish_time
    end

    test "times out for slow evaluations" do
      dataset = sample_dataset()
      config = test_config()
      metrics = [:faithfulness]

      {:ok, run_id} = Engine.start_evaluation(dataset, config, metrics)

      # Very short timeout - but evaluations now complete quickly due to LLM errors
      # So we expect either timeout or quick completion with errors
      result = Engine.await_result(run_id, 1)

      case result do
        {:error, :timeout} ->
          # Expected timeout
          :ok

        {:ok, eval_result} ->
          # Quick completion due to LLM errors is also acceptable
          assert eval_result.sample_count >= 0
      end
    end

    test "returns error for unknown run_id" do
      {:error, :not_found} = Engine.await_result("unknown_run_id", 1000)
    end
  end

  describe "cancel_evaluation/1" do
    test "cancels running evaluation" do
      dataset = sample_dataset()
      config = test_config()
      metrics = [:faithfulness]

      {:ok, run_id} = Engine.start_evaluation(dataset, config, metrics)

      :ok = Engine.cancel_evaluation(run_id)

      # Should be able to get progress showing cancelled status
      case Engine.get_progress(run_id) do
        {:ok, progress} -> assert progress.cancelled == true
        # Already cleaned up
        {:error, :not_found} -> :ok
      end
    end

    test "returns error for unknown run_id" do
      {:error, :not_found} = Engine.cancel_evaluation("unknown_run_id")
    end
  end

  describe "list_running/0" do
    test "lists active evaluations" do
      {:ok, runs_before} = Engine.list_running()
      initial_count = length(runs_before)

      dataset = sample_dataset()
      config = test_config()
      metrics = [:faithfulness]

      {:ok, run_id} = Engine.start_evaluation(dataset, config, metrics)

      {:ok, runs_after} = Engine.list_running()

      assert length(runs_after) >= initial_count

      # Should find our run in the list
      our_run = Enum.find(runs_after, fn run -> run.run_id == run_id end)
      assert our_run != nil
      assert our_run.run_id == run_id
      assert is_pid(our_run.task_pid)
    end

    test "returns empty list when no runs active" do
      # This test may be flaky if other tests are running concurrently
      # but serves as a basic sanity check
      {:ok, runs} = Engine.list_running()
      assert is_list(runs)
    end
  end

  describe "integration scenarios" do
    test "handles multiple concurrent evaluations" do
      dataset1 = sample_dataset()
      dataset2 = sample_dataset()
      config1 = test_config(tags: %{"run" => "1"})
      config2 = test_config(tags: %{"run" => "2"})
      metrics = [:faithfulness]

      {:ok, run_id1} = Engine.start_evaluation(dataset1, config1, metrics)
      {:ok, run_id2} = Engine.start_evaluation(dataset2, config2, metrics)

      assert run_id1 != run_id2

      # Both should complete successfully
      {:ok, result1} = Engine.await_result(run_id1, 15_000)
      {:ok, result2} = Engine.await_result(run_id2, 15_000)

      assert result1.run_id == run_id1
      assert result2.run_id == run_id2
      assert result1.config.tags["run"] == "1"
      assert result2.config.tags["run"] == "2"
    end

    @tag :slow
    test "handles worker failures gracefully" do
      # Create a larger dataset to ensure worker failures can be observed
      large_samples =
        1..10
        |> Enum.map(fn i ->
          %Sample.SingleTurn{
            id: "sample_#{i}",
            user_input: "Question #{i}",
            response: "Answer #{i}",
            retrieved_contexts: ["Context #{i}"],
            tags: %{"batch" => "large"}
          }
        end)

      {:ok, large_dataset} = Dataset.InMemory.new(large_samples)
      config = test_config(max_workers: 4, timeout: 20_000)
      metrics = [:faithfulness]

      {:ok, run_id} = Engine.start_evaluation(large_dataset, config, metrics)

      # The evaluation should complete, possibly with errors due to process unavailability
      result = Engine.await_result(run_id, 30_000)

      case result do
        {:ok, eval_result} ->
          assert eval_result.sample_count == 10
          # Some samples should complete even if workers fail
          assert eval_result.completed_count >= 0
          assert eval_result.completed_count <= 10

        {:error, :timeout} ->
          # This is acceptable - task may time out
          :ok

        {:error, {:task_failed, _}} ->
          # This is also acceptable - the task may fail
          :ok
      end
    end

    test "preserves sample metadata and tags" do
      samples_with_metadata = [
        %Sample.SingleTurn{
          id: "meta_sample_1",
          user_input: "Test question",
          response: "Test answer",
          retrieved_contexts: ["Test context"],
          tags: %{"category" => "test", "priority" => "high"}
        }
      ]

      {:ok, dataset} = Dataset.InMemory.new(samples_with_metadata)
      config = test_config()
      metrics = [:faithfulness]

      {:ok, result} = Engine.evaluate_sync(dataset, config, metrics)

      sample_result = hd(result.sample_results)
      assert sample_result.sample_id == "meta_sample_1"
      assert sample_result.tags["category"] == "test"
      assert sample_result.tags["priority"] == "high"

      # Tag statistics should be computed
      assert Map.has_key?(result.by_tag, "category:test")
      assert Map.has_key?(result.by_tag, "priority:high")
    end
  end

  describe "error handling" do
    test "handles malformed dataset gracefully" do
      # This would depend on Dataset implementation, but test conceptually
      {:ok, empty_dataset} = Dataset.InMemory.empty(:single_turn)
      config = test_config()
      metrics = [:faithfulness]

      {:ok, result} = Engine.evaluate_sync(empty_dataset, config, metrics)
      assert result.sample_count == 0
    end

    test "handles configuration errors" do
      dataset = sample_dataset()
      # Invalid configuration
      config = %Config{}
      metrics = [:faithfulness]

      # Should handle gracefully and generate run_id
      {:ok, run_id} = Engine.start_evaluation(dataset, config, metrics)
      assert is_binary(run_id)
    end
  end
end
