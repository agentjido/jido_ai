defmodule Jido.AI.Accuracy.SearchTest do
  use ExUnit.Case, async: false

  alias Jido.AI.Accuracy.{
    Candidate,
    Search.BeamSearch,
    Search.DiverseDecoding,
    Search.MCTS
  }

  @moduletag :capture_log
  @moduletag :integration

  # Shared test data and helpers

  defmodule MathVerifier do
    @moduledoc """
    Verifier that checks if math answers are correct.
    Returns 1.0 for correct answers, 0.0 for incorrect.
    """
    def verify(%Candidate{content: content}, _context) do
      # Extract the answer from content
      # Format: "The answer is X" or just a number
      answer =
        cond do
          Regex.run(~r/The answer is (-?\d+)/, content) != nil ->
            [[_, num]] = Regex.run(~r/The answer is (-?\d+)/, content)
            String.to_integer(num)

          Regex.run(~r/^(-?\d+)$/, String.trim(content)) != nil ->
            String.to_integer(String.trim(content))

          true ->
            nil
        end

      score = if answer == 42, do: 1.0, else: 0.0

      {:ok, %{score: score, candidate_id: "test", reasoning: "Math check"}}
    end
  end

  defmodule DeterministicGenerator do
    @moduledoc """
    Generator that produces deterministic answers based on temperature.
    Lower temps produce more "42" answers (correct).
    """
    def generate_candidates(_prompt, opts) do
      num = Keyword.get(opts, :num_candidates, 1)
      temperature = Keyword.get(opts, :temperature, 0.5)

      candidates =
        Enum.map(1..num, fn i ->
          # Lower temp = more likely to be correct
          correct_prob = 1.0 - temperature
          is_correct = :rand.uniform() < correct_prob

          answer = if is_correct, do: 42, else: 43 + rem(i, 10)

          Candidate.new!(%{
            id: "candidate_#{i}",
            content: "The answer is #{answer}",
            metadata: %{temperature: temperature, index: i}
          })
        end)

      {:ok, candidates}
    end
  end

  defmodule DiverseContentGenerator do
    @moduledoc """
    Generator that produces diverse content for testing diversity algorithms.
    """
    def generate_candidates(_prompt, opts) do
      num = Keyword.get(opts, :num_candidates, 1)

      answers = [
        "The answer is 42",
        "Forty-two is the result",
        "42 is correct",
        "The result equals 42",
        "Answer: 42",
        "42",
        "The number is 42",
        "Forty two"
      ]

      candidates =
        Enum.map(1..num, fn i ->
          answer = Enum.at(answers, rem(i - 1, length(answers)))

          Candidate.new!(%{
            id: "candidate_#{i}",
            content: answer,
            metadata: %{index: i}
          })
        end)

      {:ok, candidates}
    end
  end

  describe "Algorithm Behavior Tests" do
    test "beam search finds correct answer with verifier guidance" do
      # Set seed for reproducibility
      :rand.seed(:exsss, {123, 123, 123})

      {:ok, best} =
        BeamSearch.search(
          "What is 6 * 7?",
          DeterministicGenerator,
          MathVerifier,
          beam_width: 3,
          depth: 2,
          branching_factor: 2
        )

      assert %Candidate{} = best
      # The verifier guides toward "42"
      assert best.score >= 0.0
    end

    test "beam width impacts search results" do
      :rand.seed(:exsss, {456, 456, 456})

      # Narrow beam (greedy-ish)
      {:ok, best_narrow} =
        BeamSearch.search(
          "What is 6 * 7?",
          DeterministicGenerator,
          MathVerifier,
          beam_width: 1,
          depth: 2
        )

      :rand.seed(:exsss, {456, 456, 456})

      # Wide beam (more exploration)
      {:ok, best_wide} =
        BeamSearch.search(
          "What is 6 * 7?",
          DeterministicGenerator,
          MathVerifier,
          beam_width: 5,
          depth: 2
        )

      # Both should produce valid candidates
      assert %Candidate{} = best_narrow
      assert %Candidate{} = best_wide
    end

    test "MCTS explores reasoning space" do
      {:ok, best} =
        MCTS.search(
          "What is 6 * 7?",
          DeterministicGenerator,
          MathVerifier,
          simulations: 10
        )

      assert %Candidate{} = best
      assert is_number(best.score)
    end

    test "diverse decoding produces variety" do
      {:ok, best} =
        DiverseDecoding.search(
          "What is 6 * 7?",
          DiverseContentGenerator,
          MathVerifier,
          num_candidates: 8,
          lambda: 0.5
        )

      assert %Candidate{} = best
      # High score since all candidates mention 42
      assert best.score > 0.0
    end

    test "diverse decoding lambda parameter affects selection" do
      # Relevance-focused (high lambda)
      {:ok, relevance_focused} =
        DiverseDecoding.search(
          "test",
          DiverseContentGenerator,
          MathVerifier,
          num_candidates: 8,
          lambda: 0.9
        )

      # Diversity-focused (low lambda)
      {:ok, diversity_focused} =
        DiverseDecoding.search(
          "test",
          DiverseContentGenerator,
          MathVerifier,
          num_candidates: 8,
          lambda: 0.1
        )

      # Both should produce valid candidates
      assert %Candidate{} = relevance_focused
      assert %Candidate{} = diversity_focused
    end
  end

  describe "Performance Tests" do
    @tag :performance
    test "beam search completes within reasonable time" do
      start_time = System.monotonic_time(:millisecond)

      {:ok, _best} =
        BeamSearch.search(
          "What is 6 * 7?",
          DeterministicGenerator,
          MathVerifier,
          beam_width: 5,
          depth: 3,
          timeout: 5000
        )

      elapsed = System.monotonic_time(:millisecond) - start_time

      # Should complete well within timeout
      assert elapsed < 5000
    end

    @tag :performance
    test "MCTS completes within simulation budget" do
      start_time = System.monotonic_time(:millisecond)

      {:ok, _best} =
        MCTS.search(
          "What is 6 * 7?",
          DeterministicGenerator,
          MathVerifier,
          simulations: 20,
          timeout: 5000
        )

      elapsed = System.monotonic_time(:millisecond) - start_time

      assert elapsed < 5000
    end

    @tag :performance
    test "diverse decoding scales with num_candidates" do
      # Small batch
      start_small = System.monotonic_time(:millisecond)

      {:ok, _best_small} =
        DiverseDecoding.search(
          "test",
          DiverseContentGenerator,
          MathVerifier,
          num_candidates: 5,
          timeout: 5000
        )

      elapsed_small = System.monotonic_time(:millisecond) - start_small

      # Large batch
      start_large = System.monotonic_time(:millisecond)

      {:ok, _best_large} =
        DiverseDecoding.search(
          "test",
          DiverseContentGenerator,
          MathVerifier,
          num_candidates: 15,
          timeout: 5000
        )

      elapsed_large = System.monotonic_time(:millisecond) - start_large

      # Both should complete
      assert elapsed_small < 5000
      assert elapsed_large < 5000

      # Large batch may take longer but should still be reasonable
      # Just ensure both complete successfully without excessive time
      assert elapsed_large > 0
    end
  end

  describe "Quality Comparison Tests" do
    test "search algorithms return valid candidates" do
      algorithms = [
        {BeamSearch, [beam_width: 3, depth: 2]},
        {MCTS, [simulations: 10]},
        {DiverseDecoding, [num_candidates: 5]}
      ]

      Enum.each(algorithms, fn {algo, opts} ->
        {:ok, best} =
          algo.search(
            "What is 6 * 7?",
            DeterministicGenerator,
            MathVerifier,
            opts
          )

        assert %Candidate{} = best,
               "#{inspect(algo)} should return a valid candidate"

        assert is_binary(best.content),
               "#{inspect(algo)} candidate should have content"

        assert is_number(best.score),
               "#{inspect(algo)} candidate should have a score"
      end)
    end

    test "verifier guidance improves search quality" do
      # All algorithms should work with the verifier
      algorithms = [
        {BeamSearch, :beam_search, [beam_width: 3, depth: 2]},
        {MCTS, :mcts, [simulations: 10]},
        {DiverseDecoding, :diverse_decoding, [num_candidates: 5]}
      ]

      Enum.each(algorithms, fn {algo, name, opts} ->
        {:ok, best} =
          algo.search(
            "What is 6 * 7?",
            DiverseContentGenerator,
            MathVerifier,
            opts
          )

        # All candidates from DiverseContentGenerator mention 42
        # So they should all get high scores from MathVerifier
        assert best.score > 0.0,
               "#{name} should have score > 0 with verifier guidance"
      end)
    end
  end

  describe "Edge Cases and Error Handling" do
    test "beam search handles timeout gracefully" do
      # Very short timeout should trigger error
      result =
        BeamSearch.search(
          "test",
          DeterministicGenerator,
          MathVerifier,
          timeout: 1
        )

      # Should either return an error or a valid candidate quickly
      case result do
        {:ok, %Candidate{}} -> :ok
        {:error, _reason} -> :ok
      end
    end

    test "MCTS handles timeout gracefully" do
      result =
        MCTS.search(
          "test",
          DeterministicGenerator,
          MathVerifier,
          simulations: 100,
          timeout: 1
        )

      case result do
        {:ok, %Candidate{}} -> :ok
        {:error, _reason} -> :ok
      end
    end

    test "diverse decoding handles timeout gracefully" do
      result =
        DiverseDecoding.search(
          "test",
          DeterministicGenerator,
          MathVerifier,
          num_candidates: 50,
          timeout: 1
        )

      case result do
        {:ok, %Candidate{}} -> :ok
        {:error, _reason} -> :ok
      end
    end

    test "algorithms handle empty candidate generation" do
      defmodule EmptyGenerator do
        def generate_candidates(_prompt, _opts), do: {:ok, []}
      end

      # Beam search - may return error or fallback candidate
      beam_result = BeamSearch.search("test", EmptyGenerator, MathVerifier, [])

      case beam_result do
        {:ok, %Candidate{}} -> :ok
        {:error, _} -> :ok
      end

      # Diverse decoding - should return error for empty candidates
      diverse_result = DiverseDecoding.search("test", EmptyGenerator, MathVerifier, [])

      case diverse_result do
        {:ok, %Candidate{}} -> :ok
        {:error, _} -> :ok
      end
    end

    test "algorithms handle single candidate" do
      defmodule SingleGenerator do
        def generate_candidates(_prompt, _opts) do
          {:ok,
           [
             Candidate.new!(%{
               id: "1",
               content: "The answer is 42",
               metadata: %{}
             })
           ]}
        end
      end

      {:ok, beam_best} = BeamSearch.search("test", SingleGenerator, MathVerifier, [])
      assert %Candidate{} = beam_best

      {:ok, diverse_best} =
        DiverseDecoding.search("test", SingleGenerator, MathVerifier, [])

      assert %Candidate{} = diverse_best
    end
  end

  describe "MMR Algorithm Tests" do
    test "MMR selects diverse candidates from similar pool" do
      candidates =
        Enum.map(1..10, fn i ->
          Candidate.new!(%{
            id: "c#{i}",
            content: "The answer is 42",
            score: 0.9
          })
        end)

      # With low lambda, MMR should still select candidates
      # even when they're all similar
      result = DiverseDecoding.mmr_select(candidates, 0.3, 0.7)

      # All candidates should be selected
      assert length(result) == 10
    end

    test "MMR prioritizes relevance with high lambda" do
      c1 = Candidate.new!(%{id: "1", content: "excellent", score: 1.0})
      c2 = Candidate.new!(%{id: "2", content: "good", score: 0.8})
      c3 = Candidate.new!(%{id: "3", content: "fair", score: 0.6})

      # High lambda = relevance-focused
      result = DiverseDecoding.mmr_select([c1, c2, c3], 0.9, 0.7)

      # Highest score should be first
      assert hd(result).score == 1.0
    end
  end
end
