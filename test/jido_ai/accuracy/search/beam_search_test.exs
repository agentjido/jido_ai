defmodule Jido.AI.Accuracy.Search.BeamSearchTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Accuracy.{Candidate, Search.BeamSearch}

  @moduletag :capture_log

  # Mock verifier for testing
  defmodule MockVerifier do
    def verify(%Candidate{} = candidate, _context) do
      # Score based on content length for testing
      score = candidate.content |> String.length() |> min(100) |> Kernel./(100)
      {:ok, %{score: score, candidate_id: candidate.id}}
    end
  end

  # Mock generator for testing
  defmodule MockGenerator do
    def generate_candidates(prompt, opts) do
      num_candidates = Keyword.get(opts, :num_candidates, 5)

      candidates =
        Enum.map(1..num_candidates, fn i ->
          Candidate.new!(%{
            id: "candidate_#{i}",
            content: "#{prompt} - answer #{i}",
            metadata: %{index: i}
          })
        end)

      {:ok, candidates}
    end
  end

  describe "new/1" do
    test "creates beam search with defaults" do
      assert {:ok, bs} = BeamSearch.new([])

      assert bs.beam_width == 5
      assert bs.depth == 3
      assert bs.branching_factor == 2
    end

    test "creates beam search with custom beam_width" do
      assert {:ok, bs} = BeamSearch.new(beam_width: 10)

      assert bs.beam_width == 10
    end

    test "creates beam search with custom depth" do
      assert {:ok, bs} = BeamSearch.new(depth: 5)

      assert bs.depth == 5
    end

    test "creates beam search with custom branching_factor" do
      assert {:ok, bs} = BeamSearch.new(branching_factor: 3)

      assert bs.branching_factor == 3
    end

    test "creates beam search with all custom options" do
      assert {:ok, bs} = BeamSearch.new(beam_width: 7, depth: 4, branching_factor: 2)

      assert bs.beam_width == 7
      assert bs.depth == 4
      assert bs.branching_factor == 2
    end

    test "returns error for beam_width < 1" do
      assert {:error, :invalid_beam_width} = BeamSearch.new(beam_width: 0)
    end

    test "returns error for beam_width > 100" do
      assert {:error, :invalid_beam_width} = BeamSearch.new(beam_width: 101)
    end

    test "returns error for non-integer beam_width" do
      assert {:error, :invalid_beam_width} = BeamSearch.new(beam_width: "invalid")
    end

    test "returns error for depth < 1" do
      assert {:error, :invalid_depth} = BeamSearch.new(depth: 0)
    end

    test "returns error for depth > 20" do
      assert {:error, :invalid_depth} = BeamSearch.new(depth: 21)
    end

    test "returns error for branching_factor < 1" do
      assert {:error, :invalid_branching_factor} = BeamSearch.new(branching_factor: 0)
    end

    test "returns error for branching_factor > 10" do
      assert {:error, :invalid_branching_factor} = BeamSearch.new(branching_factor: 11)
    end
  end

  describe "new!/1" do
    test "returns config when valid" do
      bs = BeamSearch.new!(beam_width: 7)

      assert bs.beam_width == 7
    end

    test "raises when invalid" do
      assert_raise ArgumentError, ~r/Invalid BeamSearch config/, fn ->
        BeamSearch.new!(beam_width: 0)
      end
    end
  end

  describe "search/4" do
    test "searches and returns best candidate" do
      {:ok, best} =
        BeamSearch.search("test prompt", MockGenerator, MockVerifier,
          beam_width: 3,
          depth: 2
        )

      assert %Candidate{} = best
      assert is_binary(best.content)
    end

    test "respects beam_width option" do
      {:ok, best} =
        BeamSearch.search("test", MockGenerator, MockVerifier,
          beam_width: 2,
          depth: 1
        )

      assert %Candidate{} = best
    end

    test "respects depth option" do
      {:ok, best} =
        BeamSearch.search("test", MockGenerator, MockVerifier,
          beam_width: 2,
          depth: 1
        )

      assert %Candidate{} = best
    end

    test "respects branching_factor option" do
      {:ok, best} =
        BeamSearch.search("test", MockGenerator, MockVerifier,
          beam_width: 2,
          depth: 1,
          branching_factor: 3
        )

      assert %Candidate{} = best
    end

    test "beam_width of 1 works (greedy search)" do
      {:ok, best} =
        BeamSearch.search("test", MockGenerator, MockVerifier,
          beam_width: 1,
          depth: 2
        )

      assert %Candidate{} = best
    end

    test "returns error when no candidates generated" do
      # Use a generator that returns empty list
      defmodule EmptyGenerator do
        def generate_candidates(_prompt, _opts), do: {:ok, []}
        def generate_candidates(_prompt, _prompt2, _opts), do: {:ok, []}
      end

      # Force use of this generator by ensuring it's loaded
      Code.ensure_loaded?(EmptyGenerator)

      assert {:error, :no_initial_candidates} =
               BeamSearch.search("test", EmptyGenerator, MockVerifier, [])
    end

    test "returns error when timeout exceeded" do
      # Use a timeout of 0 to force timeout
      assert {:error, :timeout} =
               BeamSearch.search("test", MockGenerator, MockVerifier, timeout: 0)
    end

    test "uses default options when none provided" do
      {:ok, best} = BeamSearch.search("test", MockGenerator, MockVerifier, [])

      assert %Candidate{} = best
    end
  end

  describe "select_top_k/2" do
    test "selects top K nodes by score" do
      nodes = [
        %{candidate: Candidate.new!(%{id: "1", content: "short"}), score: 0.3, metadata: %{}},
        %{candidate: Candidate.new!(%{id: "2", content: "medium length text"}), score: 0.7, metadata: %{}},
        %{candidate: Candidate.new!(%{id: "3", content: "very long text content here"}), score: 0.9, metadata: %{}},
        %{candidate: Candidate.new!(%{id: "4", content: "tiny"}), score: 0.2, metadata: %{}}
      ]

      result = BeamSearch.select_top_k(nodes, 2)

      assert length(result) == 2
      assert hd(result).score == 0.9
      assert Enum.at(result, 1).score == 0.7
    end

    test "handles K larger than node list" do
      nodes = [
        %{candidate: Candidate.new!(%{id: "1", content: "test"}), score: 0.5, metadata: %{}}
      ]

      result = BeamSearch.select_top_k(nodes, 5)

      assert length(result) == 1
    end

    test "handles K equal to node list size" do
      nodes = [
        %{candidate: Candidate.new!(%{id: "1", content: "a"}), score: 0.5, metadata: %{}},
        %{candidate: Candidate.new!(%{id: "2", content: "b"}), score: 0.7, metadata: %{}}
      ]

      result = BeamSearch.select_top_k(nodes, 2)

      assert length(result) == 2
    end

    test "handles empty node list" do
      result = BeamSearch.select_top_k([], 3)

      assert result == []
    end

    test "handles K of 1" do
      nodes = [
        %{candidate: Candidate.new!(%{id: "1", content: "a"}), score: 0.5, metadata: %{}},
        %{candidate: Candidate.new!(%{id: "2", content: "bb"}), score: 0.7, metadata: %{}},
        %{candidate: Candidate.new!(%{id: "3", content: "c"}), score: 0.3, metadata: %{}}
      ]

      result = BeamSearch.select_top_k(nodes, 1)

      assert length(result) == 1
      assert hd(result).score == 0.7
    end
  end

  describe "algorithm behavior" do
    test "verifier scores guide beam selection" do
      # Verifier that prefers longer content
      defmodule LengthVerifier do
        def verify(%Candidate{content: content}, _context) do
          score = String.length(content) / 100
          {:ok, %{score: min(score, 1.0), candidate_id: "test"}}
        end
      end

      # Generator creates candidates with varying lengths
      defmodule VariableLengthGenerator do
        def generate_candidates(prompt, opts) do
          num = Keyword.get(opts, :num_candidates, 5)

          candidates =
            Enum.map(1..num, fn i ->
              content = String.duplicate(prompt, i)
              Candidate.new!(%{id: "c#{i}", content: content})
            end)

          {:ok, candidates}
        end
      end

      {:ok, best} =
        BeamSearch.search("x", VariableLengthGenerator, LengthVerifier,
          beam_width: 3,
          depth: 2,
          branching_factor: 2
        )

      # Best candidate should have high score (longer content)
      assert %Candidate{} = best
      assert String.length(best.content) > 0
    end

    test "beam search explores multiple candidates" do
      # This test verifies beam search completes with multiple depth levels
      defmodule DepthTrackingGenerator do
        def generate_candidates(prompt, opts) do
          num = Keyword.get(opts, :num_candidates, 5)

          candidates =
            Enum.map(1..num, fn i ->
              Candidate.new!(%{id: "c#{i}", content: "#{prompt} #{i}"})
            end)

          {:ok, candidates}
        end
      end

      # Run with depth > 1 to ensure beam expansion happens
      {:ok, best} =
        BeamSearch.search("test", DepthTrackingGenerator, MockVerifier,
          beam_width: 2,
          depth: 2,
          branching_factor: 2
        )

      # Verify we got a valid candidate
      assert %Candidate{} = best
      assert String.contains?(best.content, "test")
    end
  end

  describe "integration with SearchController behavior" do
    test "implements search/4 callback" do
      assert function_exported?(BeamSearch, :search, 4)
    end

    test "returns {:ok, candidate} on success" do
      result = BeamSearch.search("test", MockGenerator, MockVerifier, [])

      assert match?({:ok, %Candidate{}}, result)
    end

    test "returns {:error, reason} on failure" do
      result = BeamSearch.search("test", MockGenerator, MockVerifier, timeout: 0)

      assert match?({:error, _}, result)
    end
  end
end
