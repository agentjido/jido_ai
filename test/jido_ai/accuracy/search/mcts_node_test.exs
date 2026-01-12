defmodule Jido.AI.Accuracy.Search.MCTSNodeTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Accuracy.{Candidate, Search.MCTSNode}

  @moduletag :capture_log

  describe "new/1" do
    test "creates node with defaults" do
      node = MCTSNode.new()

      assert node.state == nil
      assert node.visits == 0
      assert node.value == 0.0
      assert node.children == []
      assert node.parent == nil
      assert node.is_terminal == false
      assert node.candidate == nil
      assert node.action == nil
    end

    test "creates node with custom state" do
      node = MCTSNode.new(state: "test_state")

      assert node.state == "test_state"
    end

    test "creates node with custom visits and value" do
      node = MCTSNode.new(visits: 5, value: 3.5)

      assert node.visits == 5
      assert node.value == 3.5
    end

    test "creates node with children" do
      child = MCTSNode.new(state: "child")
      node = MCTSNode.new(children: [child])

      assert length(node.children) == 1
    end

    test "creates terminal node" do
      node = MCTSNode.new(is_terminal: true)

      assert node.is_terminal == true
    end

    test "creates node with candidate" do
      candidate = Candidate.new!(%{id: "1", content: "test"})
      node = MCTSNode.new(candidate: candidate)

      assert node.candidate.id == "1"
    end
  end

  describe "ucb1_score/2" do
    test "returns infinity for unvisited nodes" do
      node = MCTSNode.new(visits: 0, value: 0.0)

      assert MCTSNode.ucb1_score(node, 1.414) == :infinity
    end

    test "calculates score for visited nodes" do
      node = MCTSNode.new(visits: 10, value: 5.0)

      score = MCTSNode.ucb1_score(node, 1.414)

      assert is_number(score)
      assert score > 0
    end

    test "higher value gives higher score" do
      node1 = MCTSNode.new(visits: 10, value: 8.0)
      node2 = MCTSNode.new(visits: 10, value: 3.0)

      score1 = MCTSNode.ucb1_score(node1, 1.0)
      score2 = MCTSNode.ucb1_score(node2, 1.0)

      assert score1 > score2
    end

    test "higher visits reduces exploration bonus" do
      node1 = MCTSNode.new(visits: 5, value: 2.5)
      node2 = MCTSNode.new(visits: 20, value: 10.0)

      score1 = MCTSNode.ucb1_score(node1, 1.414)
      score2 = MCTSNode.ucb1_score(node2, 1.414)

      # node2 has higher visits so less exploration bonus
      assert score1 > score2
    end
  end

  describe "ucb1_score_for_child/2" do
    test "returns infinity for unvisited children" do
      parent = MCTSNode.new(visits: 10)
      child = MCTSNode.new(visits: 0, parent: parent)

      assert MCTSNode.ucb1_score_for_child(child, 1.414) == :infinity
    end

    test "calculates score with parent visits" do
      parent = MCTSNode.new(visits: 20)
      child = MCTSNode.new(visits: 5, value: 3.0, parent: parent)

      score = MCTSNode.ucb1_score_for_child(child, 1.414)

      assert is_number(score)
      assert score > 0
    end

    test "handles child with no parent" do
      child = MCTSNode.new(visits: 5, value: 3.0, parent: nil)

      score = MCTSNode.ucb1_score_for_child(child, 1.414)

      assert is_number(score)
    end
  end

  describe "add_child/2" do
    test "adds child from keyword list" do
      parent = MCTSNode.new(state: "parent")

      updated = MCTSNode.add_child(parent, state: "child")

      assert length(updated.children) == 1
      assert hd(updated.children).state == "child"
    end

    test "sets parent reference on child" do
      parent = MCTSNode.new(state: "parent")
      child = MCTSNode.new(state: "child")

      updated = MCTSNode.add_child(parent, child)

      added_child = hd(updated.children)
      assert added_child.parent == parent
    end

    test "adds multiple children" do
      parent = MCTSNode.new(state: "parent")

      updated =
        parent
        |> MCTSNode.add_child(state: "child1")
        |> MCTSNode.add_child(state: "child2")

      assert length(updated.children) == 2
    end
  end

  describe "update_value/2" do
    test "accumulates value" do
      node = MCTSNode.new(value: 2.0)

      updated = MCTSNode.update_value(node, 1.5)

      assert_in_delta updated.value, 3.5, 0.01
    end

    test "handles negative values" do
      node = MCTSNode.new(value: 2.0)

      updated = MCTSNode.update_value(node, -0.5)

      assert_in_delta updated.value, 1.5, 0.01
    end
  end

  describe "increment_visits/1" do
    test "increments visit count" do
      node = MCTSNode.new(visits: 0)

      updated = MCTSNode.increment_visits(node)
      updated = MCTSNode.increment_visits(updated)

      assert updated.visits == 2
    end
  end

  describe "backpropagate/2" do
    test "updates both visits and value" do
      node = MCTSNode.new(visits: 5, value: 2.5)

      updated = MCTSNode.backpropagate(node, 0.8)

      assert updated.visits == 6
      assert_in_delta updated.value, 3.3, 0.01
    end

    test "handles initial backpropagation" do
      node = MCTSNode.new(visits: 0, value: 0.0)

      updated = MCTSNode.backpropagate(node, 1.0)

      assert updated.visits == 1
      assert_in_delta updated.value, 1.0, 0.01
    end
  end

  describe "is_fully_expanded?/1" do
    test "returns false for nodes without children" do
      node = MCTSNode.new()

      refute MCTSNode.is_fully_expanded?(node)
    end

    test "returns true for nodes with children" do
      child = MCTSNode.new(state: "child")
      node = MCTSNode.new(children: [child])

      assert MCTSNode.is_fully_expanded?(node)
    end
  end

  describe "is_terminal?/1" do
    test "returns is_terminal flag value" do
      node = MCTSNode.new(is_terminal: true)

      assert MCTSNode.is_terminal?(node)
    end

    test "returns false for non-terminal nodes" do
      node = MCTSNode.new(is_terminal: false)

      refute MCTSNode.is_terminal?(node)
    end
  end

  describe "mark_terminal/1" do
    test "marks node as terminal" do
      node = MCTSNode.new()

      updated = MCTSNode.mark_terminal(node)

      assert updated.is_terminal == true
    end
  end

  describe "best_child/2" do
    test "returns nil for nodes without children" do
      node = MCTSNode.new()

      assert MCTSNode.best_child(node, []) == nil
    end

    test "returns child with highest value/visits ratio" do
      child1 = MCTSNode.new(visits: 10, value: 5.0)
      child2 = MCTSNode.new(visits: 5, value: 4.0)

      # child1 ratio: 0.5, child2 ratio: 0.8
      node = MCTSNode.new(children: [child1, child2])

      best = MCTSNode.best_child(node, [])

      assert best == child2
    end

    test "handles unvisited children" do
      child1 = MCTSNode.new(visits: 10, value: 5.0)
      child2 = MCTSNode.new(visits: 0, value: 0.0)

      node = MCTSNode.new(children: [child1, child2])

      best = MCTSNode.best_child(node, [])

      # child1 has ratio 0.5, child2 has ratio 0.0
      assert best == child1
    end

    test "respects temperature for randomness" do
      # Set a seed for reproducibility
      :rand.seed(:exsss, {42, 42, 42})

      child1 = MCTSNode.new(visits: 10, value: 5.0)
      child2 = MCTSNode.new(visits: 5, value: 4.0)

      node = MCTSNode.new(children: [child1, child2])

      # With high temperature, should introduce randomness
      best = MCTSNode.best_child(node, temperature: 1.0)

      assert best in [child1, child2]
    end
  end

  describe "most_visited_child/1" do
    test "returns nil for nodes without children" do
      node = MCTSNode.new()

      assert MCTSNode.most_visited_child(node) == nil
    end

    test "returns most visited child" do
      child1 = MCTSNode.new(visits: 3)
      child2 = MCTSNode.new(visits: 7)
      child3 = MCTSNode.new(visits: 5)

      node = MCTSNode.new(children: [child1, child2, child3])

      best = MCTSNode.most_visited_child(node)

      assert best.visits == 7
    end
  end

  describe "average_value/1" do
    test "returns 0.0 for unvisited nodes" do
      node = MCTSNode.new(visits: 0, value: 0.0)

      assert MCTSNode.average_value(node) == 0.0
    end

    test "returns value divided by visits" do
      node = MCTSNode.new(visits: 10, value: 5.0)

      assert MCTSNode.average_value(node) == 0.5
    end

    test "handles decimal values" do
      node = MCTSNode.new(visits: 3, value: 2.0)

      assert_in_delta MCTSNode.average_value(node), 0.667, 0.01
    end
  end

  describe "find_child_by_action/2" do
    test "returns child matching action" do
      child1 = MCTSNode.new(action: :action_a)
      child2 = MCTSNode.new(action: :action_b)

      node = MCTSNode.new(children: [child1, child2])

      result = MCTSNode.find_child_by_action(node, :action_b)

      assert result.action == :action_b
    end

    test "returns nil when no child matches" do
      child = MCTSNode.new(action: :action_a)
      node = MCTSNode.new(children: [child])

      assert MCTSNode.find_child_by_action(node, :action_b) == nil
    end

    test "returns nil for nodes without children" do
      node = MCTSNode.new()

      assert MCTSNode.find_child_by_action(node, :any) == nil
    end
  end

  describe "child_count/1" do
    test "returns 0 for nodes without children" do
      node = MCTSNode.new()

      assert MCTSNode.child_count(node) == 0
    end

    test "returns number of children" do
      child1 = MCTSNode.new()
      child2 = MCTSNode.new()
      child3 = MCTSNode.new()

      node = MCTSNode.new(children: [child1, child2, child3])

      assert MCTSNode.child_count(node) == 3
    end
  end

  describe "has_children?/1" do
    test "returns false for nodes without children" do
      node = MCTSNode.new()

      refute MCTSNode.has_children?(node)
    end

    test "returns true for nodes with children" do
      child = MCTSNode.new()
      node = MCTSNode.new(children: [child])

      assert MCTSNode.has_children?(node)
    end
  end

  describe "depth/1" do
    test "returns 0 for root node" do
      node = MCTSNode.new()

      assert MCTSNode.depth(node) == 0
    end

    test "returns 1 for direct child" do
      parent = MCTSNode.new()
      child = MCTSNode.new(parent: parent)

      assert MCTSNode.depth(child) == 1
    end

    test "calculates depth for nested children" do
      root = MCTSNode.new()
      child = MCTSNode.new(parent: root)
      grandchild = MCTSNode.new(parent: child)

      assert MCTSNode.depth(grandchild) == 2
    end
  end
end
