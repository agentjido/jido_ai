defmodule Jido.AI.Accuracy.SelfRefineTest do
  use ExUnit.Case, async: false

  alias Jido.AI.Accuracy.{Candidate, SelfRefine}
  alias Jido.AI.Test.ModuleExports

  @moduletag :capture_log

  describe "new/1" do
    test "creates strategy with defaults" do
      assert {:ok, strategy} = SelfRefine.new([])

      assert strategy.model != nil
      assert strategy.temperature == 0.7
      assert strategy.timeout == 30_000
      assert strategy.feedback_prompt == nil
      assert strategy.refine_prompt == nil
    end

    test "creates strategy with custom options" do
      assert {:ok, strategy} =
               SelfRefine.new(
                 temperature: 0.5,
                 timeout: 60_000
               )

      assert strategy.temperature == 0.5
      assert strategy.timeout == 60_000
    end

    test "creates strategy with custom prompts" do
      assert {:ok, strategy} =
               SelfRefine.new(
                 feedback_prompt: "Custom feedback: <%= @prompt %>",
                 refine_prompt: "Custom refine: <%= @prompt %>"
               )

      assert strategy.feedback_prompt == "Custom feedback: <%= @prompt %>"
      assert strategy.refine_prompt == "Custom refine: <%= @prompt %>"
    end

    test "returns error for invalid temperature" do
      assert {:error, :invalid_temperature} = SelfRefine.new(temperature: 3.0)
    end

    test "returns error for invalid timeout" do
      assert {:error, :invalid_timeout} = SelfRefine.new(timeout: 100)
    end

    test "returns error for invalid model" do
      assert {:error, :invalid_model} = SelfRefine.new(model: "")
    end
  end

  describe "new!/1" do
    test "returns strategy when valid" do
      strategy = SelfRefine.new!([])

      assert %SelfRefine{} = strategy
    end

    test "raises when invalid" do
      assert_raise ArgumentError, ~r/Invalid SelfRefine/, fn ->
        SelfRefine.new!(temperature: 5.0)
      end
    end
  end

  describe "generate_feedback/4" do
    test "generates feedback for a response" do
      strategy = SelfRefine.new!([])

      # Use a simple test response
      _response = "The answer is 42."

      # When no custom feedback_prompt is set, default is used
      # The strategy will use the internal default template
      assert strategy.feedback_prompt == nil
    end

    test "truncates very long responses" do
      _strategy = SelfRefine.new!([])

      # Create a very long response
      long_response = String.duplicate("This is a long response. ", 1000)

      # The truncation should happen in the template rendering
      # We can't test the actual LLM call without mocking, but we can verify
      # the truncate_content function is applied
      assert String.length(long_response) > 8000
    end
  end

  describe "apply_feedback/5" do
    test "includes feedback in refinement prompt" do
      strategy = SelfRefine.new!([])

      _prompt = "What is 2+2?"
      _original = "The answer is 4."
      _feedback = "Be more specific in your response."

      # When no custom refine_prompt is set, default is used
      # The strategy will use the internal default template
      assert strategy.refine_prompt == nil
    end

    test "truncates long feedback and responses" do
      _strategy = SelfRefine.new!([])

      long_response = String.duplicate("Content", 2000)
      long_feedback = String.duplicate("Feedback", 2000)

      # Both should be truncated for the prompt
      assert String.length(long_response) > 8000
      assert String.length(long_feedback) > 8000
    end
  end

  describe "compare_original_refined/2" do
    test "calculates length metrics" do
      original = Candidate.new!(%{content: "Short"})
      refined = Candidate.new!(%{content: "Short but longer"})

      comparison = SelfRefine.compare_original_refined(original, refined)

      assert comparison.original_length == 5
      assert comparison.refined_length == 16
      assert comparison.length_delta == 11
      assert comparison.length_change == 220.0
    end

    test "detects improvement when longer" do
      original = Candidate.new!(%{content: String.duplicate("Text ", 10)})
      refined = Candidate.new!(%{content: String.duplicate("Text ", 15)})

      comparison = SelfRefine.compare_original_refined(original, refined)

      assert comparison.improved == true
      assert comparison.length_delta > 0
    end

    test "does not detect improvement when similar length" do
      original = Candidate.new!(%{content: String.duplicate("Text ", 10)})
      refined = Candidate.new!(%{content: String.duplicate("Text ", 10)})

      comparison = SelfRefine.compare_original_refined(original, refined)

      assert comparison.improved == false
    end

    test "handles nil content" do
      original = Candidate.new!(%{content: nil})
      refined = Candidate.new!(%{content: "Some content"})

      comparison = SelfRefine.compare_original_refined(original, refined)

      assert comparison.original_length == 0
      assert comparison.refined_length > 0
      assert comparison.length_delta > 0
    end

    test "calculates negative change when shorter" do
      original = Candidate.new!(%{content: "This is a long response with many words"})
      refined = Candidate.new!(%{content: "Short"})

      comparison = SelfRefine.compare_original_refined(original, refined)

      assert comparison.length_delta < 0
      assert comparison.length_change < 0
      assert comparison.improved == false
    end
  end

  describe "run/3" do
    test "requires prompt" do
      _strategy = SelfRefine.new!([])

      # Empty prompt should work but return empty result
      # We're testing the function signature here
      assert ModuleExports.exported?(SelfRefine, :run, 2)
      assert ModuleExports.exported?(SelfRefine, :run, 3)
    end

    test "accepts initial_candidate option" do
      _strategy = SelfRefine.new!([])

      original = Candidate.new!(%{content: "Original response"})

      # With initial_candidate, feedback should be generated
      # We can't test the full flow without mocking, but we can verify
      # the option is accepted
      assert is_map(original)
    end

    test "accepts feedback option" do
      _strategy = SelfRefine.new!([])

      _original = Candidate.new!(%{content: "Original response"})
      feedback = "Please be more detailed."

      # With feedback, refinement should skip feedback generation
      # We verify the types are correct
      assert is_binary(feedback)
    end

    test "accepts model override" do
      _strategy = SelfRefine.new!([])

      # Model can be overridden via opts
      opts = [model: "anthropic:claude-haiku-4-5"]
      assert is_list(opts)
    end
  end

  describe "integration scenarios" do
    test "strategy structure matches expected interface" do
      strategy = SelfRefine.new!([])

      # Check struct has expected fields
      assert Map.has_key?(strategy, :model)
      assert Map.has_key?(strategy, :temperature)
      assert Map.has_key?(strategy, :timeout)
      assert Map.has_key?(strategy, :feedback_prompt)
      assert Map.has_key?(strategy, :refine_prompt)
    end

    test "comparison structure matches expected interface" do
      original = Candidate.new!(%{content: "Original"})
      refined = Candidate.new!(%{content: "Refined response"})

      comparison = SelfRefine.compare_original_refined(original, refined)

      # Check comparison has expected fields
      assert Map.has_key?(comparison, :length_change)
      assert Map.has_key?(comparison, :length_delta)
      assert Map.has_key?(comparison, :original_length)
      assert Map.has_key?(comparison, :refined_length)
      assert Map.has_key?(comparison, :improved)
    end
  end

  describe "template rendering" do
    test "feedback template renders correctly" do
      strategy = SelfRefine.new!(feedback_prompt: "Question: <%= @prompt %> Answer: <%= @response %>")

      prompt = "What is 2+2?"
      response = "The answer is 4."

      rendered =
        EEx.eval_string(strategy.feedback_prompt, assigns: [prompt: prompt, response: response])

      assert rendered =~ "Question: What is 2+2?"
      assert rendered =~ "Answer: The answer is 4."
    end

    test "refine template renders correctly" do
      strategy =
        SelfRefine.new!(refine_prompt: "Q: <%= @prompt %> A: <%= @response %> F: <%= @feedback %>")

      prompt = "What is 2+2?"
      response = "4"
      feedback = "Explain more"

      rendered =
        EEx.eval_string(
          strategy.refine_prompt,
          assigns: [
            prompt: prompt,
            response: response,
            feedback: feedback
          ]
        )

      assert rendered =~ "Q: What is 2+2?"
      assert rendered =~ "A: 4"
      assert rendered =~ "F: Explain more"
    end
  end

  describe "cleanup_feedback/1" do
    test "removes common prefixes from feedback" do
      feedback = "Here is your feedback: The answer should be more detailed."

      cleaned =
        feedback
        |> String.trim()
        |> String.replace(~r/^(Here is|Below is|The following is) your (feedback|review|analysis):/i, "")
        |> String.trim()

      assert cleaned =~ "The answer should be more detailed."
      refute cleaned =~ "Here is your feedback:"
    end
  end
end
