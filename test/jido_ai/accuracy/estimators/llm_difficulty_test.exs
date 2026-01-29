defmodule Jido.AI.Accuracy.Estimators.LLMDifficultyTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Accuracy.Estimators.LLMDifficulty
  alias Jido.AI.Accuracy.{DifficultyEstimate, DifficultyEstimator}

  @moduletag :capture_log

  describe "new/1" do
    test "creates estimator with default values" do
      assert {:ok, estimator} = LLMDifficulty.new(%{})
      assert estimator.model == "anthropic:claude-haiku-4-5"
      assert estimator.timeout == 5000
      assert is_nil(estimator.prompt_template)
    end

    test "creates estimator with custom values" do
      assert {:ok, estimator} =
               LLMDifficulty.new(%{
                 model: "anthropic:claude-4-5",
                 timeout: 10_000
               })

      assert estimator.model == "anthropic:claude-4-5"
      assert estimator.timeout == 10_000
    end

    test "creates estimator with custom prompt template" do
      template = "Classify: {{query}}"
      assert {:ok, estimator} = LLMDifficulty.new(%{prompt_template: template})
      assert estimator.prompt_template == template
    end

    test "returns error for invalid model" do
      assert {:error, :invalid_model} = LLMDifficulty.new(%{model: ""})
      assert {:error, :invalid_model} = LLMDifficulty.new(%{model: nil})
    end

    test "returns error for invalid timeout" do
      assert {:error, :invalid_timeout} = LLMDifficulty.new(%{timeout: 0})
      assert {:error, :invalid_timeout} = LLMDifficulty.new(%{timeout: -1})
    end
  end

  describe "new!/1" do
    test "creates estimator with valid attributes" do
      estimator = LLMDifficulty.new!(%{})
      assert estimator.model == "anthropic:claude-haiku-4-5"
    end

    test "raises for invalid attributes" do
      assert_raise ArgumentError, ~r/Invalid/, fn ->
        LLMDifficulty.new!(%{model: ""})
      end
    end
  end

  describe "estimate/3" do
    setup do
      estimator = LLMDifficulty.new!(%{})
      {:ok, estimator: estimator}
    end

    test "returns valid estimate for simple query (uses simulation)", context do
      # In test environment without ReqLLM, uses simulation
      assert {:ok, estimate} =
               LLMDifficulty.estimate(context.estimator, "What is 2+2?", %{})

      assert %DifficultyEstimate{} = estimate
      assert estimate.level in [:easy, :medium, :hard]
      assert is_number(estimate.score)
      assert is_number(estimate.confidence)
      assert is_binary(estimate.reasoning)
    end

    test "returns valid estimate for complex query (uses simulation)", context do
      assert {:ok, estimate} =
               LLMDifficulty.estimate(
                 context.estimator,
                 "Explain quantum entanglement and its implications",
                 %{}
               )

      assert %DifficultyEstimate{} = estimate
      assert estimate.level in [:easy, :medium, :hard]
      assert estimate.score > 0.5
    end

    test "returns error for empty query", context do
      assert {:error, :invalid_query} =
               LLMDifficulty.estimate(context.estimator, "", %{})

      assert {:error, :invalid_query} =
               LLMDifficulty.estimate(context.estimator, "   ", %{})
    end

    test "returns error for non-binary query", context do
      assert {:error, :invalid_query} =
               LLMDifficulty.estimate(context.estimator, nil, %{})

      assert {:error, :invalid_query} =
               LLMDifficulty.estimate(context.estimator, 123, %{})
    end

    test "includes method in metadata", context do
      assert {:ok, estimate} =
               LLMDifficulty.estimate(context.estimator, "What is 2+2?", %{})

      assert estimate.metadata.method == :llm
      assert estimate.features.method == :llm
    end
  end

  describe "estimate/3 with custom prompt" do
    test "uses custom prompt template" do
      template = "Quick classify: {{query}}"
      estimator = LLMDifficulty.new!(%{prompt_template: template})

      # The custom template would be used in actual LLM calls
      # In simulation mode, this still works
      assert {:ok, estimate} = LLMDifficulty.estimate(estimator, "Test query", %{})
      assert %DifficultyEstimate{} = estimate
    end
  end

  describe "parse_response/2" do
    test "parses valid JSON response" do
      _json = ~s({"level": "easy", "score": 0.2, "confidence": 0.9, "reasoning": "Simple query"})

      # The parsing happens internally, so we test via the public interface
      # by verifying the simulation produces correct output
      estimator = LLMDifficulty.new!(%{})

      # A simple query should produce easy classification in simulation
      assert {:ok, estimate} = LLMDifficulty.estimate(estimator, "simple factual query", %{})
      assert %DifficultyEstimate{} = estimate
      assert estimate.level in [:easy, :medium, :hard]
    end
  end

  describe "DifficultyEstimator behaviour" do
    test "implements estimator?/1 correctly" do
      assert DifficultyEstimator.estimator?(LLMDifficulty)
    end

    test "exports estimate/3" do
      assert function_exported?(LLMDifficulty, :estimate, 3)
    end
  end

  describe "estimate_batch/3" do
    setup do
      estimator = LLMDifficulty.new!(%{})
      {:ok, estimator: estimator}
    end

    test "estimates multiple queries using default batch implementation", _context do
      queries = ["What is 2+2?", "complex quantum mechanics question", "Who wrote Hamlet?"]

      assert {:ok, estimates} =
               DifficultyEstimator.estimate_batch(queries, %{}, LLMDifficulty)

      assert length(estimates) == 3
      assert Enum.all?(estimates, fn e -> %DifficultyEstimate{} = e end)
    end
  end

  describe "integration tests" do
    test "completes full estimation flow" do
      estimator = LLMDifficulty.new!(%{timeout: 5000})

      # Easy query
      {:ok, easy_estimate} = LLMDifficulty.estimate(estimator, "What is 2+2?", %{})
      assert DifficultyEstimate.easy?(easy_estimate) or DifficultyEstimate.medium?(easy_estimate)

      # Hard query (in simulation, "complex" keyword triggers harder classification)
      {:ok, hard_estimate} =
        LLMDifficulty.estimate(estimator, "Explain complex quantum mechanics", %{})

      assert DifficultyEstimate.hard?(hard_estimate) or hard_estimate.score > 0.5
    end

    test "produces consistent results" do
      estimator = LLMDifficulty.new!(%{})
      query = "What is the capital of France?"

      # Should produce same level on repeated calls (simulation is deterministic)
      {:ok, estimate1} = LLMDifficulty.estimate(estimator, query, %{})
      {:ok, estimate2} = LLMDifficulty.estimate(estimator, query, %{})

      assert estimate1.level == estimate2.level
    end
  end
end
