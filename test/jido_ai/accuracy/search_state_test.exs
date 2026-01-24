defmodule Jido.AI.Accuracy.SearchStateTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Accuracy.{Candidate, SearchState}

  @moduletag :capture_log

  describe "new/1" do
    test "creates state with default values" do
      assert {:ok, state} = SearchState.new(budget_remaining: 100)

      assert state.nodes == []
      assert state.best_node == nil
      assert state.iterations == 0
      assert state.budget_remaining == 100
      assert state.converged == false
      assert state.metadata == %{}
      assert state.stagnation_count == 0
      assert is_integer(state.start_time)
    end

    test "creates state with custom nodes" do
      candidate = Candidate.new!(%{id: "1", content: "test"})
      node = %{candidate: candidate, score: 0.8, metadata: %{}}

      assert {:ok, state} = SearchState.new(budget_remaining: 100, nodes: [node])

      assert length(state.nodes) == 1
    end

    test "creates state with custom best_node" do
      candidate = Candidate.new!(%{id: "1", content: "test"})
      node = %{candidate: candidate, score: 0.9, metadata: %{}}

      assert {:ok, state} = SearchState.new(budget_remaining: 100, best_node: node)

      assert state.best_node.score == 0.9
    end

    test "creates state with custom iterations" do
      assert {:ok, state} = SearchState.new(budget_remaining: 100, iterations: 5)

      assert state.iterations == 5
    end

    test "creates state with custom metadata" do
      assert {:ok, state} = SearchState.new(budget_remaining: 100, metadata: %{max_iterations: 10})

      assert state.metadata.max_iterations == 10
    end

    test "creates state with stagnation_count" do
      assert {:ok, state} = SearchState.new(budget_remaining: 100, stagnation_count: 3)

      assert state.stagnation_count == 3
    end

    test "returns error for negative budget" do
      assert {:error, :invalid_budget} = SearchState.new(budget_remaining: -1)
    end

    test "returns error for non-integer budget" do
      assert {:error, :invalid_budget} = SearchState.new(budget_remaining: "invalid")
    end

    test "returns error for negative iterations" do
      assert {:error, :invalid_iterations} = SearchState.new(budget_remaining: 100, iterations: -1)
    end

    test "returns error for non-integer iterations" do
      assert {:error, :invalid_iterations} = SearchState.new(budget_remaining: 100, iterations: "invalid")
    end

    test "requires budget_remaining" do
      assert {:error, :missing_budget_remaining} = SearchState.new([])
    end
  end

  describe "new!/1" do
    test "returns state when valid" do
      state = SearchState.new!(budget_remaining: 100)

      assert state.budget_remaining == 100
    end

    test "raises when invalid" do
      assert_raise ArgumentError, ~r/Invalid SearchState/, fn ->
        SearchState.new!(budget_remaining: -1)
      end
    end
  end

  describe "update_best/4" do
    setup do
      {:ok, state} = SearchState.new(budget_remaining: 100)
      candidate1 = Candidate.new!(%{id: "1", content: "answer 1"})
      candidate2 = Candidate.new!(%{id: "2", content: "answer 2"})

      {:ok, state: state, candidate1: candidate1, candidate2: candidate2}
    end

    test "updates best_node when score is higher", %{state: state, candidate1: candidate1} do
      updated = SearchState.update_best(state, candidate1, 0.9)

      assert updated.best_node.score == 0.9
      assert updated.best_node.candidate.id == "1"
      assert updated.stagnation_count == 0
    end

    test "preserves best_node when score is lower", %{state: state, candidate1: candidate1, candidate2: candidate2} do
      state = SearchState.update_best(state, candidate1, 0.9)
      updated = SearchState.update_best(state, candidate2, 0.5)

      assert updated.best_node.score == 0.9
      assert updated.best_node.candidate.id == "1"
      assert updated.stagnation_count == 1
    end

    test "stores metadata with node", %{state: state, candidate1: candidate1} do
      updated = SearchState.update_best(state, candidate1, 0.8, %{source: :beam_search})

      assert updated.best_node.metadata.source == :beam_search
    end

    test "resets stagnation_count when new best is found", %{
      state: state,
      candidate1: candidate1,
      candidate2: candidate2
    } do
      state = SearchState.update_best(state, candidate1, 0.7)
      assert state.stagnation_count == 0

      state = SearchState.update_best(state, candidate2, 0.5)
      assert state.stagnation_count == 1

      state = SearchState.update_best(state, candidate1, 0.9)
      assert state.stagnation_count == 0
    end
  end

  describe "update_best_node/2" do
    setup do
      {:ok, state} = SearchState.new(budget_remaining: 100)
      candidate = Candidate.new!(%{id: "1", content: "answer"})
      node = %{candidate: candidate, score: 0.8, metadata: %{}}

      {:ok, state: state, node: node}
    end

    test "updates when node has higher score", %{state: state, node: node} do
      updated = SearchState.update_best_node(state, node)

      assert updated.best_node.score == 0.8
    end

    test "increments stagnation when node has lower score", %{state: state, node: node} do
      state = SearchState.update_best_node(state, %{node | score: 0.9})

      lower_node = %{node | score: 0.5}
      updated = SearchState.update_best_node(state, lower_node)

      assert updated.best_node.score == 0.9
      assert updated.stagnation_count == 1
    end
  end

  describe "should_stop?/1" do
    test "returns true when budget exhausted" do
      state = SearchState.new!(budget_remaining: 0)

      assert SearchState.should_stop?(state) == true
    end

    test "returns true when converged" do
      state = SearchState.new!(budget_remaining: 100) |> SearchState.converge()

      assert SearchState.should_stop?(state) == true
    end

    test "returns true when max iterations reached" do
      state = SearchState.new!(budget_remaining: 100, metadata: %{max_iterations: 10}, iterations: 10)

      assert SearchState.should_stop?(state) == true
    end

    test "returns false when conditions not met" do
      state = SearchState.new!(budget_remaining: 100)

      assert SearchState.should_stop?(state) == false
    end

    test "returns false when iterations below max" do
      state = SearchState.new!(budget_remaining: 100, metadata: %{max_iterations: 10}, iterations: 5)

      assert SearchState.should_stop?(state) == false
    end
  end

  describe "budget_exhausted?/1" do
    test "returns true when budget is 0" do
      state = SearchState.new!(budget_remaining: 0)

      assert SearchState.budget_exhausted?(state) == true
    end

    test "returns false when budget > 0" do
      state = SearchState.new!(budget_remaining: 10)

      assert SearchState.budget_exhausted?(state) == false
    end
  end

  describe "max_iterations_reached?/1" do
    test "returns true when iterations >= max" do
      state = SearchState.new!(budget_remaining: 100, metadata: %{max_iterations: 10}, iterations: 10)

      assert SearchState.max_iterations_reached?(state) == true
    end

    test "returns true when iterations > max" do
      state = SearchState.new!(budget_remaining: 100, metadata: %{max_iterations: 10}, iterations: 15)

      assert SearchState.max_iterations_reached?(state) == true
    end

    test "returns false when iterations < max" do
      state = SearchState.new!(budget_remaining: 100, metadata: %{max_iterations: 10}, iterations: 5)

      assert SearchState.max_iterations_reached?(state) == false
    end

    test "returns false when no max_iterations set" do
      state = SearchState.new!(budget_remaining: 100, iterations: 100)

      assert SearchState.max_iterations_reached?(state) == false
    end
  end

  describe "stagnated?/2" do
    test "returns true when stagnation_count >= threshold" do
      state = SearchState.new!(budget_remaining: 100, stagnation_count: 5)

      assert SearchState.stagnated?(state, 5) == true
    end

    test "returns true when stagnation_count > threshold" do
      state = SearchState.new!(budget_remaining: 100, stagnation_count: 10)

      assert SearchState.stagnated?(state, 5) == true
    end

    test "returns false when stagnation_count < threshold" do
      state = SearchState.new!(budget_remaining: 100, stagnation_count: 3)

      assert SearchState.stagnated?(state, 5) == false
    end
  end

  describe "add_node/2" do
    test "adds node to state" do
      state = SearchState.new!(budget_remaining: 100)
      candidate = Candidate.new!(%{id: "1", content: "test"})
      node = %{candidate: candidate, score: 0.8, metadata: %{}}

      updated = SearchState.add_node(state, node)

      assert length(updated.nodes) == 1
    end

    test "prepends node to list" do
      state = SearchState.new!(budget_remaining: 100)
      candidate1 = Candidate.new!(%{id: "1", content: "first"})
      candidate2 = Candidate.new!(%{id: "2", content: "second"})
      node1 = %{candidate: candidate1, score: 0.8, metadata: %{}}
      node2 = %{candidate: candidate2, score: 0.9, metadata: %{}}

      state = SearchState.add_node(state, node1)
      state = SearchState.add_node(state, node2)

      assert hd(state.nodes).candidate.id == "2"
    end
  end

  describe "add_nodes/2" do
    test "adds multiple nodes to state" do
      state = SearchState.new!(budget_remaining: 100)
      candidate1 = Candidate.new!(%{id: "1", content: "test1"})
      candidate2 = Candidate.new!(%{id: "2", content: "test2"})
      node1 = %{candidate: candidate1, score: 0.8, metadata: %{}}
      node2 = %{candidate: candidate2, score: 0.9, metadata: %{}}

      updated = SearchState.add_nodes(state, [node1, node2])

      assert length(updated.nodes) == 2
    end
  end

  describe "set_nodes/2" do
    test "replaces nodes in state" do
      state = SearchState.new!(budget_remaining: 100)
      candidate = Candidate.new!(%{id: "1", content: "test"})
      node = %{candidate: candidate, score: 0.8, metadata: %{}}

      updated = SearchState.set_nodes(state, [node])

      assert length(updated.nodes) == 1
    end

    test "clears nodes when empty list" do
      candidate = Candidate.new!(%{id: "1", content: "test"})
      node = %{candidate: candidate, score: 0.8, metadata: %{}}
      state = SearchState.new!(budget_remaining: 100, nodes: [node])

      updated = SearchState.set_nodes(state, [])

      assert updated.nodes == []
    end
  end

  describe "decrement_budget/2" do
    test "reduces budget by amount" do
      state = SearchState.new!(budget_remaining: 100)

      updated = SearchState.decrement_budget(state, 10)

      assert updated.budget_remaining == 90
    end

    test "clamps budget to 0" do
      state = SearchState.new!(budget_remaining: 5)

      updated = SearchState.decrement_budget(state, 10)

      assert updated.budget_remaining == 0
    end

    test "allows decrement of 1" do
      state = SearchState.new!(budget_remaining: 100)

      updated = SearchState.decrement_budget(state, 1)

      assert updated.budget_remaining == 99
    end
  end

  describe "increment_iteration/1" do
    test "increments iteration counter" do
      state = SearchState.new!(budget_remaining: 100)

      updated = SearchState.increment_iteration(state)

      assert updated.iterations == 1

      updated = SearchState.increment_iteration(updated)

      assert updated.iterations == 2
    end
  end

  describe "converge/1" do
    test "marks state as converged" do
      state = SearchState.new!(budget_remaining: 100)

      updated = SearchState.converge(state)

      assert updated.converged == true
    end
  end

  describe "get_best_candidate/1" do
    test "returns candidate when best_node exists" do
      candidate = Candidate.new!(%{id: "1", content: "test"})
      node = %{candidate: candidate, score: 0.9, metadata: %{}}
      state = SearchState.new!(budget_remaining: 100, best_node: node)

      result = SearchState.get_best_candidate(state)

      assert result.id == "1"
    end

    test "returns nil when no best_node" do
      state = SearchState.new!(budget_remaining: 100)

      assert SearchState.get_best_candidate(state) == nil
    end
  end

  describe "get_best_score/1" do
    test "returns score when best_node exists" do
      candidate = Candidate.new!(%{id: "1", content: "test"})
      node = %{candidate: candidate, score: 0.9, metadata: %{}}
      state = SearchState.new!(budget_remaining: 100, best_node: node)

      assert SearchState.get_best_score(state) == 0.9
    end

    test "returns 0.0 when no best_node" do
      state = SearchState.new!(budget_remaining: 100)

      assert SearchState.get_best_score(state) == 0.0
    end
  end

  describe "elapsed_ms/1" do
    test "returns elapsed time" do
      state = SearchState.new!(budget_remaining: 100)

      elapsed = SearchState.elapsed_ms(state)

      assert elapsed >= 0
      assert elapsed < 100
    end

    test "increases over time" do
      state = SearchState.new!(budget_remaining: 100)

      elapsed1 = SearchState.elapsed_ms(state)
      Process.sleep(10)
      elapsed2 = SearchState.elapsed_ms(state)

      assert elapsed2 >= elapsed1
    end
  end

  describe "put_metadata/3" do
    test "puts value in metadata" do
      state = SearchState.new!(budget_remaining: 100)

      updated = SearchState.put_metadata(state, :key, "value")

      assert updated.metadata.key == "value"
    end

    test "overwrites existing value" do
      state = SearchState.new!(budget_remaining: 100, metadata: %{key: "old"})

      updated = SearchState.put_metadata(state, :key, "new")

      assert updated.metadata.key == "new"
    end
  end

  describe "get_metadata/3" do
    test "gets value from metadata" do
      state = SearchState.new!(budget_remaining: 100, metadata: %{key: "value"})

      assert SearchState.get_metadata(state, :key) == "value"
    end

    test "returns default when key not found" do
      state = SearchState.new!(budget_remaining: 100)

      assert SearchState.get_metadata(state, :missing) == nil
      assert SearchState.get_metadata(state, :missing, "default") == "default"
    end

    test "uses custom default" do
      state = SearchState.new!(budget_remaining: 100)

      assert SearchState.get_metadata(state, :missing, 42) == 42
    end
  end
end
