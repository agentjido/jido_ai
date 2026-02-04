#!/usr/bin/env elixir

# Real Accuracy Pipeline Demo
#
# Run with:
#   mix run examples/accuracy/real_pipeline_demo.exs
#
# This example makes REAL LLM calls to demonstrate how the Accuracy
# pipeline improves reliability on reasoning tasks.
#
# Requirements: Set ANTHROPIC_API_KEY in .env file or environment
#   echo "ANTHROPIC_API_KEY=your-key-here" >> .env

# Load .env file if present (dotenvy is a dep of req_llm)
if File.exists?(".env") do
  Dotenvy.source!([".env"])
end

Application.ensure_all_started(:jido_ai)

alias Jido.AI.Accuracy.{
  Pipeline,
  PipelineConfig,
  Candidate
}

defmodule AccuracyDemo do
  @moduledoc """
  Demonstrates the Accuracy pipeline on tricky reasoning problems.

  These problems are designed to be easy to get wrong if you rush:

  1. "A farmer has 17 sheep. All but 9 run away. How many are left?"
     Many LLMs incorrectly answer "8" (17-9). Correct: "9"

  2. "A bat and ball cost $1.10. The bat costs $1.00 more than the ball."
     Intuitive wrong answer: $0.10. Correct: $0.05
  """

  # Use environment to determine model - prefer Anthropic, fallback to OpenAI
  @model (cond do
            System.get_env("ANTHROPIC_API_KEY") -> "anthropic:claude-haiku-4-5"
            System.get_env("OPENAI_API_KEY") -> "openai:gpt-4o-mini"
            true -> "anthropic:claude-haiku-4-5"
          end)

  @tricky_problem """
  A farmer has 17 sheep. All but 9 run away. How many sheep does the farmer have left?

  Think carefully and give just the number.
  """

  @reasoning_problem """
  A bat and ball cost $1.10 together. The bat costs $1.00 more than the ball.
  How much does the ball cost?

  Show your work step by step, then give the final answer.
  """

  def run do
    IO.puts("""
    ╔══════════════════════════════════════════════════════════════════╗
    ║              JIDO.AI ACCURACY PIPELINE DEMO                     ║
    ║                                                                  ║
    ║  This demo shows how generating multiple candidates and         ║
    ║  selecting by consensus improves LLM reliability.               ║
    ╚══════════════════════════════════════════════════════════════════╝
    """)

    case check_api_key() do
      :ok ->
        demo_single_vs_multi()
        demo_self_consistency()
        demo_full_pipeline()

      {:error, msg} ->
        IO.puts(msg)
    end
  end

  defp check_api_key do
    cond do
      System.get_env("ANTHROPIC_API_KEY") ->
        IO.puts("Using model: anthropic:claude-haiku-4-5\n")
        :ok

      System.get_env("OPENAI_API_KEY") ->
        IO.puts("Using model: openai:gpt-4o-mini\n")
        :ok

      true ->
        {:error, """
        ⚠️  No API key found!

        Please set one of:
          export ANTHROPIC_API_KEY=your-key-here
          export OPENAI_API_KEY=your-key-here

        Or add to .env file:
          echo "ANTHROPIC_API_KEY=sk-..." >> .env

        Then run again:
          mix run examples/accuracy/real_pipeline_demo.exs
        """}
    end
  end

  # Demo 1: Compare single generation vs multi-candidate
  defp demo_single_vs_multi do
    IO.puts("\n" <> String.duplicate("─", 70))
    IO.puts("DEMO 1: Single Generation vs Multi-Candidate Consensus")
    IO.puts(String.duplicate("─", 70))

    IO.puts("""
    Problem: "A farmer has 17 sheep. All but 9 run away. How many are left?"

    This is a classic trick question. The answer is 9 (not 17-9=8).
    Let's see how a single LLM call compares to majority voting.
    """)

    # Single generation
    IO.puts("→ Single generation (temperature=0.7)...")
    single_start = System.monotonic_time(:millisecond)

    case generate_single(@tricky_problem, 0.7) do
      {:ok, single_response} ->
        single_duration = System.monotonic_time(:millisecond) - single_start
        IO.puts("  Answer: #{String.trim(single_response)}")
        IO.puts("  Time: #{single_duration}ms")

      {:error, reason} ->
        IO.puts("  Error: #{inspect(reason)}")
    end

    # Multi-candidate with majority vote
    IO.puts("\n→ Multi-candidate (5 generations, majority vote)...")
    multi_start = System.monotonic_time(:millisecond)

    case generate_multiple(@tricky_problem, 5) do
      {:ok, candidates} ->
        multi_duration = System.monotonic_time(:millisecond) - multi_start

        # Show all candidates
        IO.puts("  Candidates generated:")

        candidates
        |> Enum.with_index(1)
        |> Enum.each(fn {candidate, i} ->
          content = candidate.content |> String.trim() |> String.slice(0, 60)
          IO.puts("    #{i}. #{content}")
        end)

        # Majority vote
        {best_answer, vote_count, total} = majority_vote(candidates)
        confidence = vote_count / total

        IO.puts("\n  ✓ Majority vote result: #{best_answer}")
        IO.puts("  ✓ Agreement: #{vote_count}/#{total} (#{Float.round(confidence * 100, 1)}%)")
        IO.puts("  ✓ Time: #{multi_duration}ms")

        IO.puts("""

        Key insight: With 5 candidates, incorrect answers get "outvoted"
        by the correct ones, even if some individual responses are wrong.
        """)

      {:error, reason} ->
        IO.puts("  Error: #{inspect(reason)}")
    end
  end

  # Demo 2: Chain-of-Thought with majority voting
  defp demo_self_consistency do
    IO.puts("\n" <> String.duplicate("─", 70))
    IO.puts("DEMO 2: Chain-of-Thought with Majority Voting")
    IO.puts(String.duplicate("─", 70))

    IO.puts("""
    Problem: "A bat and ball cost $1.10. The bat costs $1.00 more than the ball.
              How much does the ball cost?"

    This is the famous "bat and ball" problem. The intuitive (wrong) answer
    is $0.10, but the correct answer is $0.05.

    Let's generate 5 candidates with step-by-step reasoning.
    """)

    IO.puts("→ Generating 5 candidates with Chain-of-Thought...")

    start_time = System.monotonic_time(:millisecond)

    case generate_multiple(@reasoning_problem, 5) do
      {:ok, candidates} ->
        duration = System.monotonic_time(:millisecond) - start_time

        IO.puts("\n  Candidates generated:")

        candidates
        |> Enum.with_index(1)
        |> Enum.each(fn {candidate, i} ->
          # Extract the final answer (look for dollar amounts)
          answer = extract_dollar_amount(candidate.content)
          IO.puts("    #{i}. #{answer}")
        end)

        # Majority vote on extracted answers
        {best_answer, vote_count, total} = majority_vote_dollars(candidates)
        confidence = vote_count / total

        IO.puts("\n  ✓ Majority vote result: #{best_answer}")
        IO.puts("  ✓ Agreement: #{vote_count}/#{total} (#{Float.round(confidence * 100, 1)}%)")
        IO.puts("  ✓ Duration: #{duration}ms")

        # Check if the model got it right
        correct = best_answer == "$0.05"

        if correct do
          IO.puts("\n  ✅ Correct! The ball costs $0.05")
        else
          IO.puts("""

          ⚠️  Interesting! The model answered #{best_answer} (correct: $0.05)

          This demonstrates an important limitation of self-consistency:
          It helps with RANDOM errors, but if the model has a systematic
          bias (like the intuitive-but-wrong $0.10), all candidates will
          agree on the wrong answer. High consensus ≠ correctness.

          This is why the Accuracy pipeline also includes:
          • Verification stages (to catch systematic errors)
          • Reflection loops (to critique and revise answers)
          """)
        end

        # Show reasoning from one candidate
        IO.puts("  Sample reasoning (from candidate 1):")

        candidates
        |> List.first()
        |> Map.get(:content)
        |> String.split("\n")
        |> Enum.take(6)
        |> Enum.each(&IO.puts("    │ #{String.slice(&1, 0, 65)}"))

      {:error, reason} ->
        IO.puts("  Error: #{inspect(reason)}")
    end
  end

  # Demo 3: Full Pipeline with stages
  defp demo_full_pipeline do
    IO.puts("\n" <> String.duplicate("─", 70))
    IO.puts("DEMO 3: Full Accuracy Pipeline")
    IO.puts(String.duplicate("─", 70))

    IO.puts("""
    Now let's run the complete pipeline with:
      1. Difficulty estimation (determines how many candidates to generate)
      2. Multi-candidate generation
      3. Calibration (routes based on confidence)

    Using a logic puzzle that requires careful reasoning.
    """)

    logic_problem = """
    If it takes 5 machines 5 minutes to make 5 widgets,
    how long would it take 100 machines to make 100 widgets?

    Reason step by step, then give the final answer in minutes.
    """

    IO.puts("Problem: #{String.trim(logic_problem)}\n")

    # Create a generator function that wraps our LLM calls
    generator = fn query, _context ->
      case generate_single(query, 0.7) do
        {:ok, content} -> {:ok, Candidate.new!(%{content: content})}
        error -> error
      end
    end

    # Create pipeline with custom config
    {:ok, config} =
      PipelineConfig.new(%{
        stages: [:difficulty_estimation, :generation, :calibration],
        generation_config: %{
          min_candidates: 3,
          max_candidates: 7,
          batch_size: 3,
          early_stop_threshold: 0.8
        },
        calibration_config: %{
          high_threshold: 0.7,
          low_threshold: 0.4,
          medium_action: :with_verification,
          low_action: :abstain
        }
      })

    {:ok, pipeline} = Pipeline.new(%{config: config})

    IO.puts("→ Running pipeline...")
    start_time = System.monotonic_time(:millisecond)

    case Pipeline.run(pipeline, logic_problem, generator: generator, timeout: 120_000) do
      {:ok, result} ->
        duration = System.monotonic_time(:millisecond) - start_time

        IO.puts("\n  ┌─────────────────────────────────────────┐")
        IO.puts("  │ PIPELINE RESULT                         │")
        IO.puts("  ├─────────────────────────────────────────┤")
        IO.puts("  │ Answer: #{format_content(result.answer) |> String.pad_trailing(30)}│")
        IO.puts("  │ Confidence: #{Float.round(result.confidence * 100, 1)}%#{String.duplicate(" ", 24)}│")
        IO.puts("  │ Action: #{inspect(result.action) |> String.pad_trailing(30)}│")
        IO.puts("  └─────────────────────────────────────────┘")

        IO.puts("\n  Execution trace:")

        result.trace
        |> Enum.each(fn entry ->
          status = if entry.status == :ok, do: "✓", else: "✗"
          IO.puts("    #{status} #{entry.stage} (#{entry.duration_ms}ms)")
        end)

        IO.puts("\n  Pipeline metadata:")
        IO.puts("    • Total duration: #{duration}ms")
        IO.puts("    • Candidates generated: #{result.metadata.num_candidates}")

        difficulty_level =
          case result.metadata.difficulty do
            %{level: level} -> level
            _ -> :unknown
          end

        IO.puts("    • Difficulty level: #{difficulty_level}")

        if result.metadata.num_candidates == 1 do
          IO.puts("""

          Note: Only 1 candidate was generated because the internal
          AdaptiveSelfConsistency uses the generator function directly.
          For multi-candidate generation in the pipeline, configure
          the generation_config with higher min_candidates.
          """)
        end

      {:error, reason} ->
        IO.puts("  Pipeline error: #{inspect(reason)}")
    end

    IO.puts("""

    ╔══════════════════════════════════════════════════════════════════╗
    ║  DEMO COMPLETE                                                   ║
    ║                                                                  ║
    ║  The Accuracy pipeline trades compute for reliability:          ║
    ║  • More candidates = higher chance of correct answer            ║
    ║  • Majority voting filters out random errors                    ║
    ║  • Confidence scores let you decide when to trust the answer    ║
    ╚══════════════════════════════════════════════════════════════════╝
    """)
  end

  # Helper: Generate a single response using ReqLLM.Context
  defp generate_single(prompt, temperature) do
    context =
      ReqLLM.Context.new()
      |> ReqLLM.Context.append(ReqLLM.Context.text(:user, prompt))

    case ReqLLM.Generation.generate_text(@model, context, temperature: temperature) do
      {:ok, response} ->
        content = extract_content(response)
        {:ok, content}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Helper: Generate multiple candidates in parallel
  # Note: LLMGenerator has a bug with ReqLLM.Message format, so we do it manually
  defp generate_multiple(prompt, n) do
    temps = for _ <- 1..n, do: 0.3 + :rand.uniform() * 0.6

    results =
      temps
      |> Task.async_stream(
        fn temp ->
          case generate_single(prompt, temp) do
            {:ok, content} -> Candidate.new!(%{content: content, metadata: %{temperature: temp}})
            _ -> nil
          end
        end,
        max_concurrency: 3,
        timeout: 30_000,
        on_timeout: :kill_task
      )
      |> Enum.map(fn
        {:ok, candidate} when not is_nil(candidate) -> candidate
        _ -> nil
      end)
      |> Enum.reject(&is_nil/1)

    if Enum.empty?(results) do
      {:error, :all_generations_failed}
    else
      {:ok, results}
    end
  end

  # Helper: Simple majority vote
  defp majority_vote(candidates) do
    # Normalize answers (extract just the number if present)
    normalized =
      candidates
      |> Enum.map(fn c ->
        c.content
        |> String.trim()
        |> normalize_answer()
      end)

    # Count votes
    vote_counts =
      normalized
      |> Enum.frequencies()
      |> Enum.sort_by(fn {_, count} -> count end, :desc)

    case vote_counts do
      [{answer, count} | _] -> {answer, count, length(candidates)}
      [] -> {"no answer", 0, 0}
    end
  end

  # Extract just the core answer (number, letter, etc.)
  defp normalize_answer(text) do
    # Try to extract a number
    case Regex.run(~r/\b(\d+(?:\.\d+)?)\b/, text) do
      [_, num] -> num
      nil -> String.slice(text, 0, 50)
    end
  end

  # Extract dollar amount from text - look for final answer patterns
  defp extract_dollar_amount(text) do
    # Look for common "final answer" patterns with dollar amounts
    patterns = [
      ~r/(?:ball costs?|answer is|costs?|=)\s*\$?(0\.\d{2})/i,
      ~r/\*\*\$?(0\.\d{2})\*\*/,
      ~r/(?:therefore|so|thus)[^\$]*\$?(0\.\d{2})/i
    ]

    result =
      Enum.find_value(patterns, fn pattern ->
        case Regex.run(pattern, text) do
          [_, amount] -> "$#{amount}"
          _ -> nil
        end
      end)

    result || String.slice(text, -40, 40)
  end

  # Majority vote for dollar amounts
  defp majority_vote_dollars(candidates) do
    normalized =
      candidates
      |> Enum.map(fn c -> extract_dollar_amount(c.content) end)

    vote_counts =
      normalized
      |> Enum.frequencies()
      |> Enum.sort_by(fn {_, count} -> count end, :desc)

    case vote_counts do
      [{answer, count} | _] -> {answer, count, length(candidates)}
      [] -> {"no answer", 0, 0}
    end
  end

  defp extract_content(response) do
    case response.message.content do
      nil ->
        ""

      content when is_binary(content) ->
        content

      content when is_list(content) ->
        content
        |> Enum.filter(fn
          %{type: :text} -> true
          _ -> false
        end)
        |> Enum.map_join("", fn %{text: text} -> text end)
    end
  end

  defp format_content(nil), do: "(no answer)"

  defp format_content(content) when is_binary(content) do
    content
    |> String.trim()
    |> String.split("\n")
    |> List.first()
    |> String.slice(0, 50)
  end

  defp format_content(content) when is_map(content) do
    Map.get(content, :content, "(no answer)") |> format_content()
  end

  defp format_content(_), do: "(unknown format)"
end

# Run the demo
AccuracyDemo.run()
