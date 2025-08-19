defmodule Jido.BehaviorTreeTest do
  use ExUnit.Case
  # doctest Jido.BehaviorTree  # TODO: Fix doctest issues

  alias Jido.BehaviorTree
  alias Jido.BehaviorTree.Test.Nodes.SimpleNode

  test "creates new behavior tree" do
    node = SimpleNode.new("test")
    tree = BehaviorTree.new(node)

    assert %BehaviorTree.Tree{} = tree
    assert BehaviorTree.Tree.root(tree) == node
  end

  test "executes behavior tree tick" do
    node = SimpleNode.new("test")
    tree = BehaviorTree.new(node)
    tick = BehaviorTree.tick()

    {status, updated_tree} = BehaviorTree.tick(tree, tick)

    assert status == :success
    assert %BehaviorTree.Tree{} = updated_tree

    # Verify the node was ticked
    updated_node = BehaviorTree.Tree.root(updated_tree)
    assert updated_node.tick_count == 1
  end
end
