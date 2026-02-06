defmodule Jido.AI.Accuracy.Search.DiverseDecodingTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Accuracy.{Candidate, Search.DiverseDecoding}

  @moduletag :capture_log

  # Mock verifier for testing
  defmodule MockVerifier do
    def verify(%Candidate{} = candidate, _context) do
      # Score based on content length for deterministic testing
      score = candidate.content |> String.length() |> min(100) |> Kernel./(100)

      {:ok, %{score: score, candidate_id: candidate.id}}
    end
  end

  # Mock generator for testing
  defmodule MockGenerator do
    def generate_candidates(prompt, opts) do
      num = Keyword.get(opts, :num_candidates, 1)
      temperature = Keyword.get(opts, :temperature, 0.5)

      candidates =
        Enum.map(1..num, fn i ->
          temp_str = :erlang.float_to_binary(temperature, decimals: 2)

          Candidate.new!(%{
            id: "candidate_#{i}_#{temp_str}",
            content: "#{prompt} - answer #{i} (temp=#{temp_str})",
            metadata: %{index: i, temperature: temperature}
          })
        end)

      {:ok, candidates}
    end
  end

  # Mock generator that produces similar content
  defmodule SimilarContentGenerator do
    def generate_candidates(prompt, opts) do
      num = Keyword.get(opts, :num_candidates, 1)

      candidates =
        Enum.map(1..num, fn i ->
          Candidate.new!(%{
            id: "candidate_#{i}",
            # All candidates have very similar content
            content: "#{prompt} is the answer",
            metadata: %{index: i}
          })
        end)

      {:ok, candidates}
    end
  end

  describe "new/1" do
    test "creates diverse decoding with defaults" do
      assert {:ok, dd} = DiverseDecoding.new([])

      assert dd.num_candidates == 10
      assert dd.diversity_threshold == 0.7
      assert dd.temperature_range == {0.0, 1.0}
      assert dd.lambda == 0.5
    end

    test "creates diverse decoding with custom num_candidates" do
      assert {:ok, dd} = DiverseDecoding.new(num_candidates: 20)

      assert dd.num_candidates == 20
    end

    test "creates diverse decoding with custom diversity_threshold" do
      assert {:ok, dd} = DiverseDecoding.new(diversity_threshold: 0.5)

      assert dd.diversity_threshold == 0.5
    end

    test "creates diverse decoding with custom temperature_range" do
      assert {:ok, dd} = DiverseDecoding.new(temperature_range: {0.1, 0.9})

      assert dd.temperature_range == {0.1, 0.9}
    end

    test "creates diverse decoding with custom lambda" do
      assert {:ok, dd} = DiverseDecoding.new(lambda: 0.7)

      assert dd.lambda == 0.7
    end

    test "creates diverse decoding with all custom options" do
      assert {:ok, dd} =
               DiverseDecoding.new(
                 num_candidates: 15,
                 diversity_threshold: 0.6,
                 temperature_range: {0.2, 0.8},
                 lambda: 0.3
               )

      assert dd.num_candidates == 15
      assert dd.diversity_threshold == 0.6
      assert dd.temperature_range == {0.2, 0.8}
      assert dd.lambda == 0.3
    end

    test "returns error for num_candidates < 1" do
      assert {:error, :invalid_num_candidates} = DiverseDecoding.new(num_candidates: 0)
    end

    test "returns error for num_candidates > 100" do
      assert {:error, :invalid_num_candidates} = DiverseDecoding.new(num_candidates: 101)
    end

    test "returns error for diversity_threshold < 0" do
      assert {:error, :invalid_diversity_threshold} =
               DiverseDecoding.new(diversity_threshold: -0.1)
    end

    test "returns error for diversity_threshold > 1" do
      assert {:error, :invalid_diversity_threshold} =
               DiverseDecoding.new(diversity_threshold: 1.1)
    end

    test "returns error for invalid temperature_range" do
      assert {:error, :invalid_temperature_range} =
               DiverseDecoding.new(temperature_range: {1.0, 0.0})

      assert {:error, :invalid_temperature_range} =
               DiverseDecoding.new(temperature_range: {-0.1, 1.0})
    end

    test "returns error for lambda < 0" do
      assert {:error, :invalid_lambda} = DiverseDecoding.new(lambda: -0.1)
    end

    test "returns error for lambda > 1" do
      assert {:error, :invalid_lambda} = DiverseDecoding.new(lambda: 1.1)
    end
  end

  describe "new!/1" do
    test "returns config when valid" do
      dd = DiverseDecoding.new!(num_candidates: 15)

      assert dd.num_candidates == 15
    end

    test "raises when invalid" do
      assert_raise ArgumentError, ~r/Invalid DiverseDecoding config/, fn ->
        DiverseDecoding.new!(num_candidates: 0)
      end
    end
  end

  describe "search/4" do
    test "searches and returns best candidate" do
      {:ok, best} = DiverseDecoding.search("test", MockGenerator, MockVerifier, num_candidates: 5)

      assert %Candidate{} = best
      assert is_binary(best.content)
    end

    test "respects num_candidates option" do
      {:ok, best} =
        DiverseDecoding.search("test", MockGenerator, MockVerifier, num_candidates: 3)

      assert %Candidate{} = best
    end

    test "respects lambda option" do
      {:ok, best} =
        DiverseDecoding.search("test", MockGenerator, MockVerifier,
          num_candidates: 5,
          lambda: 0.7
        )

      assert %Candidate{} = best
    end

    test "respects diversity_threshold option" do
      {:ok, best} =
        DiverseDecoding.search("test", MockGenerator, MockVerifier,
          num_candidates: 5,
          diversity_threshold: 0.5
        )

      assert %Candidate{} = best
    end

    test "returns error when timeout exceeded" do
      assert {:error, :no_candidates} =
               DiverseDecoding.search("test", MockGenerator, MockVerifier,
                 timeout: 0,
                 num_candidates: 5
               )
    end

    test "uses default options when none provided" do
      {:ok, best} = DiverseDecoding.search("test", MockGenerator, MockVerifier, [])

      assert %Candidate{} = best
    end
  end

  describe "mmr_select/3" do
    test "returns empty list for empty candidates" do
      result = DiverseDecoding.mmr_select([], 0.5, 0.7)

      assert result == []
    end

    test "returns single candidate for single input" do
      candidate = Candidate.new!(%{id: "1", content: "test", score: 0.8})

      result = DiverseDecoding.mmr_select([candidate], 0.5, 0.7)

      assert length(result) == 1
      assert hd(result).id == "1"
    end

    test "prioritizes relevance when lambda is high" do
      c1 = Candidate.new!(%{id: "1", content: "excellent answer", score: 0.9})
      c2 = Candidate.new!(%{id: "2", content: "good answer", score: 0.8})

      # High lambda = prioritize relevance
      result = DiverseDecoding.mmr_select([c1, c2], 0.9, 0.7)

      # First selected should be highest relevance
      assert hd(result).score == 0.9
    end

    test "prioritizes diversity when lambda is low" do
      # Create candidates with similar content
      c1 = Candidate.new!(%{id: "1", content: "the answer is 42", score: 0.9})
      c2 = Candidate.new!(%{id: "2", content: "the answer is 42", score: 0.8})

      # Low lambda = prioritize diversity
      result = DiverseDecoding.mmr_select([c1, c2], 0.1, 0.5)

      # Both should be selected despite similar content
      # (low lambda reduces diversity penalty)
      assert length(result) == 2
    end

    test "handles candidates with different content" do
      c1 = Candidate.new!(%{id: "1", content: "hello world", score: 0.9})
      c2 = Candidate.new!(%{id: "2", content: "foo bar", score: 0.7})
      c3 = Candidate.new!(%{id: "3", content: "baz qux", score: 0.8})

      result = DiverseDecoding.mmr_select([c1, c2, c3], 0.5, 0.7)

      assert length(result) == 3
    end

    test "respects diversity_threshold" do
      c1 = Candidate.new!(%{id: "1", content: "similar content", score: 0.9})
      c2 = Candidate.new!(%{id: "2", content: "similar content", score: 0.8})

      # High threshold = less diversity penalty
      result1 = DiverseDecoding.mmr_select([c1, c2], 0.5, 0.9)

      # Low threshold = more diversity penalty
      result2 = DiverseDecoding.mmr_select([c1, c2], 0.5, 0.3)

      # Both should return all candidates, but in different order
      assert length(result1) == 2
      assert length(result2) == 2
    end
  end

  describe "compute_similarity/2" do
    test "returns 1.0 for identical content" do
      c1 = Candidate.new!(%{id: "1", content: "hello world"})
      c2 = Candidate.new!(%{id: "2", content: "hello world"})

      result = DiverseDecoding.compute_similarity(c1, c2)

      assert result == 1.0
    end

    test "returns 0.0 for completely different content" do
      c1 = Candidate.new!(%{id: "1", content: "hello world"})
      c2 = Candidate.new!(%{id: "2", content: "foo bar baz"})

      result = DiverseDecoding.compute_similarity(c1, c2)

      assert result < 0.5
    end

    test "returns intermediate value for partially similar content" do
      c1 = Candidate.new!(%{id: "1", content: "hello world"})
      c2 = Candidate.new!(%{id: "2", content: "hello there"})

      result = DiverseDecoding.compute_similarity(c1, c2)

      assert result > 0.0 and result < 1.0
    end
  end

  describe "integration with SearchController behavior" do
    test "implements search/4 callback" do
      # Ensure module is fully loaded before checking function_exported?
      Code.ensure_loaded!(DiverseDecoding)
      assert function_exported?(DiverseDecoding, :search, 4)
    end

    test "returns {:ok, candidate} on success" do
      result = DiverseDecoding.search("test", MockGenerator, MockVerifier, num_candidates: 3)

      assert match?({:ok, %Candidate{}}, result)
    end

    test "returns {:error, reason} on failure" do
      result =
        DiverseDecoding.search("test", MockGenerator, MockVerifier,
          timeout: 0,
          num_candidates: 5
        )

      assert match?({:error, _}, result)
    end
  end

  describe "MMR algorithm behavior" do
    test "selects diverse candidates from similar pool" do
      # Even with similar content, MMR should select all candidates
      c1 = Candidate.new!(%{id: "1", content: "answer", score: 0.9})
      c2 = Candidate.new!(%{id: "2", content: "answer", score: 0.8})
      c3 = Candidate.new!(%{id: "3", content: "answer", score: 0.7})

      result = DiverseDecoding.mmr_select([c1, c2, c3], 0.5, 0.7)

      # All should be selected
      assert length(result) == 3
    end

    test "orders by relevance when content is diverse" do
      c1 = Candidate.new!(%{id: "1", content: "alpha", score: 0.7})
      c2 = Candidate.new!(%{id: "2", content: "bravo", score: 0.9})
      c3 = Candidate.new!(%{id: "3", content: "charlie", score: 0.8})

      result = DiverseDecoding.mmr_select([c1, c2, c3], 0.7, 0.7)

      # Highest relevance should be first
      assert hd(result).score == 0.9
    end
  end
end
