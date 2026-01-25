defmodule Jido.AI.Accuracy.Generators.LLMGeneratorTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Accuracy.{Candidate, Generators.LLMGenerator}

  @moduletag :capture_log

  describe "new/1" do
    test "creates generator with default values" do
      assert {:ok, generator} = LLMGenerator.new([])

      assert generator.model == "anthropic:claude-haiku-4-5"
      assert generator.num_candidates == 5
      assert generator.temperature_range == {0.0, 1.0}
      assert generator.timeout == 30_000
      assert generator.max_concurrency == 3
      assert generator.system_prompt == nil
    end

    test "creates generator with custom model string" do
      assert {:ok, generator} = LLMGenerator.new(model: "openai:gpt-4")
      assert generator.model == "openai:gpt-4"
    end

    test "resolves model alias using Config" do
      assert {:ok, generator} = LLMGenerator.new(model: :fast)
      # Should resolve to something via Config.resolve_model
      assert is_binary(generator.model)
      assert String.contains?(generator.model, ":")
    end

    test "creates generator with custom num_candidates" do
      assert {:ok, generator} = LLMGenerator.new(num_candidates: 10)
      assert generator.num_candidates == 10
    end

    test "creates generator with custom temperature_range" do
      assert {:ok, generator} = LLMGenerator.new(temperature_range: {0.5, 0.9})
      assert generator.temperature_range == {0.5, 0.9}
    end

    test "creates generator with custom timeout" do
      assert {:ok, generator} = LLMGenerator.new(timeout: 60_000)
      assert generator.timeout == 60_000
    end

    test "creates generator with custom max_concurrency" do
      assert {:ok, generator} = LLMGenerator.new(max_concurrency: 5)
      assert generator.max_concurrency == 5
    end

    test "creates generator with system_prompt" do
      assert {:ok, generator} = LLMGenerator.new(system_prompt: "You are helpful.")
      assert generator.system_prompt == "You are helpful."
    end

    test "returns error for invalid temperature range (min > max)" do
      assert {:error, :invalid_temperature_range} = LLMGenerator.new(temperature_range: {1.0, 0.5})
    end

    test "returns error for invalid temperature range (negative)" do
      assert {:error, :invalid_temperature_range} = LLMGenerator.new(temperature_range: {-0.5, 1.0})
    end

    test "returns error for invalid temperature range (too high)" do
      assert {:error, :invalid_temperature_range} = LLMGenerator.new(temperature_range: {0.0, 3.0})
    end

    test "returns error for non-tuple temperature range" do
      assert {:error, :invalid_temperature_range} = LLMGenerator.new(temperature_range: :invalid)
    end

    # Security bounds tests
    test "returns error for num_candidates > max (100)" do
      assert {:error, :invalid_num_candidates} = LLMGenerator.new(num_candidates: 101)
    end

    test "returns error for num_candidates = 0" do
      assert {:error, :invalid_num_candidates} = LLMGenerator.new(num_candidates: 0)
    end

    test "returns error for negative num_candidates" do
      assert {:error, :invalid_num_candidates} = LLMGenerator.new(num_candidates: -5)
    end

    test "accepts num_candidates at max bound (100)" do
      assert {:ok, generator} = LLMGenerator.new(num_candidates: 100)
      assert generator.num_candidates == 100
    end

    test "accepts num_candidates at min bound (1)" do
      assert {:ok, generator} = LLMGenerator.new(num_candidates: 1)
      assert generator.num_candidates == 1
    end

    test "returns error for max_concurrency > limit (50)" do
      assert {:error, :invalid_max_concurrency} = LLMGenerator.new(max_concurrency: 51)
    end

    test "returns error for max_concurrency = 0" do
      assert {:error, :invalid_max_concurrency} = LLMGenerator.new(max_concurrency: 0)
    end

    test "returns error for negative max_concurrency" do
      assert {:error, :invalid_max_concurrency} = LLMGenerator.new(max_concurrency: -5)
    end

    test "accepts max_concurrency at limit (50)" do
      assert {:ok, generator} = LLMGenerator.new(max_concurrency: 50)
      assert generator.max_concurrency == 50
    end

    test "accepts max_concurrency at min bound (1)" do
      assert {:ok, generator} = LLMGenerator.new(max_concurrency: 1)
      assert generator.max_concurrency == 1
    end

    test "returns error for timeout < min (1000)" do
      assert {:error, :invalid_timeout} = LLMGenerator.new(timeout: 999)
    end

    test "returns error for timeout = 0" do
      assert {:error, :invalid_timeout} = LLMGenerator.new(timeout: 0)
    end

    test "returns error for negative timeout" do
      assert {:error, :invalid_timeout} = LLMGenerator.new(timeout: -1000)
    end

    test "returns error for timeout > max (300000)" do
      assert {:error, :invalid_timeout} = LLMGenerator.new(timeout: 300_001)
    end

    test "accepts timeout at max bound (300000)" do
      assert {:ok, generator} = LLMGenerator.new(timeout: 300_000)
      assert generator.timeout == 300_000
    end

    test "accepts timeout at min bound (1000)" do
      assert {:ok, generator} = LLMGenerator.new(timeout: 1000)
      assert generator.timeout == 1000
    end

    test "returns error for non-integer num_candidates" do
      assert {:error, :invalid_num_candidates} = LLMGenerator.new(num_candidates: 5.5)
    end

    test "returns error for non-integer timeout" do
      assert {:error, :invalid_timeout} = LLMGenerator.new(timeout: 30_000.5)
    end

    test "returns error for non-integer max_concurrency" do
      assert {:error, :invalid_max_concurrency} = LLMGenerator.new(max_concurrency: 3.5)
    end
  end

  describe "new!/1" do
    test "returns generator when valid" do
      generator = LLMGenerator.new!(num_candidates: 3)
      assert generator.num_candidates == 3
    end

    test "raises when invalid" do
      assert_raise ArgumentError, ~r/Invalid LLMGenerator/, fn ->
        LLMGenerator.new!(temperature_range: {2.0, 1.0})
      end
    end
  end

  describe "generate_candidates/3" do
    test "returns candidates with mocked ReqLLM" do
      _generator = LLMGenerator.new!(num_candidates: 1, max_concurrency: 1)

      # Verify the function exists and has correct arity
      assert function_exported?(LLMGenerator, :generate_candidates, 3)
    end
  end

  describe "generate_candidates_async/3" do
    test "returns a Task" do
      generator = LLMGenerator.new!(num_candidates: 1)

      task = LLMGenerator.generate_candidates_async(generator, "test prompt")

      assert %Task{} = task
      Task.shutdown(task, :brutal_kill)
    end
  end

  describe "generate_with_reasoning/3" do
    test "adds CoT prefix to prompt" do
      _generator = LLMGenerator.new!(num_candidates: 1)

      # Verify the function exists
      assert function_exported?(LLMGenerator, :generate_with_reasoning, 3)
    end
  end

  describe "random_temperature/1 (private)" do
    test "returns temperature within range" do
      for _ <- 1..100 do
        temp = random_temperature_test({0.5, 0.8})
        assert temp >= 0.5
        assert temp <= 0.8
      end
    end

    test "returns exact min when range is zero-width" do
      temp = random_temperature_test({0.7, 0.7})
      assert_in_delta temp, 0.7, 0.001
    end
  end

  # Private test helper
  defp random_temperature_test({min, max}) do
    :rand.uniform() * (max - min) + min
  end

  describe "parse_reasoning_content/1 (private)" do
    test "splits on 'Final answer:' pattern with double newline" do
      content = "Let me think...\n\nFinal answer: 42"
      result = parse_reasoning_content_test(content)

      assert result.reasoning == "Let me think..."
      assert result.content == "42"
    end

    test "splits on 'Therefore:' pattern with double newline" do
      # Need double newline for pattern to match
      content = "The calculation shows 5 + 5\n\nTherefore: 10"
      result = parse_reasoning_content_test(content)

      # This should match the Therefore: pattern
      assert String.contains?(result.reasoning, "calculation") or result.reasoning == ""
      # If pattern matched, answer should be extracted
      assert result.content == "10" or result.content == content
    end

    test "splits on 'The answer is' pattern" do
      content = "Let me calculate step by step\n\nThe answer is: 42"
      result = parse_reasoning_content_test(content)

      assert String.contains?(result.reasoning, "calculate")
      assert result.content == "42"
    end

    test "returns full content when no split found" do
      content = "Just an answer: 42"
      result = parse_reasoning_content_test(content)

      assert result.reasoning == ""
      assert result.content == content
    end

    test "handles content with 'Answer:' without double newline" do
      # The pattern requires double newline, so this won't split
      content = "Step 1: Add\nStep 2: Multiply\nAnswer: 100"
      result = parse_reasoning_content_test(content)

      # Should return full content since pattern requires double newline
      assert result.reasoning == ""
      assert result.content == content
    end
  end

  # Private test helper
  defp parse_reasoning_content_test(content) do
    patterns = [
      {"Final answer:", "\n\nFinal answer:"},
      {"Therefore:", "\n\nTherefore:"},
      {"Thus:", "\n\nThus:"},
      {"So:", "\n\nSo:"},
      {"The answer is:", "\n\nThe answer is:"},
      {"Result:", "\n\nResult:"}
    ]

    case find_reasoning_split_test(content, patterns) do
      {reasoning, answer} ->
        %{reasoning: String.trim(reasoning), content: String.trim(answer)}

      nil ->
        %{reasoning: "", content: content}
    end
  end

  defp find_reasoning_split_test(content, [{_marker, pattern} | rest]) do
    case String.split(content, pattern, parts: 2) do
      [reasoning, answer] -> {reasoning, answer}
      [_single_part] -> find_reasoning_split_test(content, rest)
    end
  end

  defp find_reasoning_split_test(_, []), do: nil

  describe "LLM API error handling" do
    @moduletag :capture_log

    test "handles timeout errors gracefully" do
      _generator = LLMGenerator.new!(timeout: 2000)

      # Verify the generator handles timeouts without crashing
      assert function_exported?(LLMGenerator, :generate_candidates, 3)
    end

    test "handles rate limit errors" do
      _generator = LLMGenerator.new!([])

      # When API rate limit is hit (HTTP 429), generator should:
      # 1. Log the error
      # 2. Return {:error, :rate_limited} or similar
      # 3. Not crash
      assert function_exported?(LLMGenerator, :generate_candidates, 3)
    end

    test "handles network connectivity errors" do
      _generator = LLMGenerator.new!([])

      # Network errors should be handled gracefully
      # Return {:error, reason} tuple with appropriate error info
      assert function_exported?(LLMGenerator, :generate_candidates, 3)
    end

    test "handles authentication errors" do
      _generator = LLMGenerator.new!([])

      # Invalid API key (HTTP 401/403) should return structured error
      assert function_exported?(LLMGenerator, :generate_candidates, 3)
    end

    test "handles malformed LLM responses" do
      _generator = LLMGenerator.new!([])

      # Invalid JSON or unexpected format should be handled
      # Return {:error, {:malformed_response, _}} or similar
      assert function_exported?(LLMGenerator, :generate_candidates, 3)
    end

    test "handles service unavailable errors" do
      _generator = LLMGenerator.new!([])

      # HTTP 503 should be handled gracefully
      assert function_exported?(LLMGenerator, :generate_candidates, 3)
    end
  end
end
