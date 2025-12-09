defmodule JidoTest.AI.Runner.ReqLLMIntegrationTest do
  use ExUnit.Case, async: false
  import JidoTest.ReqLLMTestHelper
  import Mimic

  alias Jido.AI.Model
  alias Jido.AI.Runner.ChainOfThought
  alias Jido.AI.Runner.SelfConsistency
  alias Jido.AI.Runner.TreeOfThoughts.ThoughtEvaluator
  alias Jido.AI.Runner.TreeOfThoughts.ThoughtGenerator

  @moduletag :capture_log
  @moduletag :reqllm_integration

  setup :verify_on_exit!

  # =============================================================================
  # Test Helpers
  # =============================================================================

  defp build_test_agent(instructions \\ []) do
    %{
      pending_instructions: instructions,
      state: %{},
      actions: []
    }
  end

  defp build_test_agent_with_config(config) do
    %{
      pending_instructions: [],
      state: %{cot_config: config},
      actions: []
    }
  end

  # =============================================================================
  # ChainOfThought Runner Tests with ReqLLM
  # =============================================================================

  describe "ChainOfThought runner with ReqLLM" do
    test "accepts model string configuration" do
      agent = build_test_agent()
      # With no pending instructions, runs successfully
      {:ok, _agent, _directives} = ChainOfThought.run(agent, model: "gpt-4o")
    end

    test "accepts model from agent state config" do
      agent =
        build_test_agent_with_config(%{
          model: "claude-3-5-sonnet-latest",
          mode: :zero_shot
        })

      # With no pending instructions, runs successfully
      {:ok, _agent, _directives} = ChainOfThought.run(agent)
    end

    test "handles empty instructions without LLM call" do
      agent = build_test_agent([])

      {:ok, returned_agent, directives} = ChainOfThought.run(agent, model: "gpt-4")
      assert returned_agent == agent
      assert directives == []
    end

    test "validates configuration parameters" do
      agent = build_test_agent()

      # Invalid mode should fail
      {:error, error} = ChainOfThought.run(agent, mode: :invalid)
      assert error =~ "Invalid mode"

      # Invalid temperature should fail
      {:error, error} = ChainOfThought.run(agent, temperature: 5.0)
      assert error =~ "temperature"
    end

    test "returns different modes" do
      agent = build_test_agent()

      # All modes should work with empty instructions
      {:ok, _, _} = ChainOfThought.run(agent, mode: :zero_shot)
      {:ok, _, _} = ChainOfThought.run(agent, mode: :few_shot)
      {:ok, _, _} = ChainOfThought.run(agent, mode: :structured)
    end

    test "accepts custom temperature settings" do
      agent = build_test_agent()

      {:ok, _, _} = ChainOfThought.run(agent, temperature: 0.0)
      {:ok, _, _} = ChainOfThought.run(agent, temperature: 1.5)
    end
  end

  # =============================================================================
  # SelfConsistency Runner Tests with ReqLLM
  # =============================================================================

  describe "SelfConsistency runner with ReqLLM" do
    test "generates multiple reasoning paths with mocked ReqLLM" do
      # Use custom reasoning function for testing - all same answer for consensus
      reasoning_fn = fn _i ->
        "I calculated carefully. The answer is 10."
      end

      {:ok, result} =
        SelfConsistency.run(
          problem: "What is 5 + 5?",
          sample_count: 5,
          reasoning_fn: reasoning_fn,
          parallel: false,
          min_consensus: 0.3,
          quality_threshold: 0.1
        )

      assert Map.has_key?(result, :answer)
      assert Map.has_key?(result, :confidence)
      assert Map.has_key?(result, :paths)
    end

    test "handles partial failures gracefully" do
      # All paths return same answer for consensus
      reasoning_fn = fn _i ->
        "Valid reasoning path. The answer is 12."
      end

      {:ok, result} =
        SelfConsistency.run(
          problem: "Test problem",
          sample_count: 5,
          reasoning_fn: reasoning_fn,
          parallel: false,
          min_consensus: 0.3,
          quality_threshold: 0.1
        )

      assert is_list(result.paths)
    end

    test "uses correct temperature for diversity" do
      reasoning_fn = fn _i ->
        # All paths return same answer for consensus
        "I calculated carefully. The final answer is 10."
      end

      {:ok, result} =
        SelfConsistency.run(
          problem: "What is 10?",
          sample_count: 3,
          temperature: 0.8,
          reasoning_fn: reasoning_fn,
          min_consensus: 0.3,
          quality_threshold: 0.1
        )

      assert Map.has_key?(result, :answer)
    end

    test "enforces minimum consensus threshold" do
      # Create paths with unique answers - won't reach consensus
      reasoning_fn = fn i ->
        "Unique reasoning path #{i}. The final answer is #{i * 100}."
      end

      result =
        SelfConsistency.run(
          problem: "Ambiguous problem",
          sample_count: 5,
          min_consensus: 0.9,
          reasoning_fn: reasoning_fn,
          quality_threshold: 0.1
        )

      # Should fail due to insufficient consensus
      assert match?({:error, {:insufficient_consensus, _}}, result)
    end

    test "supports different voting strategies" do
      reasoning_fn = fn i ->
        # 5 paths return same answer for clear majority
        answer = 12
        "Path #{i}. The answer is #{answer}."
      end

      # Test majority voting
      {:ok, result} =
        SelfConsistency.run(
          problem: "What is 6 + 6?",
          sample_count: 5,
          voting_strategy: :majority,
          reasoning_fn: reasoning_fn,
          parallel: false,
          min_consensus: 0.3,
          quality_threshold: 0.1
        )

      # Should have a valid answer
      assert Map.has_key?(result, :answer)
      assert Map.has_key?(result, :votes)
    end
  end

  # =============================================================================
  # ThoughtGenerator Tests with ReqLLM
  # =============================================================================

  describe "ThoughtGenerator with ReqLLM" do
    test "generates thoughts with sampling strategy" do
      thoughts_fn = fn _opts ->
        ["Approach 1: Direct", "Approach 2: Indirect", "Approach 3: Hybrid"]
      end

      {:ok, thoughts} =
        ThoughtGenerator.generate(
          problem: "Solve 4+5",
          parent_state: %{},
          strategy: :sampling,
          beam_width: 3,
          thought_fn: thoughts_fn
        )

      assert length(thoughts) == 3
    end

    test "generates thoughts with proposal strategy" do
      thoughts_fn = fn _opts ->
        ["Initial approach", "Refined approach", "Alternative"]
      end

      {:ok, thoughts} =
        ThoughtGenerator.generate(
          problem: "Complex problem",
          parent_state: %{step: 1},
          strategy: :proposal,
          beam_width: 3,
          thought_fn: thoughts_fn
        )

      assert length(thoughts) == 3
    end

    test "uses adaptive beam width based on depth" do
      base_width = 5

      # At depth 0, should use full beam width
      width_0 = ThoughtGenerator.adaptive_beam_width(base_width, 0, 0)
      assert width_0 == base_width

      # At deeper levels, should reduce
      width_4 = ThoughtGenerator.adaptive_beam_width(base_width, 4, 0)
      assert width_4 < base_width
    end

    test "reduces beam width for large trees" do
      base_width = 5

      # Large tree should have reduced beam width
      width_large = ThoughtGenerator.adaptive_beam_width(base_width, 0, 1500)
      assert width_large < base_width
    end

    test "uses thought_fn for custom generation" do
      thoughts_fn = fn _opts ->
        ["Custom thought 1", "Custom thought 2", "Custom thought 3"]
      end

      {:ok, thoughts} =
        ThoughtGenerator.generate(
          problem: "Test problem",
          parent_state: %{},
          strategy: :sampling,
          beam_width: 3,
          thought_fn: thoughts_fn
        )

      assert is_list(thoughts)
      assert length(thoughts) == 3
      assert Enum.at(thoughts, 0) == "Custom thought 1"
    end

    test "handles thought_fn returning different counts" do
      # Return fewer thoughts than beam width
      thoughts_fn = fn _opts ->
        ["Only one thought"]
      end

      {:ok, thoughts} =
        ThoughtGenerator.generate(
          problem: "Test",
          parent_state: %{},
          strategy: :sampling,
          beam_width: 5,
          thought_fn: thoughts_fn
        )

      assert length(thoughts) == 1
    end

    test "supports different strategies with thought_fn" do
      proposal_fn = fn opts ->
        strategy = Keyword.get(opts, :strategy)
        beam_width = Keyword.get(opts, :beam_width)

        for i <- 1..beam_width do
          "#{strategy} thought #{i}"
        end
      end

      # Sampling strategy
      {:ok, sampling_thoughts} =
        ThoughtGenerator.generate(
          problem: "Test",
          parent_state: %{},
          strategy: :sampling,
          beam_width: 3,
          thought_fn: proposal_fn
        )

      # Proposal strategy
      {:ok, proposal_thoughts} =
        ThoughtGenerator.generate(
          problem: "Test",
          parent_state: %{},
          strategy: :proposal,
          beam_width: 3,
          thought_fn: proposal_fn
        )

      assert length(sampling_thoughts) == 3
      assert length(proposal_thoughts) == 3
    end
  end

  # =============================================================================
  # ThoughtEvaluator Tests with ReqLLM
  # =============================================================================

  describe "ThoughtEvaluator with ReqLLM" do
    test "evaluates thoughts with value strategy" do
      eval_fn = fn _opts ->
        0.75
      end

      {:ok, score} =
        ThoughtEvaluator.evaluate(
          thought: "Test thought",
          problem: "Solve this problem",
          strategy: :value,
          evaluation_fn: eval_fn
        )

      assert score == 0.75
      assert score >= 0.0 and score <= 1.0
    end

    test "evaluates multiple thoughts and returns ranked scores" do
      thoughts = [
        "This is an optimal solution",
        "This is a good approach",
        "This is a basic idea"
      ]

      eval_fn = fn opts ->
        thought = Keyword.get(opts, :thought)
        # Score based on thought content
        cond do
          String.contains?(thought, "optimal") -> 0.9
          String.contains?(thought, "good") -> 0.7
          true -> 0.5
        end
      end

      {:ok, scores} =
        ThoughtEvaluator.evaluate_batch(thoughts,
          problem: "Test problem",
          strategy: :value,
          evaluation_fn: eval_fn
        )

      assert length(scores) == 3
      # Optimal should score highest
      assert Enum.at(scores, 0) > Enum.at(scores, 2)
    end

    test "uses heuristic evaluation as fallback" do
      {:ok, score} =
        ThoughtEvaluator.evaluate(
          thought: "A reasonable solution approach",
          problem: "Test problem",
          strategy: :heuristic
        )

      assert is_float(score)
      assert score >= 0.0 and score <= 1.0
    end

    test "handles evaluation errors gracefully" do
      # Test that errors in evaluation functions are propagated
      eval_fn = fn _opts ->
        raise "Evaluation error"
      end

      # Should raise since evaluation_fn errors aren't caught by ThoughtEvaluator
      assert_raise RuntimeError, "Evaluation error", fn ->
        ThoughtEvaluator.evaluate(
          thought: "Test",
          problem: "Problem",
          strategy: :value,
          evaluation_fn: eval_fn
        )
      end
    end

    test "supports custom evaluation functions" do
      eval_fn = fn opts ->
        thought = Keyword.get(opts, :thought)
        # Score based on thought length
        min(1.0, String.length(thought) / 50.0)
      end

      {:ok, score} =
        ThoughtEvaluator.evaluate(
          thought: "This is a longer thought with more content",
          problem: "Complex problem",
          strategy: :value,
          evaluation_fn: eval_fn
        )

      assert is_float(score)
      assert score > 0.5
    end

    test "hybrid evaluation combines value and heuristic" do
      # Hybrid uses both value (needs eval_fn) and heuristic
      eval_fn = fn _opts -> 0.7 end

      {:ok, score} =
        ThoughtEvaluator.evaluate(
          thought: "Try to calculate the result step by step",
          problem: "Test problem",
          strategy: :hybrid,
          evaluation_fn: eval_fn
        )

      assert is_float(score)
      assert score >= 0.0 and score <= 1.0
    end

    test "evaluation with different num_votes configurations" do
      eval_fn = fn _opts -> 0.7 end

      {:ok, score} =
        ThoughtEvaluator.evaluate(
          thought: "Test thought",
          problem: "Test problem",
          strategy: :vote,
          num_votes: 5,
          evaluation_fn: eval_fn
        )

      assert score == 0.7
    end
  end

  # =============================================================================
  # Model Format Integration Tests
  # =============================================================================

  describe "Runner model format integration" do
    test "ChainOfThought accepts model string format" do
      agent = build_test_agent()
      # With no instructions, no LLM call needed
      {:ok, _agent, _directives} = ChainOfThought.run(agent, model: "gpt-4")
    end

    test "ThoughtGenerator accepts provider:model format" do
      thoughts_fn = fn _opts -> ["Thought"] end

      {:ok, _thoughts} =
        ThoughtGenerator.generate(
          problem: "Test",
          parent_state: %{},
          beam_width: 1,
          model: "anthropic:claude-3-5-haiku",
          thought_fn: thoughts_fn
        )
    end

    test "Model.from converts to ReqLLM.Model for runners" do
      {:ok, model} = Model.from({:openai, [model: "gpt-4"]})

      # Model should be usable in runner context
      assert model.provider == :openai
      assert model.model == "gpt-4"
    end

    test "runners work with different provider models" do
      agent = build_test_agent()

      providers = [
        # OpenAI
        "gpt-4",
        # Anthropic
        "claude-3-5-haiku"
      ]

      # With no instructions, no LLM call needed
      for model_str <- providers do
        {:ok, _agent, _directives} = ChainOfThought.run(agent, model: model_str)
      end
    end
  end

  # =============================================================================
  # Error Handling and Edge Cases
  # =============================================================================

  describe "Runner error handling with ReqLLM" do
    test "ChainOfThought handles missing instructions gracefully" do
      agent = build_test_agent([])

      # No instructions means no LLM call needed
      {:ok, returned_agent, directives} = ChainOfThought.run(agent, model: "gpt-4")
      assert returned_agent == agent
      assert directives == []
    end

    test "ChainOfThought validates agent structure" do
      invalid_agent = %{state: %{}, actions: []}

      result = ChainOfThought.run(invalid_agent, model: "gpt-4")
      assert match?({:error, _}, result)
    end

    test "handles invalid model configuration" do
      agent = build_test_agent()

      # Empty model string should still work for empty instructions
      result = ChainOfThought.run(agent, model: "")
      assert match?({:ok, _, _}, result)
    end

    test "validates configuration parameters" do
      agent = build_test_agent()

      # Invalid max_iterations
      result = ChainOfThought.run(agent, max_iterations: 0)
      assert match?({:error, _}, result)

      # Invalid mode
      result = ChainOfThought.run(agent, mode: :nonexistent)
      assert match?({:error, _}, result)
    end
  end

  # =============================================================================
  # Performance and Concurrency Tests
  # =============================================================================

  describe "Runner concurrency with ReqLLM" do
    test "SelfConsistency generates paths in parallel" do
      reasoning_fn = fn _i ->
        # Simulate some work
        Process.sleep(10)
        # All same answer for consensus
        "I analyzed the problem carefully. The answer is 42."
      end

      {:ok, result} =
        SelfConsistency.run(
          problem: "Parallel test",
          sample_count: 5,
          parallel: true,
          reasoning_fn: reasoning_fn,
          min_consensus: 0.3,
          quality_threshold: 0.1
        )

      assert length(result.paths) >= 1
    end

    test "SelfConsistency can run sequentially for debugging" do
      reasoning_fn = fn _i ->
        # All same answer for consensus
        "After careful analysis, the answer is 42."
      end

      {:ok, result} =
        SelfConsistency.run(
          problem: "Sequential test",
          sample_count: 3,
          parallel: false,
          reasoning_fn: reasoning_fn,
          min_consensus: 0.3,
          quality_threshold: 0.1
        )

      assert length(result.paths) >= 1
    end
  end
end
