defmodule Jido.AI.GEPA.EvaluatorTest do
  use ExUnit.Case, async: true

  alias Jido.AI.GEPA.{Evaluator, PromptVariant, Task}

  # ============================================================================
  # Test Helpers
  # ============================================================================

  # Simple mock runner that returns deterministic results
  defp mock_runner(template, input, _opts) do
    # Return the input as output for testing
    {:ok, %{output: "Answer: #{input}", tokens: 100}}
  end

  # Runner that simulates failures for specific inputs
  defp failing_runner(_template, input, _opts) do
    if String.contains?(input, "fail") do
      {:error, :simulated_failure}
    else
      {:ok, %{output: "Success: #{input}", tokens: 50}}
    end
  end

  # Runner that tracks calls
  defp tracking_runner(agent_pid) do
    fn template, input, opts ->
      send(agent_pid, {:runner_called, template, input, opts})
      {:ok, %{output: input, tokens: 10}}
    end
  end

  # Slow runner for timeout testing
  defp slow_runner(_template, _input, _opts) do
    Process.sleep(500)
    {:ok, %{output: "delayed", tokens: 1}}
  end

  # ============================================================================
  # evaluate_variant/3
  # ============================================================================

  describe "evaluate_variant/3" do
    test "evaluates variant against tasks" do
      variant = PromptVariant.new!(%{template: "Question: {{input}}"})

      tasks = [
        Task.new!(%{input: "What is 2+2?", expected: "2+2"}),
        Task.new!(%{input: "What is 3+3?", expected: "3+3"})
      ]

      {:ok, result} = Evaluator.evaluate_variant(variant, tasks, runner: &mock_runner/3)

      assert result.accuracy == 1.0
      assert result.token_cost == 200
      assert length(result.results) == 2
      assert Enum.all?(result.results, & &1.success)
    end

    test "calculates accuracy from successes" do
      variant = PromptVariant.new!(%{template: "{{input}}"})

      # Only one task will match (expecting "Success" in output)
      tasks = [
        Task.new!(%{input: "pass this", expected: "Success"}),
        Task.new!(%{input: "fail this", expected: "Success"})
      ]

      {:ok, result} = Evaluator.evaluate_variant(variant, tasks, runner: &failing_runner/3)

      # First task passes (contains "Success"), second fails (error)
      assert result.accuracy == 0.5
    end

    test "aggregates token costs" do
      variant = PromptVariant.new!(%{template: "{{input}}"})

      tasks = [
        Task.new!(%{input: "a"}),
        Task.new!(%{input: "b"}),
        Task.new!(%{input: "c"})
      ]

      {:ok, result} = Evaluator.evaluate_variant(variant, tasks, runner: &mock_runner/3)

      assert result.token_cost == 300  # 100 * 3
    end

    test "returns error when runner is missing" do
      variant = PromptVariant.new!(%{template: "test"})
      tasks = [Task.new!(%{input: "test"})]

      assert {:error, :runner_required} = Evaluator.evaluate_variant(variant, tasks, [])
    end

    test "returns error when runner is invalid" do
      variant = PromptVariant.new!(%{template: "test"})
      tasks = [Task.new!(%{input: "test"})]

      assert {:error, :invalid_runner} = Evaluator.evaluate_variant(variant, tasks, runner: "not a function")
      assert {:error, :invalid_runner} = Evaluator.evaluate_variant(variant, tasks, runner: fn -> :ok end)
    end

    test "handles empty task list" do
      variant = PromptVariant.new!(%{template: "test"})

      {:ok, result} = Evaluator.evaluate_variant(variant, [], runner: &mock_runner/3)

      assert result.accuracy == 0.0
      assert result.token_cost == 0
      assert result.results == []
    end

    test "runs tasks in parallel when parallel: true" do
      variant = PromptVariant.new!(%{template: "{{input}}"})

      tasks = [
        Task.new!(%{input: "a"}),
        Task.new!(%{input: "b"}),
        Task.new!(%{input: "c"})
      ]

      # Use slow runner to verify parallelism
      start_time = System.monotonic_time(:millisecond)

      {:ok, result} = Evaluator.evaluate_variant(variant, tasks,
        runner: &slow_runner/3,
        parallel: true
      )

      elapsed = System.monotonic_time(:millisecond) - start_time

      assert length(result.results) == 3
      # Should complete much faster than 1500ms (3 * 500ms) if parallel
      assert elapsed < 1000
    end

    test "runs tasks sequentially by default" do
      test_pid = self()
      variant = PromptVariant.new!(%{template: "{{input}}"})

      tasks = [
        Task.new!(%{input: "first"}),
        Task.new!(%{input: "second"}),
        Task.new!(%{input: "third"})
      ]

      runner = fn _template, input, _opts ->
        send(test_pid, {:called, input})
        {:ok, %{output: input, tokens: 1}}
      end

      {:ok, _result} = Evaluator.evaluate_variant(variant, tasks, runner: runner)

      # Verify order
      assert_receive {:called, "first"}
      assert_receive {:called, "second"}
      assert_receive {:called, "third"}
    end

    test "passes runner_opts to runner" do
      test_pid = self()
      variant = PromptVariant.new!(%{template: "{{input}}"})
      tasks = [Task.new!(%{input: "test"})]

      runner = fn _template, _input, opts ->
        send(test_pid, {:opts, opts})
        {:ok, %{output: "test", tokens: 1}}
      end

      {:ok, _result} = Evaluator.evaluate_variant(variant, tasks,
        runner: runner,
        runner_opts: [model: "gpt-4", temperature: 0.5]
      )

      assert_receive {:opts, opts}
      assert opts[:model] == "gpt-4"
      assert opts[:temperature] == 0.5
    end

    test "returns error when variant is not a PromptVariant" do
      tasks = [Task.new!(%{input: "test"})]

      assert {:error, :invalid_args} = Evaluator.evaluate_variant("not a variant", tasks, runner: &mock_runner/3)
      assert {:error, :invalid_args} = Evaluator.evaluate_variant(nil, tasks, runner: &mock_runner/3)
      assert {:error, :invalid_args} = Evaluator.evaluate_variant(%{}, tasks, runner: &mock_runner/3)
    end

    test "returns error when tasks is not a list" do
      variant = PromptVariant.new!(%{template: "test"})

      assert {:error, :invalid_args} = Evaluator.evaluate_variant(variant, "not a list", runner: &mock_runner/3)
      assert {:error, :invalid_args} = Evaluator.evaluate_variant(variant, nil, runner: &mock_runner/3)
    end
  end

  # ============================================================================
  # run_single_task/3
  # ============================================================================

  describe "run_single_task/3" do
    test "returns success result when task passes" do
      variant = PromptVariant.new!(%{template: "{{input}}"})
      task = Task.new!(%{input: "What is 2+2?", expected: "2+2"})

      result = Evaluator.run_single_task(variant, task, runner: &mock_runner/3)

      assert result.success == true
      assert result.output =~ "2+2"
      assert result.tokens == 100
      assert result.error == nil
      assert result.task == task
    end

    test "returns failure result when task fails validation" do
      variant = PromptVariant.new!(%{template: "{{input}}"})
      task = Task.new!(%{input: "test", expected: "something else"})

      result = Evaluator.run_single_task(variant, task, runner: &mock_runner/3)

      assert result.success == false
      assert result.output != nil  # Output exists but doesn't match
      assert result.error == nil   # No error, just validation failure
    end

    test "returns failure result when runner fails" do
      variant = PromptVariant.new!(%{template: "{{input}}"})
      task = Task.new!(%{input: "fail this", expected: "anything"})

      result = Evaluator.run_single_task(variant, task, runner: &failing_runner/3)

      assert result.success == false
      assert result.output == nil
      assert result.error == :simulated_failure
    end

    test "renders string template with input" do
      test_pid = self()
      variant = PromptVariant.new!(%{template: "Be helpful. Question: {{input}}"})
      task = Task.new!(%{input: "What is AI?"})

      runner = fn template, _input, _opts ->
        send(test_pid, {:template, template})
        {:ok, %{output: "AI is...", tokens: 1}}
      end

      Evaluator.run_single_task(variant, task, runner: runner)

      assert_receive {:template, rendered}
      assert rendered == "Be helpful. Question: What is AI?"
    end

    test "renders map template with input" do
      test_pid = self()
      variant = PromptVariant.new!(%{
        template: %{
          system: "You are helpful",
          user: "Answer this: {{input}}"
        }
      })
      task = Task.new!(%{input: "What is 1+1?"})

      runner = fn template, _input, _opts ->
        send(test_pid, {:template, template})
        {:ok, %{output: "2", tokens: 1}}
      end

      Evaluator.run_single_task(variant, task, runner: runner)

      assert_receive {:template, rendered}
      assert is_map(rendered)
      assert rendered.system == "You are helpful"
      assert rendered.user == "Answer this: What is 1+1?"
    end

    test "handles template with spaces around input placeholder" do
      test_pid = self()
      variant = PromptVariant.new!(%{template: "Q: {{ input }}"})
      task = Task.new!(%{input: "test"})

      runner = fn template, _input, _opts ->
        send(test_pid, {:template, template})
        {:ok, %{output: "test", tokens: 1}}
      end

      Evaluator.run_single_task(variant, task, runner: runner)

      assert_receive {:template, "Q: test"}
    end

    test "measures latency" do
      variant = PromptVariant.new!(%{template: "{{input}}"})
      task = Task.new!(%{input: "test"})

      result = Evaluator.run_single_task(variant, task, runner: &slow_runner/3)

      # Should measure at least 500ms (the sleep time)
      assert result.latency_ms >= 400  # Allow some margin
    end

    test "handles runner returning output without tokens" do
      variant = PromptVariant.new!(%{template: "{{input}}"})
      task = Task.new!(%{input: "test", expected: "test"})

      runner = fn _template, input, _opts ->
        {:ok, %{output: input}}
      end

      result = Evaluator.run_single_task(variant, task, runner: runner)

      assert result.success == true
      assert result.tokens == 0  # Defaults to 0
    end

    test "handles runner exception" do
      variant = PromptVariant.new!(%{template: "{{input}}"})
      task = Task.new!(%{input: "test"})

      runner = fn _template, _input, _opts ->
        raise "boom"
      end

      result = Evaluator.run_single_task(variant, task, runner: runner)

      assert result.success == false
      assert result.error != nil
    end
  end

  # ============================================================================
  # Edge Cases
  # ============================================================================

  describe "edge cases" do
    test "handles unicode in templates and inputs" do
      variant = PromptVariant.new!(%{template: "質問: {{input}}"})
      task = Task.new!(%{input: "日本語のテスト", expected: "日本語のテスト"})

      result = Evaluator.run_single_task(variant, task, runner: &mock_runner/3)

      assert result.output =~ "日本語のテスト"
    end

    test "handles very long inputs" do
      variant = PromptVariant.new!(%{template: "{{input}}"})
      long_input = String.duplicate("a", 10_000)
      task = Task.new!(%{input: long_input})

      result = Evaluator.run_single_task(variant, task, runner: &mock_runner/3)

      assert result.output =~ long_input
    end

    test "handles empty output from runner" do
      variant = PromptVariant.new!(%{template: "{{input}}"})
      task = Task.new!(%{input: "test", expected: ""})

      runner = fn _template, _input, _opts ->
        {:ok, %{output: "", tokens: 5}}
      end

      result = Evaluator.run_single_task(variant, task, runner: runner)

      assert result.output == ""
      assert result.tokens == 5
    end

    test "handles nil output from runner" do
      variant = PromptVariant.new!(%{template: "{{input}}"})
      task = Task.new!(%{input: "test"})

      runner = fn _template, _input, _opts ->
        {:ok, %{output: nil, tokens: 5}}
      end

      result = Evaluator.run_single_task(variant, task, runner: runner)

      assert result.output == nil
      # Task without expected/validator always passes
      assert result.success == true
    end
  end
end
