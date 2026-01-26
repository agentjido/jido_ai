defmodule Jido.AI.Accuracy.Search.MCTSTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Accuracy.{Candidate, Search.MCTS, Search.MCTSNode}

  @moduletag :capture_log

  # Mock verifier for testing
  defmodule MockVerifier do
    def verify(%Candidate{} = candidate, _context) do
      # Score based on content length
      score = candidate.content |> String.length() |> min(100) |> Kernel./(100)
      {:ok, %{score: score, candidate_id: candidate.id}}
    end
  end

  # Mock generator for testing
  defmodule MockGenerator do
    def generate_candidates(prompt, opts) do
      num = Keyword.get(opts, :num_candidates, 1)

      candidates =
        Enum.map(1..num, fn i ->
          Candidate.new!(%{
            id: "candidate_#{i}",
            content: String.duplicate(prompt, i),
            metadata: %{index: i}
          })
        end)

      {:ok, candidates}
    end
  end

  describe "new/1" do
    test "creates MCTS with defaults" do
      assert {:ok, mcts} = MCTS.new([])

      assert mcts.simulations == 100
      assert mcts.exploration_constant == 1.414
      assert mcts.max_depth == 10
    end

    test "creates MCTS with custom simulations" do
      assert {:ok, mcts} = MCTS.new(simulations: 200)

      assert mcts.simulations == 200
    end

    test "creates MCTS with custom exploration_constant" do
      assert {:ok, mcts} = MCTS.new(exploration_constant: 2.0)

      assert mcts.exploration_constant == 2.0
    end

    test "creates MCTS with custom max_depth" do
      assert {:ok, mcts} = MCTS.new(max_depth: 5)

      assert mcts.max_depth == 5
    end

    test "returns error for simulations < 1" do
      assert {:error, :invalid_simulations} = MCTS.new(simulations: 0)
    end

    test "returns error for simulations > 10_000" do
      assert {:error, :invalid_simulations} = MCTS.new(simulations: 10_001)
    end

    test "returns error for negative exploration_constant" do
      assert {:error, :invalid_exploration_constant} = MCTS.new(exploration_constant: -1.0)
    end

    test "returns error for exploration_constant > 10" do
      assert {:error, :invalid_exploration_constant} = MCTS.new(exploration_constant: 11.0)
    end

    test "returns error for max_depth < 1" do
      assert {:error, :invalid_max_depth} = MCTS.new(max_depth: 0)
    end

    test "returns error for max_depth > 100" do
      assert {:error, :invalid_max_depth} = MCTS.new(max_depth: 101)
    end
  end

  describe "new!/1" do
    test "returns config when valid" do
      mcts = MCTS.new!(simulations: 50)

      assert mcts.simulations == 50
    end

    test "raises when invalid" do
      assert_raise ArgumentError, ~r/Invalid MCTS config/, fn ->
        MCTS.new!(simulations: 0)
      end
    end
  end

  describe "search/4" do
    test "searches and returns best candidate" do
      {:ok, best} = MCTS.search("test", MockGenerator, MockVerifier, simulations: 10)

      assert %Candidate{} = best
      assert is_binary(best.content)
    end

    test "respects simulations option" do
      {:ok, best} = MCTS.search("test", MockGenerator, MockVerifier, simulations: 5)

      assert %Candidate{} = best
    end

    test "respects exploration_constant option" do
      {:ok, best} =
        MCTS.search("test", MockGenerator, MockVerifier,
          simulations: 10,
          exploration_constant: 1.0
        )

      assert %Candidate{} = best
    end

    test "respects max_depth option" do
      {:ok, best} =
        MCTS.search("test", MockGenerator, MockVerifier,
          simulations: 10,
          max_depth: 3
        )

      assert %Candidate{} = best
    end

    test "returns error when no candidates can be generated" do
      defmodule FailingGenerator do
        def generate_candidates(_prompt, _opts), do: {:ok, []}
        def generate_candidates(_prompt, _prompt2, _opts), do: {:ok, []}
      end

      assert {:error, :no_valid_candidate} =
               MCTS.search("test", FailingGenerator, MockVerifier, simulations: 5)
    end

    test "returns error when timeout exceeded" do
      assert {:error, :no_valid_candidate} =
               MCTS.search("test", MockGenerator, MockVerifier, timeout: 0, simulations: 10)
    end
  end

  describe "algorithm behavior" do
    test "completes search with single simulation" do
      {:ok, best} = MCTS.search("test", MockGenerator, MockVerifier, simulations: 1)

      assert %Candidate{} = best
    end

    test "explorer constant affects search (smoke test)" do
      # Just verify it doesn't crash with different constants
      {:ok, _best} =
        MCTS.search("test", MockGenerator, MockVerifier,
          simulations: 5,
          exploration_constant: 0.5
        )

      {:ok, _best} =
        MCTS.search("test", MockGenerator, MockVerifier,
          simulations: 5,
          exploration_constant: 2.0
        )
    end

    test "max_depth limits tree depth (smoke test)" do
      {:ok, best} =
        MCTS.search("test", MockGenerator, MockVerifier,
          simulations: 10,
          max_depth: 2
        )

      assert %Candidate{} = best
    end
  end

  describe "integration with SearchController behavior" do
    test "implements search/4 callback" do
      # Ensure module is fully loaded before checking function_exported?
      Code.ensure_loaded!(MCTS)
      assert function_exported?(MCTS, :search, 4)
    end

    test "returns {:ok, candidate} on success" do
      result = MCTS.search("test", MockGenerator, MockVerifier, simulations: 5)

      assert match?({:ok, %Candidate{}}, result)
    end

    test "returns {:error, reason} on failure" do
      result = MCTS.search("test", MockGenerator, MockVerifier, timeout: 0, simulations: 5)

      assert match?({:error, _}, result)
    end
  end

  describe "MCTSNode integration" do
    test "uses MCTSNode for tree structure" do
      root = MCTSNode.new(state: %{prompt: "test", depth: 0})

      assert root.state.prompt == "test"
      assert root.state.depth == 0
    end

    test "node depth calculation works correctly" do
      root = MCTSNode.new()
      child = MCTSNode.new(parent: root)
      grandchild = MCTSNode.new(parent: child)

      assert MCTSNode.depth(root) == 0
      assert MCTSNode.depth(child) == 1
      assert MCTSNode.depth(grandchild) == 2
    end
  end
end
