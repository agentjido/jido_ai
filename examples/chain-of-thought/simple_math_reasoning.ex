defmodule Examples.ChainOfThought.SimpleMathReasoning do
  @moduledoc """
  Simple example demonstrating Chain-of-Thought for math problems.

  This example shows how to use CoT to solve mathematical reasoning problems
  with step-by-step explanations.

  ## Usage

      # Run the example
      Examples.ChainOfThought.SimpleMathReasoning.run()

      # Solve a custom problem
      Examples.ChainOfThought.SimpleMathReasoning.solve_math_problem(
        "What is 15% of 80?"
      )

  ## Features

  - Zero-shot Chain-of-Thought reasoning
  - Automatic step-by-step breakdown
  - Result validation
  - Reasoning trace logging
  """

  require Logger

  @doc """
  Run the complete example with a sample math problem.
  """
  def run do
    IO.puts("\n=== Simple Math Reasoning with Chain-of-Thought ===\n")

    # Sample problem
    problem = "What is 15% of 80?"

    IO.puts("Problem: #{problem}")
    IO.puts("\n" <> String.duplicate("-", 60) <> "\n")

    case solve_math_problem(problem) do
      {:ok, result} ->
        display_result(result)
        {:ok, result}

      {:error, reason} ->
        IO.puts("❌ Error: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Solve a mathematical problem using Chain-of-Thought reasoning.

  ## Parameters

  - `problem` - The math problem to solve as a string

  ## Returns

  - `{:ok, result}` - Success with reasoning and answer
  - `{:error, reason}` - Failure reason

  ## Example

      {:ok, result} = solve_math_problem("What is 25% of 200?")
      IO.puts("Answer: #{result.answer}")
  """
  def solve_math_problem(problem) do
    # Build the Chain-of-Thought prompt
    prompt = build_cot_prompt(problem)

    # For demonstration, we'll simulate the LLM response
    # In production, this would call the actual LLM
    case simulate_llm_reasoning(problem) do
      {:ok, response} ->
        result = parse_response(response, problem)
        {:ok, result}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Private Functions

  defp build_cot_prompt(problem) do
    """
    Problem: #{problem}

    Let's solve this step by step:

    1. First, understand what we're being asked
    2. Identify the numbers and operation
    3. Perform the calculation step by step
    4. State the final answer

    Please show your reasoning for each step.
    """
  end

  defp simulate_llm_reasoning(problem) do
    # This simulates what an LLM would return with CoT reasoning
    # In production, replace with actual LLM call

    response = cond do
      String.contains?(problem, "15% of 80") ->
        """
        Let me solve this step by step:

        **Step 1: Understand the problem**
        We need to find 15% of 80. This means we're calculating what 15 percent of 80 equals.

        **Step 2: Convert percentage to decimal**
        15% = 15/100 = 0.15

        **Step 3: Multiply by the number**
        0.15 × 80 = 12

        **Step 4: Verification**
        Let's verify: If 10% of 80 is 8, and 5% of 80 is 4, then 15% = 10% + 5% = 8 + 4 = 12 ✓

        **Answer: 12**

        Therefore, 15% of 80 is **12**.
        """

      String.contains?(problem, "25% of 200") ->
        """
        Let me solve this step by step:

        **Step 1: Understand the problem**
        We need to find 25% of 200.

        **Step 2: Convert percentage to decimal**
        25% = 25/100 = 0.25 (which is also 1/4)

        **Step 3: Multiply**
        0.25 × 200 = 50

        **Step 4: Verification**
        25% is the same as 1/4, and 200/4 = 50 ✓

        **Answer: 50**

        Therefore, 25% of 200 is **50**.
        """

      String.contains?(problem, "train") and String.contains?(problem, "60 miles") ->
        """
        Let me solve this step by step:

        **Step 1: Extract information**
        - Segment 1: 60 miles in 1.5 hours
        - Segment 2: 40 miles in 1 hour
        - Question: What is the average speed?

        **Step 2: Calculate total distance**
        Total distance = 60 + 40 = 100 miles

        **Step 3: Calculate total time**
        Total time = 1.5 + 1.0 = 2.5 hours

        **Step 4: Calculate average speed**
        Average speed = Total distance / Total time
        Average speed = 100 miles / 2.5 hours = 40 mph

        **Step 5: Verification**
        At 40 mph for 2.5 hours: 40 × 2.5 = 100 miles ✓

        **Answer: 40 mph**

        The average speed is **40 miles per hour**.
        """

      true ->
        """
        Let me solve this step by step:

        **Step 1: Analyze the problem**
        #{problem}

        **Step 2: Identify the approach**
        This problem requires mathematical reasoning.

        **Step 3: Solve**
        [Solution would be calculated here]

        **Answer: [Result]**

        Note: This is a simulated response. In production, an actual LLM would provide reasoning.
        """
    end

    {:ok, response}
  end

  defp parse_response(response, problem) do
    # Extract the answer from the response
    answer = extract_answer(response)

    # Extract reasoning steps
    steps = extract_steps(response)

    # Calculate confidence based on verification
    confidence = calculate_confidence(response)

    %{
      problem: problem,
      answer: answer,
      reasoning: response,
      steps: steps,
      confidence: confidence,
      metadata: %{
        has_verification: String.contains?(response, "Verification"),
        step_count: length(steps),
        reasoning_length: String.length(response)
      }
    }
  end

  defp extract_answer(response) do
    # Look for the answer in the response
    cond do
      match = Regex.run(~r/\*\*Answer:\s*(.+?)\*\*/s, response) ->
        match |> List.last() |> String.trim()

      match = Regex.run(~r/is\s+\*\*(.+?)\*\*/, response) ->
        match |> List.last() |> String.trim()

      match = Regex.run(~r/Answer:\s*(.+?)$/m, response) ->
        match |> List.last() |> String.trim()

      true ->
        "Unable to extract answer"
    end
  end

  defp extract_steps(response) do
    # Extract step-by-step reasoning
    response
    |> String.split("\n")
    |> Enum.filter(&String.starts_with?(&1, "**Step"))
    |> Enum.map(&String.trim/1)
    |> Enum.map(fn step ->
      # Remove markdown formatting
      step
      |> String.replace("**", "")
      |> String.replace("Step ", "")
    end)
  end

  defp calculate_confidence(response) do
    # Calculate confidence based on reasoning quality indicators
    indicators = [
      {String.contains?(response, "Verification"), 0.2},
      {String.contains?(response, "Step 1"), 0.15},
      {String.contains?(response, "Step 2"), 0.15},
      {String.contains?(response, "✓"), 0.2},
      {String.length(response) > 200, 0.15},
      {String.contains?(response, "Therefore"), 0.15}
    ]

    base_confidence = 0.5

    boost =
      indicators
      |> Enum.filter(fn {condition, _weight} -> condition end)
      |> Enum.map(fn {_condition, weight} -> weight end)
      |> Enum.sum()

    Float.round(base_confidence + boost, 2)
  end

  defp display_result(result) do
    IO.puts("✅ **Solution Found**\n")

    IO.puts("**Answer:** #{result.answer}\n")

    IO.puts("**Reasoning Steps:**")

    result.steps
    |> Enum.with_index(1)
    |> Enum.each(fn {step, idx} ->
      IO.puts("  #{idx}. #{step}")
    end)

    IO.puts("\n**Confidence:** #{result.confidence * 100}%")

    IO.puts("\n**Metadata:**")
    IO.puts("  • Verification included: #{result.metadata.has_verification}")
    IO.puts("  • Number of steps: #{result.metadata.step_count}")
    IO.puts("  • Reasoning length: #{result.metadata.reasoning_length} characters")

    if result.confidence >= 0.8 do
      IO.puts("\n✨ High confidence result!")
    end

    IO.puts("\n" <> String.duplicate("-", 60))

    IO.puts("\n**Full Reasoning Trace:**")
    IO.puts(result.reasoning)
  end

  @doc """
  Compare solving with and without Chain-of-Thought reasoning.

  Shows the difference in output quality and explainability.
  """
  def compare_with_without_cot do
    IO.puts("\n=== Comparing: With vs Without Chain-of-Thought ===\n")

    problem = "What is 15% of 80?"

    # Without CoT - direct answer
    IO.puts("**WITHOUT Chain-of-Thought (Direct):**")
    IO.puts("Problem: #{problem}")
    IO.puts("Answer: 12")
    IO.puts("(No reasoning provided)")

    IO.puts("\n" <> String.duplicate("-", 60) <> "\n")

    # With CoT - step-by-step reasoning
    IO.puts("**WITH Chain-of-Thought (Reasoning):**")

    case solve_math_problem(problem) do
      {:ok, result} ->
        IO.puts("Problem: #{problem}")
        IO.puts("\nAnswer: #{result.answer}")
        IO.puts("\nReasoning:")

        result.steps
        |> Enum.with_index(1)
        |> Enum.each(fn {step, idx} ->
          IO.puts("  #{idx}. #{step}")
        end)

        IO.puts("\n✅ **Key Benefits:**")
        IO.puts("  • Transparent reasoning process")
        IO.puts("  • Step-by-step verification")
        IO.puts("  • Higher confidence: #{result.confidence * 100}%")
        IO.puts("  • Easier to identify errors")
        IO.puts("  • Educational value")

      {:error, reason} ->
        IO.puts("Error: #{inspect(reason)}")
    end
  end

  @doc """
  Solve multiple problems to demonstrate consistency.
  """
  def batch_solve(problems \\ []) do
    default_problems = [
      "What is 15% of 80?",
      "What is 25% of 200?",
      "If a train travels 60 miles in 1.5 hours, then 40 miles in 1 hour, what is its average speed?"
    ]

    problems_to_solve = if Enum.empty?(problems), do: default_problems, else: problems

    IO.puts("\n=== Batch Problem Solving ===\n")

    results =
      Enum.map(problems_to_solve, fn problem ->
        IO.puts("Problem: #{problem}")

        case solve_math_problem(problem) do
          {:ok, result} ->
            IO.puts("Answer: #{result.answer}")
            IO.puts("Confidence: #{result.confidence * 100}%")
            IO.puts("")
            result

          {:error, reason} ->
            IO.puts("Error: #{inspect(reason)}\n")
            nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    IO.puts("Solved #{length(results)}/#{length(problems_to_solve)} problems")

    avg_confidence =
      if length(results) > 0 do
        results
        |> Enum.map(& &1.confidence)
        |> Enum.sum()
        |> Kernel./(length(results))
        |> Float.round(2)
      else
        0.0
      end

    IO.puts("Average confidence: #{avg_confidence * 100}%")

    {:ok, results}
  end
end
