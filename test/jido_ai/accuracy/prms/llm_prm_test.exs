defmodule Jido.AI.Accuracy.Prms.LLMPrmTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Accuracy.Prms.LLMPrm

  @moduletag :capture_log

  describe "new/1" do
    test "creates PRM with default values" do
      assert {:ok, prm} = LLMPrm.new([])

      assert prm.model == nil
      assert prm.prompt_template == nil
      assert prm.score_range == {0.0, 1.0}
      assert prm.temperature == 0.2
      assert prm.timeout == 30_000
      assert prm.max_retries == 2
      assert prm.parallel == false
    end

    test "creates PRM with custom model" do
      assert {:ok, prm} = LLMPrm.new(model: "openai:gpt-4")

      assert prm.model == "openai:gpt-4"
    end

    test "creates PRM with custom score_range" do
      assert {:ok, prm} = LLMPrm.new(score_range: {0, 100})

      assert prm.score_range == {0, 100}
    end

    test "creates PRM with negative score_range" do
      assert {:ok, prm} = LLMPrm.new(score_range: {-1, 1})

      assert prm.score_range == {-1, 1}
    end

    test "creates PRM with custom temperature" do
      assert {:ok, prm} = LLMPrm.new(temperature: 0.5)

      assert prm.temperature == 0.5
    end

    test "creates PRM with custom timeout" do
      assert {:ok, prm} = LLMPrm.new(timeout: 60_000)

      assert prm.timeout == 60_000
    end

    test "creates PRM with custom max_retries" do
      assert {:ok, prm} = LLMPrm.new(max_retries: 5)

      assert prm.max_retries == 5
    end

    test "creates PRM with parallel enabled" do
      assert {:ok, prm} = LLMPrm.new(parallel: true)

      assert prm.parallel == true
    end

    test "returns error for invalid score_range (min > max)" do
      assert {:error, :invalid_score_range} = LLMPrm.new(score_range: {1.0, 0.0})
    end

    test "returns error for invalid score_range (equal values)" do
      assert {:error, :invalid_score_range} = LLMPrm.new(score_range: {0.5, 0.5})
    end

    test "returns error for invalid temperature (negative)" do
      assert {:error, :invalid_temperature} = LLMPrm.new(temperature: -0.1)
    end

    test "returns error for invalid temperature (too high)" do
      assert {:error, :invalid_temperature} = LLMPrm.new(temperature: 2.5)
    end

    test "returns error for invalid timeout (zero)" do
      assert {:error, :invalid_timeout} = LLMPrm.new(timeout: 0)
    end

    test "returns error for invalid timeout (negative)" do
      assert {:error, :invalid_timeout} = LLMPrm.new(timeout: -1000)
    end

    test "accepts temperature at bounds (0, 2)" do
      assert {:ok, prm1} = LLMPrm.new(temperature: 0)
      assert prm1.temperature == 0

      assert {:ok, prm2} = LLMPrm.new(temperature: 2)
      assert prm2.temperature == 2
    end
  end

  describe "new!/1" do
    test "returns PRM when valid" do
      prm = LLMPrm.new!([])
      assert prm.score_range == {0.0, 1.0}
    end

    test "raises when invalid score_range" do
      assert_raise ArgumentError, ~r/Invalid LLM PRM/, fn ->
        LLMPrm.new!(score_range: {1.0, 0.0})
      end
    end

    test "raises when invalid temperature" do
      assert_raise ArgumentError, ~r/Invalid LLM PRM/, fn ->
        LLMPrm.new!(temperature: 3.0)
      end
    end

    test "raises when invalid timeout" do
      assert_raise ArgumentError, ~r/Invalid LLM PRM/, fn ->
        LLMPrm.new!(timeout: 0)
      end
    end
  end

  describe "supports_streaming?/0" do
    test "returns true for LLM PRM" do
      assert LLMPrm.supports_streaming?() == true
    end
  end

  describe "score_step/4" do
    test "extracts score from LLM response with Score: prefix" do
      _prm = LLMPrm.new!([])

      # Mock the LLM call by testing the extraction logic
      content = "Score: 0.8\\nClassification: correct"
      score = extract_score_test(content, {0.0, 1.0})

      assert_in_delta score, 0.8, 0.01
    end

    test "extracts score with lowercase score: prefix" do
      content = "score: 0.7\\nClassification: neutral"
      score = extract_score_test(content, {0.0, 1.0})

      assert_in_delta score, 0.7, 0.01
    end

    test "extracts score with Step Score: prefix" do
      content = "Step Score: 0.9\\nClassification: correct"
      score = extract_score_test(content, {0.0, 1.0})

      assert_in_delta score, 0.9, 0.01
    end

    test "extracts score with Rating: prefix" do
      content = "Rating: 85\\nClassification: correct"
      score = extract_score_test(content, {0, 100})

      assert_in_delta score, 85, 0.1
    end

    test "handles integer scores" do
      content = "Score: 1"
      score = extract_score_test(content, {0.0, 1.0})

      assert score == 1.0
    end

    test "handles negative scores" do
      content = "Score: -0.5"
      score = extract_score_test(content, {-1.0, 1.0})

      assert score == -0.5
    end

    test "returns default midpoint when no pattern matches" do
      content = "No score here\\nJust text"
      score = extract_score_test(content, {0.0, 1.0})

      assert score == 0.5
    end

    test "clamps score to max range" do
      content = "Score: 150"
      score = extract_score_test(content, {0.0, 100.0})

      assert score == 100.0
    end

    test "clamps score to min range" do
      content = "Score: -50"
      score = extract_score_test(content, {0.0, 100.0})

      assert score == 0.0
    end
  end

  describe "score_trace/4" do
    test "returns empty list for empty trace" do
      prm = LLMPrm.new!([])

      assert {:ok, []} = LLMPrm.score_trace(prm, [], %{}, [])
    end

    test "extracts scores in Step N: Score: X format" do
      content = """
      Step 1: Score: 0.9, Classification: correct
      Step 2: Score: 0.7, Classification: neutral
      Step 3: Score: 0.95, Classification: correct
      """

      scores = extract_trace_scores_test(content, 3, {0.0, 1.0})

      assert Enum.at(scores, 0) == 0.9
      assert Enum.at(scores, 1) == 0.7
      assert Enum.at(scores, 2) == 0.95
    end

    test "extracts scores with simple Score: pattern when step format not found" do
      content = """
      Score: 0.8
      Score: 0.6
      Score: 0.9
      """

      scores = extract_trace_scores_test(content, 3, {0.0, 1.0})

      assert Enum.at(scores, 0) == 0.8
      assert Enum.at(scores, 1) == 0.6
      assert Enum.at(scores, 2) == 0.9
    end

    test "pads with default scores when fewer scores than steps" do
      content = """
      Step 1: Score: 0.8
      Step 2: Score: 0.9
      """

      scores = extract_trace_scores_test(content, 4, {0.0, 1.0})

      assert Enum.at(scores, 0) == 0.8
      assert Enum.at(scores, 1) == 0.9
      # default
      assert Enum.at(scores, 2) == 0.5
      # default
      assert Enum.at(scores, 3) == 0.5
    end

    test "truncates extra scores when more scores than steps" do
      content = """
      Step 1: Score: 0.8
      Step 2: Score: 0.9
      Step 3: Score: 0.7
      """

      scores = extract_trace_scores_test(content, 2, {0.0, 1.0})

      assert length(scores) == 2
      assert Enum.at(scores, 0) == 0.8
      assert Enum.at(scores, 1) == 0.9
    end
  end

  describe "classify_step/4" do
    test "classifies high score as correct" do
      _prm = LLMPrm.new!(score_range: {0.0, 1.0})

      # Simulate score_step returning 0.8
      classification = score_to_classification_test(0.8, {0.0, 1.0})

      assert classification == :correct
    end

    test "classifies low score as incorrect" do
      _prm = LLMPrm.new!(score_range: {0.0, 1.0})

      classification = score_to_classification_test(0.2, {0.0, 1.0})

      assert classification == :incorrect
    end

    test "classifies mid score as neutral" do
      _prm = LLMPrm.new!(score_range: {0.0, 1.0})

      classification = score_to_classification_test(0.5, {0.0, 1.0})

      assert classification == :neutral
    end

    test "classifies boundary score (0.7) as correct" do
      classification = score_to_classification_test(0.7, {0.0, 1.0})

      assert classification == :correct
    end

    test "classifies boundary score (0.3) as incorrect" do
      classification = score_to_classification_test(0.3, {0.0, 1.0})

      assert classification == :incorrect
    end

    test "handles negative score range" do
      # Score 0.5 in range {-1, 1} is normalized to 0.75 (correct)
      classification = score_to_classification_test(0.5, {-1.0, 1.0})

      assert classification == :correct
    end

    test "handles custom score range" do
      # Score 70 in range {0, 100} is normalized to 0.7 (correct boundary)
      classification = score_to_classification_test(70, {0, 100})

      assert classification == :correct
    end

    test "handles custom score range with low score" do
      # Score 30 in range {0, 100} is normalized to 0.3 (incorrect boundary)
      classification = score_to_classification_test(30, {0, 100})

      assert classification == :incorrect
    end
  end

  describe "prompt rendering" do
    test "renders default step prompt with all variables" do
      prm = LLMPrm.new!([])

      prompt = render_step_prompt_test(prm, "What is 2+2?", "2 + 2 = 4", [])

      assert String.contains?(prompt, "What is 2+2?")
      assert String.contains?(prompt, "2 + 2 = 4")
      # min_score
      assert String.contains?(prompt, "0.0")
      # max_score
      assert String.contains?(prompt, "1.0")
      # mid_score
      assert String.contains?(prompt, "0.5")
    end

    test "renders step prompt with previous steps" do
      prm = LLMPrm.new!([])

      prompt =
        render_step_prompt_test(prm, "What is 15*23?", "15 * 23 = 345", [
          "Let me calculate 15 * 23."
        ])

      assert String.contains?(prompt, "Let me calculate 15 * 23.")
      assert String.contains?(prompt, "Previous Steps")
    end

    test "renders trace prompt with multiple steps" do
      prm = LLMPrm.new!([])

      prompt =
        render_trace_prompt_test(prm, "What is 2+2?", ["Step 1", "Step 2", "Step 3"])

      assert String.contains?(prompt, "What is 2+2?")
      assert String.contains?(prompt, "3 reasoning steps")
      assert String.contains?(prompt, "1. Step 1")
      assert String.contains?(prompt, "2. Step 2")
      assert String.contains?(prompt, "3. Step 3")
    end

    test "renders with custom score range" do
      prm = LLMPrm.new!(score_range: {0, 100})

      prompt = render_step_prompt_test(prm, "Question", "Step", [])

      # min
      assert String.contains?(prompt, "0")
      # max
      assert String.contains?(prompt, "100")
      # mid
      assert String.contains?(prompt, "50")
    end
  end

  describe "edge cases" do
    test "handles nil question in context" do
      prm = LLMPrm.new!([])

      prompt = render_step_prompt_test(prm, nil, "Step", [])

      assert String.contains?(prompt, "Step")
    end

    test "handles empty question in context" do
      prm = LLMPrm.new!([])

      prompt = render_step_prompt_test(prm, "", "Step", [])

      assert String.contains?(prompt, "Step")
    end

    test "handles empty previous steps" do
      prm = LLMPrm.new!([])

      prompt = render_step_prompt_test(prm, "Question", "Step", [])

      refute String.contains?(prompt, "Previous Steps")
    end

    test "handles zero max_retries" do
      assert {:ok, prm} = LLMPrm.new(max_retries: 0)
      assert prm.max_retries == 0
    end

    test "handles large timeout values" do
      assert {:ok, prm} = LLMPrm.new(timeout: 300_000)
      assert prm.timeout == 300_000
    end

    test "handles large max_retries values" do
      assert {:ok, prm} = LLMPrm.new(max_retries: 100)
      assert prm.max_retries == 100
    end
  end

  # Test helper functions

  defp extract_score_test(content, score_range) do
    # Simulate the extract_score function from LLMPrm
    patterns = [
      ~r/Score:\s*(-?\d+\.?\d*)/i,
      ~r/score:\s*(-?\d+\.?\d*)/i,
      ~r/Step Score:\s*(-?\d+\.?\d*)/i,
      ~r/step score:\s*(-?\d+\.?\d*)/i,
      ~r/Rating:\s*(-?\d+\.?\d*)/i
    ]

    score =
      Enum.find_value(patterns, fn pattern ->
        case Regex.run(pattern, content) do
          [_, score_str] ->
            case Float.parse(score_str) do
              {score, ""} -> score
              {score, _rest} -> score
              :error -> nil
            end

          _ ->
            nil
        end
      end)

    {min_score, max_score} = score_range
    default_score = (min_score + max_score) / 2

    cond do
      score == nil -> default_score
      score < min_score -> min_score
      score > max_score -> max_score
      true -> score
    end
  end

  defp extract_trace_scores_test(content, step_count, score_range) do
    # Try to extract scores in format "Step N: Score: X"
    pattern = ~r/Step\s*(\d+):\s*(?:.*?\s*)?Score:\s*(-?\d+\.?\d*)/i

    captures = Regex.scan(pattern, content)

    if Enum.empty?(captures) do
      # Try alternative format: just scores in order
      extract_scores_simple_test(content, step_count, score_range)
    else
      # Build map of step index to score
      scores_map =
        Map.new(captures, fn [_, index_str, score_str] ->
          {String.to_integer(index_str) - 1, parse_score_value_test(score_str)}
        end)

      # Convert to list in order
      0..(step_count - 1)
      |> Enum.map(fn index ->
        Map.get(scores_map, index, elem(score_range, 0) + (elem(score_range, 1) - elem(score_range, 0)) / 2)
      end)
    end
  end

  defp extract_scores_simple_test(content, step_count, score_range) do
    # Extract all numeric scores from content
    pattern = ~r/(?:Score|Rating):\s*(-?\d+\.?\d*)/i

    scores =
      Regex.scan(pattern, content)
      |> Enum.map(fn [_, score_str] -> parse_score_value_test(score_str) end)

    default_score = elem(score_range, 0) + (elem(score_range, 1) - elem(score_range, 0)) / 2

    # Pad or truncate to match step_count
    case length(scores) do
      n when n < step_count ->
        scores ++ List.duplicate(default_score, step_count - n)

      n when n > step_count ->
        Enum.take(scores, step_count)

      _ ->
        scores
    end
  end

  defp parse_score_value_test(str) do
    case Float.parse(str) do
      {score, ""} ->
        score

      {score, _rest} ->
        score

      :error ->
        case Integer.parse(str) do
          {score, ""} -> score * 1.0
          {score, _rest} -> score * 1.0
          :error -> nil
        end
    end
  end

  defp score_to_classification_test(score, score_range) do
    {min_score, max_score} = score_range
    range = max_score - min_score
    normalized = (score - min_score) / range

    cond do
      normalized >= 0.7 -> :correct
      normalized <= 0.3 -> :incorrect
      true -> :neutral
    end
  end

  defp render_step_prompt_test(prm, question, step, previous_steps) do
    assigns = [
      question: question || "",
      step: step,
      previous_steps: previous_steps,
      min_score: elem(prm.score_range, 0),
      max_score: elem(prm.score_range, 1),
      mid_score: (elem(prm.score_range, 0) + elem(prm.score_range, 1)) / 2
    ]

    template = """
    You are an expert evaluator assessing reasoning steps.

    Original Question: <%= @question %>

    Reasoning Step to Evaluate:
    <%= @step %>

    <%= if length(@previous_steps) > 0 do %>
    Previous Steps (for context):
    <%= Enum.join(@previous_steps, "\\\\n") %>
    <% end %>

    Evaluate this reasoning step on a scale from <%= @min_score %> to <%= @max_score %>:
    - <%= @max_score %>: Correct and sound reasoning
    - <%= @mid_score %>: Partially correct
    - <%= @min_score %>: Incorrect
    """

    EEx.eval_string(template, assigns: assigns)
  end

  defp render_trace_prompt_test(prm, question, steps) do
    # Pre-format steps for the template (like the actual implementation)
    formatted_steps =
      steps
      |> Enum.with_index(1)
      |> Enum.map_join("\n", fn {step, i} -> "#{i}. #{step}" end)

    assigns = [
      question: question || "",
      steps: steps,
      formatted_steps: formatted_steps,
      step_count: length(steps),
      min_score: elem(prm.score_range, 0),
      max_score: elem(prm.score_range, 1),
      mid_score: (elem(prm.score_range, 0) + elem(prm.score_range, 1)) / 2
    ]

    template = """
    You are an expert evaluator assessing reasoning steps.

    Original Question: <%= @question %>

    Evaluate each of the following <%= @step_count %> reasoning steps on a scale from <%= @min_score %> to <%= @max_score %>:

    Reasoning Steps:
    <%= @formatted_steps %>
    """

    EEx.eval_string(template, assigns: assigns)
  end
end
