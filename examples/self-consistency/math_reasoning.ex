defmodule Examples.SelfConsistency.MathReasoning do
  @moduledoc """
  Basic Self-Consistency example demonstrating mathematical reasoning.

  This example shows how Self-Consistency generates multiple diverse reasoning
  paths and uses voting to select the most reliable answer, dramatically
  improving accuracy on complex problems.

  ## The Technique

  Instead of relying on a single reasoning path, Self-Consistency:
  1. Generates k diverse reasoning paths (with higher temperature)
  2. Extracts and normalizes answers from each path
  3. Analyzes path quality (coherence, completeness, confidence)
  4. Votes across paths to select the most reliable answer

  ## Usage

      # Run the example
      Examples.SelfConsistency.MathReasoning.run()

      # Solve a custom problem
      Examples.SelfConsistency.MathReasoning.solve(
        "If 5 machines make 5 widgets in 5 minutes, how long for 100 machines to make 100 widgets?"
      )

      # Compare with single-path CoT
      Examples.SelfConsistency.MathReasoning.compare_with_cot()

  ## Features

  - Multiple diverse reasoning paths (k=5)
  - Answer extraction and normalization
  - Quality scoring for each path
  - Majority voting with confidence
  - Consensus measurement
  - Path visualization
  """

  require Logger

  @doc """
  Run the complete example with the classic "bat and ball" problem.
  """
  def run do
    IO.puts("\n" <> String.duplicate("=", 70))
    IO.puts("  Self-Consistency: Mathematical Reasoning")
    IO.puts(String.duplicate("=", 70) <> "\n")

    problem = """
    A bat and a ball together cost $1.10.
    The bat costs $1.00 more than the ball.
    How much does the ball cost?
    """

    IO.puts("📝 **Problem:**")
    IO.puts(String.trim(problem))
    IO.puts("\n🎯 **Strategy:** Generate 5 diverse reasoning paths, vote for answer")
    IO.puts("🌡️  **Temperature:** 0.7 (encourages diverse approaches)\n")
    IO.puts(String.duplicate("-", 70) <> "\n")

    case solve(problem, sample_count: 5, temperature: 0.7) do
      {:ok, result} ->
        display_result(result)
        {:ok, result}

      {:error, reason} ->
        IO.puts("❌ **Error:** #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Solve a problem using Self-Consistency.

  ## Parameters

  - `problem` - The problem to solve
  - `opts` - Options (sample_count, temperature, voting_strategy)

  ## Returns

  - `{:ok, result}` - Success with answer, consensus, and paths
  - `{:error, reason}` - Failure reason
  """
  def solve(problem, opts \\ []) do
    sample_count = Keyword.get(opts, :sample_count, 5)
    temperature = Keyword.get(opts, :temperature, 0.7)
    voting_strategy = Keyword.get(opts, :voting_strategy, :majority)
    quality_threshold = Keyword.get(opts, :quality_threshold, 0.5)

    # Step 1: Generate multiple reasoning paths
    IO.puts("🔄 Generating #{sample_count} diverse reasoning paths...")

    {:ok, paths} = generate_reasoning_paths(problem, sample_count, temperature)

    IO.puts("✓ Generated #{length(paths)} paths\n")

    # Step 2: Extract answers
    IO.puts("📊 Extracting and normalizing answers...")

    paths_with_answers = extract_answers(paths)

    # Step 3: Analyze quality
    IO.puts("🔍 Analyzing path quality...")

    analyzed_paths = analyze_quality(paths_with_answers)

    # Step 4: Filter by quality threshold
    quality_paths =
      Enum.filter(analyzed_paths, fn path ->
        path.quality_score >= quality_threshold
      end)

    IO.puts("✓ #{length(quality_paths)} paths passed quality threshold\n")

    # Step 5: Vote and select answer
    IO.puts("🗳️  Voting across paths...")

    result = vote_and_select(quality_paths, voting_strategy)

    IO.puts("✓ Selected answer with #{Float.round(result.consensus * 100, 1)}% consensus\n")

    {:ok, result}
  end

  # Path Generation

  defp generate_reasoning_paths(problem, sample_count, temperature) do
    # Simulate generating diverse paths
    # In production, this would make k parallel LLM calls with temp=0.7

    paths =
      case true do
        _ when problem =~ "bat and a ball" ->
          [
            # Path 1: Correct algebraic approach
            """
            Let x be the cost of the ball.
            Then the bat costs x + $1.00.
            Together: x + (x + $1.00) = $1.10
            2x + $1.00 = $1.10
            2x = $0.10
            x = $0.05

            The ball costs $0.05.
            """,
            # Path 2: Correct equation solving
            """
            Ball = b, Bat = b + 1.00
            b + (b + 1.00) = 1.10
            2b = 0.10
            b = 0.05

            Therefore, the ball costs $0.05.
            """,
            # Path 3: Correct trial and error
            """
            Bat is $1 more than ball.
            Let's test values:

            If ball is $0.10:
              Bat = $0.10 + $1.00 = $1.10
              Total = $0.10 + $1.10 = $1.20 ✗

            If ball is $0.05:
              Bat = $0.05 + $1.00 = $1.05
              Total = $0.05 + $1.05 = $1.10 ✓

            The ball costs $0.05.
            """,
            # Path 4: Common error (intuitive but wrong)
            """
            Total is $1.10, bat is $1 more than ball.
            If bat is $1.00, then ball must be $0.10.
            Check: $1.00 + $0.10 = $1.10 ✓

            Wait, is the bat $1 more? $1.00 - $0.10 = $0.90, not $1.00.

            Let me recalculate...
            Actually, I think the ball costs $0.10.
            """,
            # Path 5: Correct systematic approach
            """
            Let's denote:
            - Ball cost = x
            - Bat cost = x + 1.00

            Equation: x + (x + 1.00) = 1.10
            Simplify: 2x + 1.00 = 1.10
            Solve: 2x = 0.10
            x = 0.05

            Verification: 0.05 + 1.05 = 1.10 ✓
            Difference: 1.05 - 0.05 = 1.00 ✓

            The ball costs 5 cents or $0.05.
            """
          ]

        _ when problem =~ "machines" and problem =~ "widgets" ->
          [
            # Path 1: Correct parallel reasoning
            """
            Each machine makes 1 widget in 5 minutes.
            100 machines working in parallel make 100 widgets in the same 5 minutes.

            Answer: 5 minutes
            """,
            # Path 2: Correct rate calculation
            """
            Rate = 1 widget per machine per 5 minutes.
            With 100 machines: 100 widgets at same rate = 5 minutes.

            Answer: 5 minutes
            """,
            # Path 3: Common error (scaling misconception)
            """
            100 machines is 20 times more than 5 machines.
            100 widgets is 20 times more than 5 widgets.
            So time = 5 minutes × 20 = 100 minutes.

            Answer: 100 minutes
            """,
            # Path 4: Correct understanding
            """
            This is parallel production, not serial.
            All machines work simultaneously.
            Time remains constant regardless of scale.

            Answer: 5 minutes
            """,
            # Path 5: Correct with verification
            """
            5 machines make 5 widgets in 5 min → 1 machine makes 1 widget in 5 min.
            100 machines make 100 widgets in 5 min (parallel work).

            Verify: Each of 100 machines makes its own widget in 5 minutes.
            Total: 100 widgets in 5 minutes.

            Answer: 5 minutes
            """
          ]

        _ ->
          # Generic paths for other problems
          Enum.map(1..sample_count, fn i ->
            "Reasoning path #{i}: #{problem} → Answer: [computed answer]"
          end)
      end

    # Take only requested number of paths
    {:ok, Enum.take(paths, sample_count)}
  end

  # Answer Extraction

  defp extract_answers(paths) do
    Enum.map(paths, fn reasoning ->
      answer = extract_answer_from_reasoning(reasoning)

      %{
        reasoning: String.trim(reasoning),
        answer: answer,
        raw_answer: answer
      }
    end)
  end

  defp extract_answer_from_reasoning(reasoning) do
    cond do
      # Look for explicit answer statements
      match = Regex.run(~r/[Aa]nswer:\s*(.+?)(?:\.|$)/m, reasoning) ->
        normalize_answer(List.last(match))

      match = Regex.run(~r/[Tt]herefore.*?(\$?\d+\.?\d*)\s*(?:cents|minutes)?/m, reasoning) ->
        normalize_answer(List.last(match))

      match = Regex.run(~r/[Cc]osts?\s*(\$?\d+\.?\d*)/m, reasoning) ->
        normalize_answer(List.last(match))

      match = Regex.run(~r/[Bb]all\s*=\s*(\$?\d+\.?\d*)/m, reasoning) ->
        normalize_answer(List.last(match))

      # Look for final numeric value
      match = Regex.run(~r/(\$?\d+\.?\d*)\s*(?:cents|minutes)/m, reasoning) ->
        normalize_answer(List.last(match))

      true ->
        "Unknown"
    end
  end

  defp normalize_answer(answer_str) when is_binary(answer_str) do
    # Remove $ and normalize
    answer_str
    |> String.trim()
    |> String.replace("$", "")
    |> String.downcase()
    |> then(fn str ->
      cond do
        str =~ ~r/^\d+\.?\d*$/ ->
          # Convert to number for comparison
          case Float.parse(str) do
            {num, ""} -> if num == Float.round(num, 0), do: trunc(num), else: num
            _ -> str
          end

        true ->
          str
      end
    end)
  end

  defp normalize_answer(other), do: other

  # Quality Analysis

  defp analyze_quality(paths) do
    Enum.map(paths, fn path ->
      quality_score = calculate_quality_score(path)
      confidence = extract_confidence(path)

      Map.merge(path, %{
        quality_score: quality_score,
        confidence: confidence,
        factors: %{
          coherence: score_coherence(path.reasoning),
          completeness: score_completeness(path.reasoning),
          length: score_length(path.reasoning),
          structure: score_structure(path.reasoning)
        }
      })
    end)
  end

  defp calculate_quality_score(path) do
    reasoning = path.reasoning

    coherence = score_coherence(reasoning)
    completeness = score_completeness(reasoning)
    length_score = score_length(reasoning)
    structure = score_structure(reasoning)

    # Weighted average
    0.3 * coherence + 0.3 * completeness + 0.2 * length_score + 0.2 * structure
  end

  defp score_coherence(reasoning) do
    # Check for logical connectors
    has_therefore = reasoning =~ ~r/therefore|thus|hence/i
    has_because = reasoning =~ ~r/because|since|as/i
    has_steps = reasoning =~ ~r/step|first|then|next/i
    has_check = reasoning =~ ~r/verify|check|confirm/i

    score = 0.4
    score = if has_therefore, do: score + 0.2, else: score
    score = if has_because, do: score + 0.15, else: score
    score = if has_steps, do: score + 0.15, else: score
    if has_check, do: score + 0.1, else: score
  end

  defp score_completeness(reasoning) do
    has_equation = reasoning =~ ~r/=/
    has_calculation = reasoning =~ ~r/\d+\s*[+\-*/]\s*\d+/
    has_answer = reasoning =~ ~r/answer|result|therefore/i
    is_long_enough = String.length(reasoning) > 50

    score = 0.25
    score = if has_equation, do: score + 0.25, else: score
    score = if has_calculation, do: score + 0.25, else: score
    score = if has_answer, do: score + 0.15, else: score
    if is_long_enough, do: score + 0.1, else: score
  end

  defp score_length(reasoning) do
    length = String.length(reasoning)

    cond do
      length < 50 -> 0.3
      length < 100 -> 0.6
      length < 300 -> 1.0
      length < 500 -> 0.9
      true -> 0.7
    end
  end

  defp score_structure(reasoning) do
    has_paragraphs = String.contains?(reasoning, "\n\n")
    has_sections = reasoning =~ ~r/^[A-Z][a-z]+:/m
    has_checkmark = reasoning =~ ~r/✓|✗/

    score = 0.4
    score = if has_paragraphs, do: score + 0.3, else: score
    score = if has_sections, do: score + 0.2, else: score
    if has_checkmark, do: score + 0.1, else: score
  end

  defp extract_confidence(path) do
    reasoning = path.reasoning

    # Look for uncertainty markers
    has_uncertainty = reasoning =~ ~r/maybe|perhaps|might|unsure|think/i
    has_certainty = reasoning =~ ~r/definitely|certainly|clearly|verify/i
    has_verification = reasoning =~ ~r/✓|check:|verify:|confirm/i

    base_confidence = 0.7
    base_confidence = if has_uncertainty, do: base_confidence - 0.2, else: base_confidence
    base_confidence = if has_certainty, do: base_confidence + 0.1, else: base_confidence
    if has_verification, do: base_confidence + 0.1, else: base_confidence
  end

  # Voting Mechanism

  defp vote_and_select(paths, voting_strategy) do
    # Group paths by answer
    votes =
      paths
      |> Enum.group_by(fn path -> path.answer end)
      |> Enum.map(fn {answer, answer_paths} ->
        {answer, length(answer_paths), answer_paths}
      end)
      |> Enum.sort_by(fn {_ans, count, _paths} -> -count end)

    # Apply voting strategy
    {winner_answer, winner_paths} =
      case voting_strategy do
        :majority ->
          {answer, _count, paths} = List.first(votes)
          {answer, paths}

        :confidence_weighted ->
          select_by_weighted_vote(votes, :confidence)

        :quality_weighted ->
          select_by_weighted_vote(votes, :quality_score)

        :hybrid ->
          select_by_hybrid_vote(votes)
      end

    # Calculate consensus
    total_paths = length(paths)
    consensus = length(winner_paths) / total_paths

    # Calculate average confidence and quality
    avg_confidence =
      winner_paths
      |> Enum.map(& &1.confidence)
      |> Enum.sum()
      |> Kernel./(length(winner_paths))

    avg_quality =
      winner_paths
      |> Enum.map(& &1.quality_score)
      |> Enum.sum()
      |> Kernel./(length(winner_paths))

    # Build vote distribution
    vote_distribution =
      votes
      |> Enum.map(fn {answer, count, _} -> {answer, count} end)
      |> Enum.into(%{})

    %{
      answer: winner_answer,
      consensus: consensus,
      confidence: avg_confidence,
      quality: avg_quality,
      votes: vote_distribution,
      paths: paths,
      winning_paths: winner_paths,
      voting_strategy: voting_strategy
    }
  end

  defp select_by_weighted_vote(votes, weight_key) do
    {winner_answer, _weight, winner_paths} =
      votes
      |> Enum.map(fn {answer, _count, paths} ->
        total_weight =
          paths
          |> Enum.map(&Map.get(&1, weight_key, 0))
          |> Enum.sum()

        {answer, total_weight, paths}
      end)
      |> Enum.max_by(fn {_ans, weight, _paths} -> weight end)

    {winner_answer, winner_paths}
  end

  defp select_by_hybrid_vote(votes) do
    {winner_answer, _score, winner_paths} =
      votes
      |> Enum.map(fn {answer, count, paths} ->
        avg_confidence = Enum.sum(Enum.map(paths, & &1.confidence)) / length(paths)
        avg_quality = Enum.sum(Enum.map(paths, & &1.quality_score)) / length(paths)

        # Hybrid: 40% count, 30% confidence, 30% quality
        score = count * 0.4 + avg_confidence * count * 0.3 + avg_quality * count * 0.3

        {answer, score, paths}
      end)
      |> Enum.max_by(fn {_ans, score, _paths} -> score end)

    {winner_answer, winner_paths}
  end

  # Display Functions

  defp display_result(result) do
    IO.puts(String.duplicate("=", 70))
    IO.puts("\n✅ **Self-Consistency Complete**\n")

    IO.puts("🎯 **Final Answer:** #{format_answer(result.answer)}")
    IO.puts("📊 **Consensus:** #{Float.round(result.consensus * 100, 1)}%")
    IO.puts("💯 **Confidence:** #{Float.round(result.confidence * 100, 1)}%")
    IO.puts("⭐ **Quality:** #{Float.round(result.quality, 2)}")
    IO.puts("🗳️  **Strategy:** #{result.voting_strategy}")

    IO.puts("\n📈 **Vote Distribution:**")

    result.votes
    |> Enum.sort_by(fn {_ans, count} -> -count end)
    |> Enum.each(fn {answer, count} ->
      percentage = Float.round(count / length(result.paths) * 100, 1)
      IO.puts("   • #{format_answer(answer)}: #{count} votes (#{percentage}%)")
    end)

    IO.puts("\n📝 **All Reasoning Paths:**")

    result.paths
    |> Enum.with_index(1)
    |> Enum.each(fn {path, idx} ->
      winner_mark = if path in result.winning_paths, do: " ✓", else: ""

      IO.puts("\n   Path #{idx}#{winner_mark}:")
      IO.puts("   Answer: #{format_answer(path.answer)}")
      IO.puts("   Quality: #{Float.round(path.quality_score, 2)}, Confidence: #{Float.round(path.confidence, 2)}")

      IO.puts("   Reasoning:")
      reasoning_preview = String.slice(path.reasoning, 0, 150)
      IO.puts("   #{reasoning_preview}...")
    end)

    IO.puts("\n" <> String.duplicate("=", 70))
  end

  defp format_answer(answer) when is_float(answer), do: "$#{Float.round(answer, 2)}"
  defp format_answer(answer) when is_integer(answer) and answer < 100, do: "$0.#{String.pad_leading(Integer.to_string(answer), 2, "0")}"
  defp format_answer(answer) when is_integer(answer), do: "#{answer}"
  defp format_answer(answer), do: to_string(answer)

  @doc """
  Compare Self-Consistency with single-path Chain-of-Thought.
  """
  def compare_with_cot do
    IO.puts("\n" <> String.duplicate("=", 70))
    IO.puts("  Comparison: Chain-of-Thought vs Self-Consistency")
    IO.puts(String.duplicate("=", 70) <> "\n")

    problem = """
    A bat and a ball together cost $1.10.
    The bat costs $1.00 more than the ball.
    How much does the ball cost?
    """

    IO.puts("**Problem:**")
    IO.puts(String.trim(problem))
    IO.puts("")

    IO.puts("**Chain-of-Thought (Single Path):**")
    IO.puts("   • One reasoning path, temperature 0.2")
    IO.puts("   • Fast: ~2 seconds, ~$0.003")
    IO.puts("   • Risk: If reasoning has error, answer is wrong")
    IO.puts("   • Common error: Intuitively answer $0.10 (wrong)")
    IO.puts("   • Accuracy: ~60% (humans often get this wrong too)")

    IO.puts("\n**Self-Consistency (Multiple Paths):**")

    {:ok, result} = solve(problem, sample_count: 5)

    IO.puts("   • Five diverse reasoning paths, temperature 0.7")
    IO.puts("   • Slower: ~15 seconds, ~$0.015 (5× cost)")
    IO.puts("   • Resilient: Errors in 1-2 paths don't affect final answer")
    IO.puts("   • Result: #{format_answer(result.answer)} with #{Float.round(result.consensus * 100, 1)}% consensus")
    IO.puts("   • Accuracy: ~92% (+32% improvement)")

    IO.puts("\n**Key Insight:**")
    IO.puts("   ✓ Correct reasoning paths converge on same answer (#{format_answer(result.answer)})")
    IO.puts("   ✓ Error paths diverge (scattered incorrect answers)")
    IO.puts("   ✓ Majority voting selects the correct answer")
    IO.puts("   ✓ Worth 5× cost for mission-critical decisions")
  end

  @doc """
  Solve multiple problems to demonstrate consistency.
  """
  def batch_solve(problems \\ nil) do
    default_problems = [
      "A bat and a ball together cost $1.10. The bat costs $1.00 more than the ball. How much does the ball cost?",
      "If 5 machines make 5 widgets in 5 minutes, how long for 100 machines to make 100 widgets?"
    ]

    problems_to_solve = problems || default_problems

    IO.puts("\n" <> String.duplicate("=", 70))
    IO.puts("  Batch Self-Consistency Problem Solving")
    IO.puts(String.duplicate("=", 70) <> "\n")

    results =
      Enum.map(problems_to_solve, fn problem ->
        IO.puts("Problem: #{String.slice(problem, 0, 60)}...")

        case solve(problem, sample_count: 5) do
          {:ok, result} ->
            IO.puts("✓ Answer: #{format_answer(result.answer)}")
            IO.puts("  Consensus: #{Float.round(result.consensus * 100, 1)}%\n")
            result

          {:error, reason} ->
            IO.puts("✗ Error: #{inspect(reason)}\n")
            nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    avg_consensus =
      if length(results) > 0 do
        results
        |> Enum.map(& &1.consensus)
        |> Enum.sum()
        |> Kernel./(length(results))
        |> Float.round(2)
      else
        0.0
      end

    IO.puts("Solved #{length(results)}/#{length(problems_to_solve)} problems")
    IO.puts("Average consensus: #{Float.round(avg_consensus * 100, 1)}%")

    {:ok, results}
  end
end
