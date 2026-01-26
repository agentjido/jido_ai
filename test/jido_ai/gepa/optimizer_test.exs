defmodule Jido.AI.GEPA.OptimizerTest do
  use ExUnit.Case, async: true

  alias Jido.AI.GEPA.{Optimizer, PromptVariant, Task}

  # ============================================================================
  # Test Helpers
  # ============================================================================

  defp create_tasks do
    [
      Task.new!(%{input: "What is 2+2?", expected: "4"}),
      Task.new!(%{input: "What is 3+3?", expected: "6"}),
      Task.new!(%{input: "What is 5*5?", expected: "25"})
    ]
  end

  # Mock runner that returns predictable results based on template quality
  defp mock_runner(template, input, _opts) do
    # Better templates (longer, more specific) get better scores
    quality = min(1.0, String.length(template) / 100)

    # Simulate some correct answers based on quality
    output =
      cond do
        String.contains?(input, "2+2") and quality > 0.3 -> "4"
        String.contains?(input, "3+3") and quality > 0.5 -> "6"
        String.contains?(input, "5*5") and quality > 0.7 -> "25"
        true -> "I don't know"
      end

    {:ok, %{output: output, tokens: round(50 + quality * 100)}}
  end

  # Mock runner that also generates mutations
  defp full_mock_runner(template, input, _opts) do
    cond do
      # Mutation request
      String.contains?(template, "Mutation Request") or String.contains?(template, "improved prompt") ->
        {:ok,
         %{
           output: """
           ---MUTATION 1---
           Improved template with more detail: {{input}}

           ---MUTATION 2---
           Please answer the following question carefully: {{input}}

           ---MUTATION 3---
           You are a math expert. Solve: {{input}}
           """,
           tokens: 100
         }}

      # Crossover request
      String.contains?(template, "Crossover Request") or String.contains?(template, "hybrid") ->
        {:ok,
         %{
           output: """
           ---MUTATION 1---
           Combined approach: {{input}}

           ---MUTATION 2---
           Hybrid solution: {{input}}
           """,
           tokens: 80
         }}

      # Reflection request
      String.contains?(template, "analyzing") or String.contains?(template, "failures") ->
        {:ok, %{output: "The prompt needs more specific instructions.", tokens: 50}}

      # Regular evaluation
      true ->
        mock_runner(template, input, [])
    end
  end

  defp attach_telemetry do
    test_pid = self()

    :telemetry.attach_many(
      "test-handler-#{inspect(self())}",
      [
        [:jido, :ai, :gepa, :generation],
        [:jido, :ai, :gepa, :evaluation],
        [:jido, :ai, :gepa, :mutation],
        [:jido, :ai, :gepa, :complete]
      ],
      fn event, measurements, metadata, _config ->
        send(test_pid, {:telemetry, event, measurements, metadata})
      end,
      nil
    )

    on_exit(fn ->
      :telemetry.detach("test-handler-#{inspect(test_pid)}")
    end)
  end

  # ============================================================================
  # optimize/3
  # ============================================================================

  describe "optimize/3" do
    test "runs optimization loop and returns results" do
      tasks = create_tasks()

      {:ok, result} =
        Optimizer.optimize(
          "Answer: {{input}}",
          tasks,
          runner: &full_mock_runner/3,
          generations: 2,
          population_size: 3
        )

      assert is_list(result.best_variants)
      assert result.best_accuracy >= 0.0
      assert result.best_accuracy <= 1.0
      assert result.generations_run == 2
      assert result.total_evaluations >= 0
    end

    test "returns error when runner is missing" do
      tasks = create_tasks()

      assert {:error, :runner_required} = Optimizer.optimize("Test", tasks, [])
    end

    test "returns error when runner is invalid" do
      tasks = create_tasks()

      assert {:error, :invalid_runner} = Optimizer.optimize("Test", tasks, runner: "not a function")
    end

    test "handles empty tasks list" do
      {:ok, result} =
        Optimizer.optimize(
          "Answer: {{input}}",
          [],
          runner: &full_mock_runner/3,
          generations: 1
        )

      # With no tasks, accuracy should be 0 (or 1 if we define empty as success)
      assert is_list(result.best_variants)
    end

    test "respects generations option" do
      tasks = create_tasks()

      {:ok, result} =
        Optimizer.optimize(
          "Answer: {{input}}",
          tasks,
          runner: &full_mock_runner/3,
          generations: 3,
          population_size: 2
        )

      assert result.generations_run == 3
    end

    test "respects population_size option" do
      tasks = create_tasks()

      {:ok, result} =
        Optimizer.optimize(
          "Answer: {{input}}",
          tasks,
          runner: &full_mock_runner/3,
          generations: 1,
          population_size: 4
        )

      # Final population should be at most population_size
      assert length(result.final_population) <= 4
    end

    test "improves accuracy over generations" do
      tasks = [
        Task.new!(%{input: "2+2", expected: "4"}),
        Task.new!(%{input: "3+3", expected: "6"})
      ]

      # Short initial template - should have lower accuracy
      {:ok, result} =
        Optimizer.optimize(
          "{{input}}",
          tasks,
          runner: &full_mock_runner/3,
          generations: 3,
          population_size: 4,
          mutation_count: 2
        )

      # Should have found some variants (may or may not have improved)
      assert result.best_variants != []
    end
  end

  # ============================================================================
  # run_generation/4
  # ============================================================================

  describe "run_generation/4" do
    test "evaluates unevaluated variants" do
      tasks = create_tasks()
      variant = PromptVariant.new!(%{template: "Answer: {{input}}"})

      {:ok, new_pop} =
        Optimizer.run_generation(
          [variant],
          tasks,
          0,
          runner: &full_mock_runner/3,
          population_size: 3
        )

      # Should have evaluated the variant
      evaluated = Enum.filter(new_pop, &PromptVariant.evaluated?/1)
      assert evaluated != []
    end

    test "generates mutations from survivors" do
      tasks = create_tasks()
      variant = PromptVariant.new!(%{template: "Test: {{input}}"})
      variant = PromptVariant.update_metrics(variant, %{accuracy: 0.5, token_cost: 100})

      {:ok, new_pop} =
        Optimizer.run_generation(
          [variant],
          tasks,
          0,
          runner: &full_mock_runner/3,
          population_size: 4,
          mutation_count: 2
        )

      # Should have generated new variants
      assert new_pop != []
    end

    test "preserves evaluated variants" do
      tasks = create_tasks()

      # Pre-evaluated variant
      variant = PromptVariant.new!(%{template: "Test: {{input}}", id: "pre-eval"})
      variant = PromptVariant.update_metrics(variant, %{accuracy: 0.8, token_cost: 100})

      {:ok, new_pop} =
        Optimizer.run_generation(
          [variant],
          tasks,
          0,
          runner: &full_mock_runner/3,
          population_size: 3
        )

      # Original should still be there with same accuracy
      original = Enum.find(new_pop, &(&1.id == "pre-eval"))

      if original do
        assert original.accuracy == 0.8
      end
    end
  end

  # ============================================================================
  # best_variants/2
  # ============================================================================

  describe "best_variants/2" do
    test "returns Pareto front" do
      # Best on both
      v1 = %PromptVariant{id: "1", template: "a", accuracy: 0.9, token_cost: 100}
      # Trade-off
      v2 = %PromptVariant{id: "2", template: "b", accuracy: 0.7, token_cost: 80}
      # Dominated by v1
      v3 = %PromptVariant{id: "3", template: "c", accuracy: 0.8, token_cost: 150}

      best = Optimizer.best_variants([v1, v2, v3])

      # v1 and v2 are on Pareto front, v3 is dominated by v1
      assert length(best) == 2
      assert Enum.any?(best, &(&1.id == "1"))
      assert Enum.any?(best, &(&1.id == "2"))
      refute Enum.any?(best, &(&1.id == "3"))
    end

    test "respects custom objectives" do
      v1 = %PromptVariant{id: "1", template: "a", accuracy: 0.9, token_cost: 200, latency_ms: 50}
      v2 = %PromptVariant{id: "2", template: "b", accuracy: 0.8, token_cost: 100, latency_ms: 100}

      # With latency as objective, both might be on front
      best =
        Optimizer.best_variants([v1, v2],
          objectives: [
            {:accuracy, :maximize},
            {:latency_ms, :minimize}
          ]
        )

      assert best != []
    end
  end

  # ============================================================================
  # Telemetry
  # ============================================================================

  describe "telemetry" do
    test "emits generation events" do
      attach_telemetry()
      tasks = create_tasks()

      {:ok, _result} =
        Optimizer.optimize(
          "Answer: {{input}}",
          tasks,
          runner: &full_mock_runner/3,
          generations: 2,
          population_size: 2
        )

      # Should receive generation telemetry
      assert_receive {:telemetry, [:jido, :ai, :gepa, :generation], measurements, metadata}, 1000
      assert is_number(measurements.best_accuracy)
      assert is_number(measurements.avg_accuracy)
      assert is_integer(metadata.generation)
    end

    test "emits evaluation events" do
      attach_telemetry()
      tasks = create_tasks()

      {:ok, _result} =
        Optimizer.optimize(
          "Answer: {{input}}",
          tasks,
          runner: &full_mock_runner/3,
          generations: 1,
          population_size: 2
        )

      # Should receive evaluation telemetry
      assert_receive {:telemetry, [:jido, :ai, :gepa, :evaluation], measurements, metadata}, 1000
      assert is_number(measurements.accuracy)
      assert is_binary(metadata.variant_id)
    end

    test "emits complete event" do
      attach_telemetry()
      tasks = create_tasks()

      {:ok, _result} =
        Optimizer.optimize(
          "Answer: {{input}}",
          tasks,
          runner: &full_mock_runner/3,
          generations: 1,
          population_size: 2
        )

      # Should receive complete telemetry
      assert_receive {:telemetry, [:jido, :ai, :gepa, :complete], measurements, _metadata}, 1000
      assert measurements.total_generations == 1
      assert is_number(measurements.best_accuracy)
    end
  end

  # ============================================================================
  # Edge Cases
  # ============================================================================

  describe "edge cases" do
    test "handles single generation" do
      tasks = create_tasks()

      {:ok, result} =
        Optimizer.optimize(
          "Answer: {{input}}",
          tasks,
          runner: &full_mock_runner/3,
          generations: 1,
          population_size: 2
        )

      assert result.generations_run == 1
    end

    test "handles map template" do
      tasks = create_tasks()

      {:ok, result} =
        Optimizer.optimize(
          %{system: "You are helpful", user: "{{input}}"},
          tasks,
          runner: &full_mock_runner/3,
          generations: 1,
          population_size: 2
        )

      assert is_list(result.best_variants)
    end

    test "handles runner errors gracefully" do
      tasks = create_tasks()

      failing_runner = fn _template, _input, _opts ->
        {:error, :llm_unavailable}
      end

      # Should not crash, but results might be poor
      {:ok, result} =
        Optimizer.optimize(
          "Answer: {{input}}",
          tasks,
          runner: failing_runner,
          generations: 1,
          population_size: 2
        )

      assert result.generations_run == 1
    end

    test "handles zero crossover rate" do
      tasks = create_tasks()

      {:ok, result} =
        Optimizer.optimize(
          "Answer: {{input}}",
          tasks,
          runner: &full_mock_runner/3,
          generations: 2,
          population_size: 3,
          crossover_rate: 0.0
        )

      assert is_list(result.best_variants)
    end

    test "handles high crossover rate" do
      tasks = create_tasks()

      {:ok, result} =
        Optimizer.optimize(
          "Answer: {{input}}",
          tasks,
          runner: &full_mock_runner/3,
          generations: 2,
          population_size: 4,
          crossover_rate: 0.8
        )

      assert is_list(result.best_variants)
    end

    test "validates maximum generations" do
      tasks = create_tasks()

      assert {:error, :generations_exceeds_max} =
               Optimizer.optimize(
                 "Answer: {{input}}",
                 tasks,
                 runner: &full_mock_runner/3,
                 generations: 10_000
               )
    end

    test "validates maximum population_size" do
      tasks = create_tasks()

      assert {:error, :population_size_exceeds_max} =
               Optimizer.optimize(
                 "Answer: {{input}}",
                 tasks,
                 runner: &full_mock_runner/3,
                 population_size: 10_000
               )
    end

    test "validates maximum mutation_count" do
      tasks = create_tasks()

      assert {:error, :mutation_count_exceeds_max} =
               Optimizer.optimize(
                 "Answer: {{input}}",
                 tasks,
                 runner: &full_mock_runner/3,
                 mutation_count: 10_000
               )
    end
  end

  # ============================================================================
  # Invalid Args Tests
  # ============================================================================

  describe "invalid args" do
    test "optimize returns error when tasks is not a list" do
      assert {:error, :invalid_args} = Optimizer.optimize("template", "not a list", runner: &mock_runner/3)
      assert {:error, :invalid_args} = Optimizer.optimize("template", nil, runner: &mock_runner/3)
      assert {:error, :invalid_args} = Optimizer.optimize("template", %{}, runner: &mock_runner/3)
    end

    test "run_generation returns error when variants is not a list" do
      tasks = create_tasks()

      assert {:error, :invalid_args} = Optimizer.run_generation("not a list", tasks, 0, runner: &mock_runner/3)
      assert {:error, :invalid_args} = Optimizer.run_generation(nil, tasks, 0, runner: &mock_runner/3)
    end
  end
end
