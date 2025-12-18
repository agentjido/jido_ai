defmodule Examples.SelfConsistency.MultiDomainSolver do
  @moduledoc """
  Advanced Self-Consistency example demonstrating multi-domain problem solving using the SelfConsistency runner.

  This example shows sophisticated Self-Consistency patterns including:
  - Runner-based orchestration with SelfConsistency runner
  - Domain-specific reasoning path generation (math, code, text)
  - Multiple voting strategies via runner (majority, confidence_weighted)
  - Quality threshold filtering via runner
  - Diversity filtering via runner
  - Progressive refinement for difficult problems

  ## Runner-Based Architecture

  Uses the SelfConsistency runner which handles:
  1. Parallel generation of diverse reasoning paths
  2. Answer extraction and normalization
  3. Quality analysis and filtering
  4. Diversity enforcement
  5. Voting mechanisms (majority, confidence-weighted)

  ## Usage

      # Run the example
      Examples.SelfConsistency.MultiDomainSolver.run()

      # Solve with specific strategy
      Examples.SelfConsistency.MultiDomainSolver.solve(
        problem,
        domain: :math,
        voting_strategy: :confidence_weighted,
        sample_count: 10
      )

      # Progressive refinement
      Examples.SelfConsistency.MultiDomainSolver.solve_with_refinement(problem)

  ## Features

  - SelfConsistency runner orchestration
  - Domain-aware path generation via custom reasoning_fn
  - Voting strategies via runner
  - Quality and diversity filtering via runner
  - Progressive refinement pattern
  - Detailed result analytics
  """

  require Logger

  alias Jido.AI.Runner.SelfConsistency

  @doc """
  Run the complete example demonstrating advanced Self-Consistency patterns with the runner.
  """
  def run do
    IO.puts("\n" <> String.duplicate("=", 70))
    IO.puts("  Self-Consistency: Multi-Domain Problem Solver (Runner-Based)")
    IO.puts(String.duplicate("=", 70) <> "\n")

    # Demonstrate with a financial calculation problem
    problem = """
    Investment Scenario:
    You invest $10,000 at 7% annual compound interest for 5 years.
    You also invest another $5,000 at 4% annual compound interest for 5 years.

    Question: What is the total value of both investments after 5 years?
    (Use formula: A = P(1 + r)^t)
    """

    IO.puts("📝 **Problem:** Financial calculation with compound interest")
    IO.puts("🎯 **Domain:** Mathematics")
    IO.puts("🔧 **Method:** SelfConsistency runner with domain-specific paths")
    IO.puts("🔧 **Features:**")
    IO.puts("   • Custom reasoning function for math domain")
    IO.puts("   • Runner-managed answer extraction")
    IO.puts("   • Runner-managed quality filtering")
    IO.puts("   • Runner-managed voting\n")
    IO.puts(String.duplicate("-", 70) <> "\n")

    case solve(problem, domain: :math, voting_strategy: :confidence_weighted, sample_count: 7) do
      {:ok, result} ->
        display_result(result)
        {:ok, result}

      {:error, reason} ->
        IO.puts("❌ **Error:** #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Solve a problem with domain-aware Self-Consistency using the SelfConsistency runner.

  ## Options

  - `:domain` - :math, :code, :text (affects path generation)
  - `:sample_count` - Number of paths (default: 7)
  - `:temperature` - Diversity control (default: 0.7)
  - `:voting_strategy` - :majority | :confidence_weighted (default: :confidence_weighted)
  - `:quality_threshold` - Minimum quality (default: 0.5)
  - `:diversity_threshold` - Minimum diversity (default: 0.3)

  ## Returns

  - `{:ok, result}` - Success with answer, consensus, paths, and votes
  - `{:error, reason}` - Failure reason
  """
  def solve(problem, opts \\ []) do
    domain = Keyword.get(opts, :domain, :math)
    sample_count = Keyword.get(opts, :sample_count, 7)
    temperature = Keyword.get(opts, :temperature, 0.7)
    voting_strategy = Keyword.get(opts, :voting_strategy, :confidence_weighted)
    quality_threshold = Keyword.get(opts, :quality_threshold, 0.5)
    diversity_threshold = Keyword.get(opts, :diversity_threshold, 0.3)

    IO.puts("🚀 **Running SelfConsistency runner with domain=#{domain}...**\n")

    # Use custom reasoning function to generate domain-specific paths
    reasoning_fn = fn _i ->
      paths = generate_reasoning_paths(problem, sample_count, temperature, domain)
      {:ok, path_list} = paths
      Enum.random(path_list)
    end

    # Call the SelfConsistency runner
    SelfConsistency.run(
      problem: problem,
      sample_count: sample_count,
      temperature: temperature,
      voting_strategy: voting_strategy,
      quality_threshold: quality_threshold,
      diversity_threshold: diversity_threshold,
      reasoning_fn: reasoning_fn
    )
  end

  # Domain-Specific Path Generation

  defp generate_reasoning_paths(problem, sample_count, _temperature, domain) do
    # Simulate domain-aware path generation
    paths =
      case domain do
        :math when problem =~ "compound interest" ->
          [
            """
            Investment 1: $10,000 at 7% for 5 years
            A₁ = 10000 × (1 + 0.07)^5
            A₁ = 10000 × (1.07)^5
            A₁ = 10000 × 1.40255
            A₁ = $14,025.52

            Investment 2: $5,000 at 4% for 5 years
            A₂ = 5000 × (1 + 0.04)^5
            A₂ = 5000 × (1.04)^5
            A₂ = 5000 × 1.21665
            A₂ = $6,083.26

            Total = $14,025.52 + $6,083.26 = $20,108.78

            Answer: $20,108.78
            """,
            """
            Using compound interest formula A = P(1 + r)^t

            First investment:
            P = 10,000, r = 0.07, t = 5
            A = 10,000 × (1.07)^5 ≈ 14,025.52

            Second investment:
            P = 5,000, r = 0.04, t = 5
            A = 5,000 × (1.04)^5 ≈ 6,083.26

            Total value = 14,025.52 + 6,083.26 = 20,108.78

            Answer: $20,108.78
            """,
            """
            Calculate each investment separately:

            Investment A: $10,000 @ 7%
            Year 1: 10,700
            Year 2: 11,449
            Year 3: 12,250
            Year 4: 13,108
            Year 5: 14,026 (rounded)

            Investment B: $5,000 @ 4%
            Year 1: 5,200
            Year 2: 5,408
            Year 3: 5,624
            Year 4: 5,849
            Year 5: 6,083 (rounded)

            Total: 14,026 + 6,083 = 20,109

            Answer: $20,109
            """,
            """
            Let me calculate step by step.

            First investment with 7% compounding:
            10000 × 1.07^5 = 10000 × 1.402551 = 14,025.51

            Second investment with 4% compounding:
            5000 × 1.04^5 = 5000 × 1.216653 = 6,083.26

            Adding both: 14,025.51 + 6,083.26 = 20,108.77

            Answer: $20,108.77
            """,
            """
            Using the compound interest formula:

            For $10,000 at 7%:
            A = 10,000(1.07)^5 = 14,025.52

            For $5,000 at 4%:
            A = 5,000(1.04)^5 = 6,083.26

            Combined total = 20,108.78

            Answer: $20,108.78
            """,
            """
            Calculate both investments:
            Investment 1: 10000 × (1.07)^5
            = 10000 × 1.4025517307
            = 14,025.52 (rounded to 2 decimals)

            Investment 2: 5000 × (1.04)^5
            = 5000 × 1.2166529024
            = 6,083.26 (rounded to 2 decimals)

            Total = 14,025.52 + 6,083.26 = 20,108.78

            Answer: $20,108.78
            """,
            """
            Apply compound interest to each:

            10,000 at 7% compounded 5 times:
            10,000 × 1.07 × 1.07 × 1.07 × 1.07 × 1.07 = 14,025.52

            5,000 at 4% compounded 5 times:
            5,000 × 1.04 × 1.04 × 1.04 × 1.04 × 1.04 = 6,083.26

            Sum = 20,108.78

            Answer: $20,108.78
            """
          ]

        _ ->
          Enum.map(1..sample_count, fn i ->
            "Reasoning path #{i} for #{domain} problem"
          end)
      end

    {:ok, Enum.take(paths, sample_count)}
  end

  # Domain-Specific Answer Extraction

  defp extract_answers(paths, domain) do
    Enum.map(paths, fn reasoning ->
      answer = extract_answer_by_domain(reasoning, domain)

      %{
        reasoning: String.trim(reasoning),
        answer: answer,
        domain: domain
      }
    end)
  end

  defp extract_answer_by_domain(reasoning, domain) do
    case domain do
      :math ->
        extract_math_answer(reasoning)

      :code ->
        extract_code_answer(reasoning)

      :text ->
        extract_text_answer(reasoning)

      _ ->
        extract_generic_answer(reasoning)
    end
  end

  defp extract_math_answer(reasoning) do
    cond do
      # Look for Answer: $X,XXX.XX pattern
      match = Regex.run(~r/[Aa]nswer:\s*\$?([\d,]+\.?\d*)/m, reasoning) ->
        List.last(match) |> normalize_number()

      # Look for = $X,XXX.XX at end
      match = Regex.run(~r/=\s*\$?([\d,]+\.?\d*)\s*$/m, reasoning) ->
        List.last(match) |> normalize_number()

      # Look for Total = $X,XXX.XX
      match = Regex.run(~r/[Tt]otal.*?\$?([\d,]+\.?\d*)/m, reasoning) ->
        List.last(match) |> normalize_number()

      # Last number in text
      matches = Regex.scan(~r/\$?([\d,]+\.?\d*)/, reasoning) ->
        matches |> List.last() |> List.last() |> normalize_number()

      true ->
        "Unknown"
    end
  end

  defp extract_code_answer(reasoning) do
    # Extract code blocks
    case Regex.run(~r/```(?:\w+)?\n(.+?)\n```/s, reasoning) do
      [_, code] -> String.trim(code)
      _ -> extract_generic_answer(reasoning)
    end
  end

  defp extract_text_answer(reasoning) do
    # Extract conclusion or final statement
    cond do
      match = Regex.run(~r/[Cc]onclusion:\s*(.+?)(?:\.|$)/m, reasoning) ->
        List.last(match) |> String.trim()

      match = Regex.run(~r/[Ii]n summary,\s*(.+?)(?:\.|$)/m, reasoning) ->
        List.last(match) |> String.trim()

      true ->
        extract_generic_answer(reasoning)
    end
  end

  defp extract_generic_answer(reasoning) do
    case Regex.run(~r/[Aa]nswer:\s*(.+?)(?:\.|$)/m, reasoning) do
      [_, answer] -> String.trim(answer)
      _ -> "Unknown"
    end
  end

  defp normalize_number(str) when is_binary(str) do
    str
    |> String.replace(",", "")
    |> String.replace("$", "")
    |> String.trim()
    |> then(fn s ->
      case Float.parse(s) do
        {num, ""} -> Float.round(num, 2)
        _ -> s
      end
    end)
  end

  defp normalize_number(num), do: num

  # Advanced Quality Analysis

  defp analyze_quality(paths) do
    Enum.map(paths, fn path ->
      factors = %{
        coherence: score_coherence(path.reasoning),
        completeness: score_completeness(path.reasoning),
        confidence_markers: score_confidence_markers(path.reasoning),
        mathematical_rigor: score_mathematical_rigor(path.reasoning),
        length: score_length(path.reasoning)
      }

      quality_score = calculate_weighted_quality(factors)
      confidence = calibrate_confidence(quality_score, factors)

      Map.merge(path, %{
        quality_score: quality_score,
        confidence: confidence,
        factors: factors
      })
    end)
  end

  defp calculate_weighted_quality(factors) do
    0.25 * factors.coherence +
      0.25 * factors.completeness +
      0.20 * factors.confidence_markers +
      0.20 * factors.mathematical_rigor +
      0.10 * factors.length
  end

  defp score_coherence(reasoning) do
    indicators = [
      reasoning =~ ~r/therefore|thus|hence/i,
      reasoning =~ ~r/because|since/i,
      reasoning =~ ~r/step|first|then/i,
      reasoning =~ ~r/calculate|compute/i
    ]

    Enum.count(indicators, & &1) / length(indicators)
  end

  defp score_completeness(reasoning) do
    indicators = [
      reasoning =~ ~r/=/,
      reasoning =~ ~r/\d+\s*[+\-*/×÷]\s*\d+/,
      reasoning =~ ~r/answer/i,
      String.length(reasoning) > 100
    ]

    Enum.count(indicators, & &1) / length(indicators)
  end

  defp score_confidence_markers(reasoning) do
    # Positive markers
    has_verification = reasoning =~ ~r/verify|check|confirm/i
    has_certainty = reasoning =~ ~r/clearly|definitely|precisely/i

    # Negative markers
    has_uncertainty = reasoning =~ ~r/maybe|perhaps|might|unsure/i
    has_approximation = reasoning =~ ~r/roughly|about|approximately/i

    base = 0.5
    base = if has_verification, do: base + 0.2, else: base
    base = if has_certainty, do: base + 0.15, else: base
    base = if has_uncertainty, do: base - 0.25, else: base
    if has_approximation, do: max(0.0, base - 0.1), else: base
  end

  defp score_mathematical_rigor(reasoning) do
    indicators = [
      reasoning =~ ~r/formula|equation/i,
      reasoning =~ ~r/\^|power/i,
      reasoning =~ ~r/\(1\.\d+\)\^/,
      Regex.scan(~r/=/, reasoning) |> length() >= 3
    ]

    Enum.count(indicators, & &1) / length(indicators)
  end

  defp score_length(reasoning) do
    length = String.length(reasoning)

    cond do
      length < 80 -> 0.4
      length < 150 -> 0.7
      length < 350 -> 1.0
      length < 600 -> 0.9
      true -> 0.7
    end
  end

  defp calibrate_confidence(quality_score, factors) do
    # Start with quality score
    base_confidence = quality_score

    # Adjust based on confidence markers
    marker_adj = (factors.confidence_markers - 0.5) * 0.2

    # Boost for mathematical rigor
    rigor_boost = factors.mathematical_rigor * 0.1

    # Final calibrated confidence
    min(1.0, max(0.0, base_confidence + marker_adj + rigor_boost))
  end

  # Outlier Detection

  defp detect_outliers(paths) do
    # Calculate statistics
    qualities = Enum.map(paths, & &1.quality_score)
    lengths = Enum.map(paths, &String.length(&1.reasoning))

    avg_quality = Enum.sum(qualities) / length(qualities)
    avg_length = Enum.sum(lengths) / length(lengths)

    std_quality = calculate_std_dev(qualities, avg_quality)
    std_length = calculate_std_dev(lengths, avg_length)

    # Mark outliers
    Enum.map(paths, fn path ->
      quality_z = abs(path.quality_score - avg_quality) / (std_quality + 0.01)
      length_z = abs(String.length(path.reasoning) - avg_length) / (std_length + 1)

      is_outlier =
        quality_z > 2.0 or
          length_z > 2.5 or
          path.quality_score < 0.3

      outlier_reasons =
        []
        |> maybe_add(quality_z > 2.0, "Quality is #{Float.round(quality_z, 1)}σ from mean")
        |> maybe_add(length_z > 2.5, "Length is #{Float.round(length_z, 1)}σ from mean")
        |> maybe_add(path.quality_score < 0.3, "Very low quality score")

      path
      |> Map.put(:is_outlier, is_outlier)
      |> Map.put(:outlier_reasons, outlier_reasons)
      |> Map.put(:z_scores, %{quality: quality_z, length: length_z})
    end)
  end

  defp calculate_std_dev(values, mean) do
    variance =
      values
      |> Enum.map(fn x -> :math.pow(x - mean, 2) end)
      |> Enum.sum()
      |> Kernel./(length(values))

    :math.sqrt(variance)
  end

  defp maybe_add(list, condition, item) do
    if condition, do: [item | list], else: list
  end

  # Advanced Voting

  defp vote_and_select(paths, voting_strategy, all_paths) do
    votes =
      paths
      |> Enum.group_by(& &1.answer)
      |> Enum.map(fn {answer, answer_paths} ->
        {answer, length(answer_paths), answer_paths}
      end)
      |> Enum.sort_by(fn {_ans, count, _paths} -> -count end)

    {winner_answer, winner_paths} =
      case voting_strategy do
        :majority ->
          {answer, _count, paths} = List.first(votes)
          {answer, paths}

        :confidence_weighted ->
          select_weighted(votes, :confidence)

        :quality_weighted ->
          select_weighted(votes, :quality_score)

        :hybrid ->
          select_hybrid(votes)
      end

    build_result(winner_answer, winner_paths, paths, all_paths, voting_strategy)
  end

  defp select_weighted(votes, weight_key) do
    {answer, _weight, paths} =
      votes
      |> Enum.map(fn {answer, _count, paths} ->
        total_weight = Enum.sum(Enum.map(paths, &Map.get(&1, weight_key, 0)))
        {answer, total_weight, paths}
      end)
      |> Enum.max_by(fn {_ans, weight, _paths} -> weight end)

    {answer, paths}
  end

  defp select_hybrid(votes) do
    {answer, _score, paths} =
      votes
      |> Enum.map(fn {answer, count, paths} ->
        avg_conf = Enum.sum(Enum.map(paths, & &1.confidence)) / length(paths)
        avg_qual = Enum.sum(Enum.map(paths, & &1.quality_score)) / length(paths)

        score = count * 0.4 + avg_conf * count * 0.3 + avg_qual * count * 0.3
        {answer, score, paths}
      end)
      |> Enum.max_by(fn {_ans, score, _paths} -> score end)

    {answer, paths}
  end

  defp build_result(winner_answer, winner_paths, quality_paths, all_paths, voting_strategy) do
    consensus = length(winner_paths) / length(quality_paths)
    avg_confidence = Enum.sum(Enum.map(winner_paths, & &1.confidence)) / length(winner_paths)
    avg_quality = Enum.sum(Enum.map(winner_paths, & &1.quality_score)) / length(winner_paths)

    vote_distribution =
      quality_paths
      |> Enum.group_by(& &1.answer)
      |> Enum.map(fn {answer, paths} -> {answer, length(paths)} end)
      |> Enum.into(%{})

    outliers = Enum.filter(all_paths, & &1.is_outlier)

    %{
      answer: winner_answer,
      consensus: consensus,
      confidence: avg_confidence,
      quality: avg_quality,
      votes: vote_distribution,
      paths: quality_paths,
      winning_paths: winner_paths,
      voting_strategy: voting_strategy,
      outliers: outliers,
      metadata: %{
        total_paths: length(all_paths),
        quality_paths: length(quality_paths),
        outlier_count: length(outliers),
        unique_answers: map_size(vote_distribution)
      }
    }
  end

  # Display

  defp display_result(result) do
    IO.puts(String.duplicate("=", 70))
    IO.puts("\n✅ **Analysis Complete (via Runner)**\n")

    IO.puts("🎯 **Final Answer:** #{format_answer(result.answer)}")
    IO.puts("📊 **Consensus:** #{Float.round(result.consensus * 100, 1)}%")
    IO.puts("💯 **Avg Confidence:** #{Float.round(result.confidence * 100, 1)}%")

    # Calculate average quality from paths
    avg_quality =
      if length(result.paths) > 0 do
        result.paths
        |> Enum.map(& &1.quality_score)
        |> Enum.sum()
        |> Kernel./(length(result.paths))
      else
        0.0
      end

    IO.puts("⭐ **Avg Quality:** #{Float.round(avg_quality, 2)}")

    IO.puts("\n📈 **Vote Distribution:**")

    result.votes
    |> Enum.sort_by(fn {_ans, count} -> -count end)
    |> Enum.each(fn {answer, count} ->
      pct = Float.round(count / length(result.paths) * 100, 1)
      IO.puts("   • #{format_answer(answer)}: #{count} votes (#{pct}%)")
    end)

    IO.puts("\n📊 **Analytics:**")
    IO.puts("   • Total paths: #{length(result.paths)}")
    IO.puts("   • Unique answers: #{map_size(result.votes)}")
    IO.puts("   • Winner consensus: #{Float.round(result.consensus * 100, 1)}%")

    IO.puts("\n" <> String.duplicate("=", 70))
  end

  defp format_answer(answer) when is_float(answer), do: "$#{:erlang.float_to_binary(answer, decimals: 2)}"
  defp format_answer(answer), do: to_string(answer)

  @doc """
  Compare different voting strategies supported by the runner on the same problem.
  """
  def compare_voting_strategies(problem) do
    IO.puts("\n" <> String.duplicate("=", 70))
    IO.puts("  Voting Strategy Comparison (Runner-Based)")
    IO.puts(String.duplicate("=", 70) <> "\n")

    # Runner supports: :majority and :confidence_weighted
    strategies = [:majority, :confidence_weighted]

    results =
      Enum.map(strategies, fn strategy ->
        {:ok, result} = solve(problem, voting_strategy: strategy, sample_count: 7)
        {strategy, result}
      end)

    IO.puts("**Results by Strategy:**\n")

    Enum.each(results, fn {strategy, result} ->
      IO.puts("#{strategy}:")
      IO.puts("   Answer: #{format_answer(result.answer)}")
      IO.puts("   Consensus: #{Float.round(result.consensus * 100, 1)}%")
      IO.puts("   Confidence: #{Float.round(result.confidence * 100, 1)}%")
      IO.puts("")
    end)

    IO.puts("Note: Runner supports :majority and :confidence_weighted strategies.")
    IO.puts("For custom voting strategies, extend the VotingMechanism module.\n")

    {:ok, results}
  end

  @doc """
  Progressive refinement: Start small, expand if consensus is low.
  """
  def solve_with_refinement(problem, opts \\ []) do
    max_iterations = Keyword.get(opts, :max_iterations, 3)
    target_consensus = Keyword.get(opts, :target_consensus, 0.7)

    IO.puts("\n🔄 **Progressive Refinement**\n")

    # Phase 1: Quick check (3 paths)
    IO.puts("Phase 1: Quick exploration (3 paths)...")
    {:ok, result1} = solve(problem, sample_count: 3)

    if result1.consensus >= target_consensus do
      IO.puts("✓ High consensus achieved, stopping.\n")
      {:ok, result1}
    else
      IO.puts("⚠ Low consensus (#{Float.round(result1.consensus * 100, 1)}%), expanding...\n")

      # Phase 2: Standard (7 paths)
      IO.puts("Phase 2: Standard exploration (7 paths)...")
      {:ok, result2} = solve(problem, sample_count: 7)

      if result2.consensus >= target_consensus do
        IO.puts("✓ Acceptable consensus achieved.\n")
        {:ok, result2}
      else
        IO.puts("⚠ Still low consensus, final expansion...\n")

        # Phase 3: Thorough (15 paths)
        IO.puts("Phase 3: Thorough exploration (15 paths)...")
        {:ok, result3} = solve(problem, sample_count: 15)
        IO.puts("✓ Final result: #{Float.round(result3.consensus * 100, 1)}% consensus\n")
        {:ok, result3}
      end
    end
  end
end
