defmodule Jido.AI.GEPA.ReflectorTest do
  use ExUnit.Case, async: true

  alias Jido.AI.GEPA.{Reflector, PromptVariant, Task}

  # ============================================================================
  # Test Helpers
  # ============================================================================

  defp create_variant(template \\ "Answer the question: {{input}}") do
    PromptVariant.new!(%{template: template})
  end

  defp create_task(input, expected) do
    Task.new!(%{input: input, expected: expected})
  end

  defp create_failing_result(task, output) do
    %{
      task: task,
      success: false,
      output: output,
      tokens: 50,
      latency_ms: 100,
      error: nil
    }
  end

  defp create_error_result(task, error) do
    %{
      task: task,
      success: false,
      output: nil,
      tokens: 0,
      latency_ms: 100,
      error: error
    }
  end

  defp mock_reflection_runner(_prompt, _input, _opts) do
    {:ok, %{output: "The prompt lacks clarity. It doesn't specify the expected format.", tokens: 50}}
  end

  defp mock_mutation_runner(prompt, _input, _opts) do
    # Return different responses based on what the prompt is asking for
    if String.contains?(prompt, "Mutation Request") do
      {:ok,
       %{
         output: """
         ---MUTATION 1---
         Please answer clearly and concisely: {{input}}

         ---MUTATION 2---
         You are a helpful assistant. Answer: {{input}}

         ---MUTATION 3---
         Task: {{input}}
         Provide a direct answer.
         """,
         tokens: 100
       }}
    else
      # Reflection response
      {:ok, %{output: "The prompt needs clearer instructions.", tokens: 50}}
    end
  end

  defp mock_crossover_runner(_prompt, _input, _opts) do
    {:ok,
     %{
       output: """
       ---MUTATION 1---
       Combined prompt A and B: {{input}}

       ---MUTATION 2---
       Hybrid approach: {{input}}
       """,
       tokens: 80
     }}
  end

  defp failing_runner(_prompt, _input, _opts) do
    {:error, :llm_unavailable}
  end

  defp invalid_response_runner(_prompt, _input, _opts) do
    {:ok, %{output: nil, tokens: 0}}
  end

  # ============================================================================
  # reflect_on_failures/3
  # ============================================================================

  describe "reflect_on_failures/3" do
    test "analyzes failures and returns reflection text" do
      variant = create_variant()
      task = create_task("What is 2+2?", "4")
      failure = create_failing_result(task, "The answer might be four")

      {:ok, reflection} = Reflector.reflect_on_failures(variant, [failure], runner: &mock_reflection_runner/3)

      assert is_binary(reflection)
      assert String.contains?(reflection, "clarity")
    end

    test "returns success message when no failures" do
      variant = create_variant()

      {:ok, reflection} = Reflector.reflect_on_failures(variant, [], runner: &mock_reflection_runner/3)

      assert String.contains?(reflection, "No failures")
    end

    test "handles multiple failures" do
      variant = create_variant()

      failures = [
        create_failing_result(create_task("Q1", "A1"), "Wrong1"),
        create_failing_result(create_task("Q2", "A2"), "Wrong2"),
        create_failing_result(create_task("Q3", "A3"), "Wrong3")
      ]

      {:ok, reflection} = Reflector.reflect_on_failures(variant, failures, runner: &mock_reflection_runner/3)

      assert is_binary(reflection)
    end

    test "limits failure samples to prevent context overflow" do
      variant = create_variant()
      # Create many failures
      failures =
        for i <- 1..20 do
          create_failing_result(create_task("Q#{i}", "A#{i}"), "Wrong#{i}")
        end

      test_pid = self()

      capturing_runner = fn prompt, _input, _opts ->
        send(test_pid, {:prompt, prompt})
        {:ok, %{output: "Analysis complete.", tokens: 50}}
      end

      {:ok, _reflection} = Reflector.reflect_on_failures(variant, failures, runner: capturing_runner)

      assert_receive {:prompt, prompt}
      # Should mention "5 of 20" since we cap at 5 samples
      assert String.contains?(prompt, "5 of 20")
    end

    test "handles error results" do
      variant = create_variant()
      failure = create_error_result(create_task("Q", "A"), :timeout)

      {:ok, reflection} = Reflector.reflect_on_failures(variant, [failure], runner: &mock_reflection_runner/3)

      assert is_binary(reflection)
    end

    test "returns error when runner is missing" do
      variant = create_variant()
      failure = create_failing_result(create_task("Q", "A"), "Wrong")

      assert {:error, :runner_required} = Reflector.reflect_on_failures(variant, [failure], [])
    end

    test "returns error when runner is invalid" do
      variant = create_variant()
      failure = create_failing_result(create_task("Q", "A"), "Wrong")

      assert {:error, :invalid_runner} = Reflector.reflect_on_failures(variant, [failure], runner: "not a function")
    end

    test "returns error when runner fails" do
      variant = create_variant()
      failure = create_failing_result(create_task("Q", "A"), "Wrong")

      assert {:error, :llm_unavailable} = Reflector.reflect_on_failures(variant, [failure], runner: &failing_runner/3)
    end

    test "returns error when runner returns invalid response" do
      variant = create_variant()
      failure = create_failing_result(create_task("Q", "A"), "Wrong")

      assert {:error, :invalid_runner_response} =
               Reflector.reflect_on_failures(variant, [failure], runner: &invalid_response_runner/3)
    end
  end

  # ============================================================================
  # propose_mutations/3
  # ============================================================================

  describe "propose_mutations/3" do
    test "generates mutation templates from reflection" do
      variant = create_variant()
      reflection = "The prompt lacks specificity."

      {:ok, mutations} = Reflector.propose_mutations(variant, reflection, runner: &mock_mutation_runner/3)

      assert is_list(mutations)
      assert length(mutations) == 3
      assert Enum.all?(mutations, &is_binary/1)
      assert Enum.all?(mutations, &String.contains?(&1, "{{input}}"))
    end

    test "respects mutation_count option" do
      variant = create_variant()
      reflection = "Needs improvement."

      runner = fn _prompt, _input, _opts ->
        {:ok,
         %{
           output: """
           ---MUTATION 1---
           Template 1: {{input}}

           ---MUTATION 2---
           Template 2: {{input}}
           """,
           tokens: 50
         }}
      end

      {:ok, mutations} =
        Reflector.propose_mutations(variant, reflection,
          runner: runner,
          mutation_count: 2
        )

      assert length(mutations) == 2
    end

    test "handles poorly formatted LLM responses" do
      variant = create_variant()
      reflection = "Needs work."

      # Runner that returns unformatted text
      runner = fn _prompt, _input, _opts ->
        {:ok,
         %{
           output: """
           Here are some improved prompts:

           First, try this approach: Be specific when answering {{input}}

           Second, consider this format: Question received, let me answer {{input}} clearly

           Third option: Direct response to {{input}}
           """,
           tokens: 50
         }}
      end

      {:ok, mutations} = Reflector.propose_mutations(variant, reflection, runner: runner)

      # Should fall back to paragraph-based parsing
      assert is_list(mutations)
      refute Enum.empty?(mutations)
    end

    test "returns error when runner fails" do
      variant = create_variant()
      reflection = "Analysis text."

      assert {:error, :llm_unavailable} = Reflector.propose_mutations(variant, reflection, runner: &failing_runner/3)
    end
  end

  # ============================================================================
  # mutate_prompt/3
  # ============================================================================

  describe "mutate_prompt/3" do
    test "returns PromptVariant children from eval results" do
      variant = create_variant()

      eval_result = %{
        accuracy: 0.5,
        token_cost: 100,
        latency_ms: 200,
        results: [
          %{task: create_task("Q1", "A1"), success: true, output: "A1", tokens: 50, latency_ms: 100, error: nil},
          %{task: create_task("Q2", "A2"), success: false, output: "Wrong", tokens: 50, latency_ms: 100, error: nil}
        ]
      }

      {:ok, children} = Reflector.mutate_prompt(variant, eval_result, runner: &mock_mutation_runner/3)

      assert is_list(children)
      assert length(children) == 3
      assert Enum.all?(children, &match?(%PromptVariant{}, &1))

      # Check lineage
      first_child = hd(children)
      assert first_child.generation == variant.generation + 1
      assert first_child.parents == [variant.id]
    end

    test "returns empty list when all tasks pass" do
      variant = create_variant()

      eval_result = %{
        accuracy: 1.0,
        token_cost: 100,
        latency_ms: 200,
        results: [
          %{task: create_task("Q1", "A1"), success: true, output: "A1", tokens: 50, latency_ms: 100, error: nil}
        ]
      }

      {:ok, children} = Reflector.mutate_prompt(variant, eval_result, runner: &mock_mutation_runner/3)

      assert children == []
    end

    test "children have unique IDs" do
      variant = create_variant()

      eval_result = %{
        accuracy: 0.0,
        token_cost: 100,
        latency_ms: 200,
        results: [
          %{task: create_task("Q1", "A1"), success: false, output: "Wrong", tokens: 50, latency_ms: 100, error: nil}
        ]
      }

      {:ok, children} = Reflector.mutate_prompt(variant, eval_result, runner: &mock_mutation_runner/3)

      ids = Enum.map(children, & &1.id)
      assert length(Enum.uniq(ids)) == length(ids)
    end

    test "children are unevaluated" do
      variant = create_variant()

      eval_result = %{
        accuracy: 0.0,
        token_cost: 100,
        latency_ms: 200,
        results: [
          %{task: create_task("Q1", "A1"), success: false, output: "Wrong", tokens: 50, latency_ms: 100, error: nil}
        ]
      }

      {:ok, children} = Reflector.mutate_prompt(variant, eval_result, runner: &mock_mutation_runner/3)

      assert Enum.all?(children, &(!PromptVariant.evaluated?(&1)))
    end

    test "returns error when runner is missing" do
      variant = create_variant()
      eval_result = %{results: []}

      assert {:error, :runner_required} = Reflector.mutate_prompt(variant, eval_result, [])
    end
  end

  # ============================================================================
  # crossover/3
  # ============================================================================

  describe "crossover/3" do
    test "combines two parent variants" do
      variant1 = create_variant("Parent A: {{input}}")
      variant2 = create_variant("Parent B: {{input}}")

      {:ok, children} = Reflector.crossover(variant1, variant2, runner: &mock_crossover_runner/3)

      assert is_list(children)
      assert length(children) == 2
      assert Enum.all?(children, &match?(%PromptVariant{}, &1))
    end

    test "children have both parents in lineage" do
      variant1 = create_variant("A: {{input}}")
      variant2 = create_variant("B: {{input}}")

      {:ok, children} = Reflector.crossover(variant1, variant2, runner: &mock_crossover_runner/3)

      first_child = hd(children)
      assert variant1.id in first_child.parents
      assert variant2.id in first_child.parents
    end

    test "children have incremented generation from higher parent" do
      variant1 = PromptVariant.new!(%{template: "A: {{input}}", generation: 3})
      variant2 = PromptVariant.new!(%{template: "B: {{input}}", generation: 5})

      {:ok, children} = Reflector.crossover(variant1, variant2, runner: &mock_crossover_runner/3)

      first_child = hd(children)
      # max(3, 5) + 1
      assert first_child.generation == 6
    end

    test "children have crossover metadata" do
      variant1 = create_variant("A: {{input}}")
      variant2 = create_variant("B: {{input}}")

      {:ok, children} = Reflector.crossover(variant1, variant2, runner: &mock_crossover_runner/3)

      first_child = hd(children)
      assert first_child.metadata.mutation_type == :crossover
    end

    test "respects children_count option" do
      variant1 = create_variant("A: {{input}}")
      variant2 = create_variant("B: {{input}}")

      runner = fn _prompt, _input, _opts ->
        {:ok,
         %{
           output: """
           ---MUTATION 1---
           Hybrid: {{input}}
           """,
           tokens: 50
         }}
      end

      {:ok, children} =
        Reflector.crossover(variant1, variant2,
          runner: runner,
          children_count: 1
        )

      assert length(children) == 1
    end

    test "returns error when runner fails" do
      variant1 = create_variant("A")
      variant2 = create_variant("B")

      assert {:error, :llm_unavailable} = Reflector.crossover(variant1, variant2, runner: &failing_runner/3)
    end
  end

  # ============================================================================
  # Edge Cases
  # ============================================================================

  describe "edge cases" do
    test "handles map templates in reflection" do
      variant =
        PromptVariant.new!(%{
          template: %{system: "You are helpful", user: "{{input}}"}
        })

      failure = create_failing_result(create_task("Q", "A"), "Wrong")

      {:ok, reflection} = Reflector.reflect_on_failures(variant, [failure], runner: &mock_reflection_runner/3)

      assert is_binary(reflection)
    end

    test "handles very long outputs in failures" do
      variant = create_variant()
      long_output = String.duplicate("a", 10_000)
      failure = create_failing_result(create_task("Q", "A"), long_output)

      test_pid = self()

      capturing_runner = fn prompt, _input, _opts ->
        send(test_pid, {:prompt_length, String.length(prompt)})
        {:ok, %{output: "Analysis.", tokens: 50}}
      end

      {:ok, _} = Reflector.reflect_on_failures(variant, [failure], runner: capturing_runner)

      assert_receive {:prompt_length, length}
      # Should truncate long outputs
      assert length < 5000
    end

    test "handles tasks with custom validators" do
      variant = create_variant()
      task = Task.new!(%{input: "Q", validator: fn _ -> false end})
      failure = create_failing_result(task, "Some output")

      {:ok, reflection} = Reflector.reflect_on_failures(variant, [failure], runner: &mock_reflection_runner/3)

      assert is_binary(reflection)
    end

    test "handles unicode in templates and outputs" do
      variant = create_variant("日本語で答えて: {{input}}")
      failure = create_failing_result(create_task("質問", "回答"), "間違った答え")

      {:ok, reflection} = Reflector.reflect_on_failures(variant, [failure], runner: &mock_reflection_runner/3)

      assert is_binary(reflection)
    end
  end

  # ============================================================================
  # Invalid Args Tests
  # ============================================================================

  describe "invalid args" do
    test "reflect_on_failures returns error for non-variant first arg" do
      failure = create_failing_result(create_task("Q", "A"), "Wrong")

      assert {:error, :invalid_args} =
               Reflector.reflect_on_failures("not a variant", [failure], runner: &mock_reflection_runner/3)

      assert {:error, :invalid_args} = Reflector.reflect_on_failures(nil, [failure], runner: &mock_reflection_runner/3)
      assert {:error, :invalid_args} = Reflector.reflect_on_failures(%{}, [failure], runner: &mock_reflection_runner/3)
    end

    test "reflect_on_failures returns error for non-list second arg" do
      variant = create_variant()

      assert {:error, :invalid_args} =
               Reflector.reflect_on_failures(variant, "not a list", runner: &mock_reflection_runner/3)

      assert {:error, :invalid_args} = Reflector.reflect_on_failures(variant, nil, runner: &mock_reflection_runner/3)
    end

    test "propose_mutations returns error for non-variant first arg" do
      assert {:error, :invalid_args} =
               Reflector.propose_mutations("not a variant", "reflection", runner: &mock_mutation_runner/3)

      assert {:error, :invalid_args} = Reflector.propose_mutations(nil, "reflection", runner: &mock_mutation_runner/3)
    end

    test "propose_mutations returns error for non-string reflection" do
      variant = create_variant()

      assert {:error, :invalid_args} = Reflector.propose_mutations(variant, 123, runner: &mock_mutation_runner/3)
      assert {:error, :invalid_args} = Reflector.propose_mutations(variant, nil, runner: &mock_mutation_runner/3)
    end

    test "mutate_prompt returns error for non-variant first arg" do
      eval_result = %{results: []}

      assert {:error, :invalid_args} =
               Reflector.mutate_prompt("not a variant", eval_result, runner: &mock_mutation_runner/3)

      assert {:error, :invalid_args} = Reflector.mutate_prompt(nil, eval_result, runner: &mock_mutation_runner/3)
    end

    test "mutate_prompt returns error for invalid eval_result" do
      variant = create_variant()

      assert {:error, :invalid_args} = Reflector.mutate_prompt(variant, "not a map", runner: &mock_mutation_runner/3)
      assert {:error, :invalid_args} = Reflector.mutate_prompt(variant, %{}, runner: &mock_mutation_runner/3)
      assert {:error, :invalid_args} = Reflector.mutate_prompt(variant, nil, runner: &mock_mutation_runner/3)
    end

    test "crossover returns error for non-variant args" do
      variant = create_variant()

      assert {:error, :invalid_args} = Reflector.crossover("not a variant", variant, runner: &mock_crossover_runner/3)
      assert {:error, :invalid_args} = Reflector.crossover(variant, "not a variant", runner: &mock_crossover_runner/3)
      assert {:error, :invalid_args} = Reflector.crossover(nil, variant, runner: &mock_crossover_runner/3)
      assert {:error, :invalid_args} = Reflector.crossover(variant, nil, runner: &mock_crossover_runner/3)
    end
  end
end
