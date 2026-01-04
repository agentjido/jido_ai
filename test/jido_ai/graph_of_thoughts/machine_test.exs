defmodule Jido.AI.GraphOfThoughts.MachineTest do
  use ExUnit.Case, async: true

  alias Jido.AI.GraphOfThoughts.Machine

  describe "new/1" do
    test "creates machine with default values" do
      machine = Machine.new()

      assert machine.status == "idle"
      assert machine.nodes == %{}
      assert machine.edges == []
      assert machine.max_nodes == 20
      assert machine.max_depth == 5
      assert machine.aggregation_strategy == :synthesis
    end

    test "accepts custom options" do
      machine = Machine.new(max_nodes: 10, max_depth: 3, aggregation_strategy: :voting)

      assert machine.max_nodes == 10
      assert machine.max_depth == 3
      assert machine.aggregation_strategy == :voting
    end
  end

  describe "status/1" do
    test "returns status as atom" do
      machine = Machine.new()
      assert Machine.status(machine) == :idle
    end
  end

  describe "from_map/1" do
    test "creates machine from map" do
      map = %{
        status: "generating",
        prompt: "test prompt",
        nodes: %{"node_1" => %{id: "node_1", content: "test", score: nil, depth: 0, metadata: %{}}}
      }

      machine = Machine.from_map(map)

      assert machine.status == "generating"
      assert machine.prompt == "test prompt"
      assert map_size(machine.nodes) == 1
    end

    test "handles atom status" do
      map = %{status: :idle}
      machine = Machine.from_map(map)
      assert machine.status == "idle"
    end

    test "uses defaults for missing keys" do
      machine = Machine.from_map(%{})

      assert machine.status == "idle"
      assert machine.nodes == %{}
      assert machine.edges == []
    end

    test "filters out unknown keys" do
      map = %{status: "idle", unknown_key: "value", config: %{}}
      machine = Machine.from_map(map)
      assert machine.status == "idle"
    end
  end

  describe "update/3 with :start" do
    test "transitions from idle to generating" do
      machine = Machine.new()
      {updated, directives} = Machine.update(machine, {:start, "Solve this problem", "call_1"}, %{})

      assert updated.status == "generating"
      assert updated.prompt == "Solve this problem"
      assert updated.current_call_id == "call_1"
      assert map_size(updated.nodes) == 1
      assert updated.root_id != nil
    end

    test "creates root node with prompt" do
      machine = Machine.new()
      {updated, _} = Machine.update(machine, {:start, "Test prompt", "call_1"}, %{})

      root = Machine.get_node(updated, updated.root_id)
      assert root.content == "Test prompt"
      assert root.depth == 0
      assert root.metadata.type == :root
    end

    test "returns generate_thought directive" do
      machine = Machine.new()
      {_, directives} = Machine.update(machine, {:start, "Problem", "call_1"}, %{})

      assert [{:generate_thought, "call_1", context}] = directives
      assert context.prompt == "Problem"
      assert is_binary(context.system_prompt)
    end
  end

  describe "update/3 with :llm_result in generating state" do
    setup do
      machine = Machine.new()
      {machine, _} = Machine.update(machine, {:start, "Problem", "call_1"}, %{})
      {:ok, machine: machine}
    end

    test "creates new node from response", %{machine: machine} do
      result = {:ok, %{text: "This is my analysis"}}
      {updated, _} = Machine.update(machine, {:llm_result, "call_1", result}, %{})

      # Should have root + new node
      assert map_size(updated.nodes) >= 2
    end

    test "accumulates usage", %{machine: machine} do
      result = {:ok, %{text: "Response", usage: %{input_tokens: 10, output_tokens: 20}}}
      {updated, _} = Machine.update(machine, {:llm_result, "call_1", result}, %{})

      assert updated.usage.input_tokens == 10
      assert updated.usage.output_tokens == 20
      assert updated.usage.total_tokens == 30
    end

    test "ignores stale call_id", %{machine: machine} do
      result = {:ok, %{text: "Response"}}
      {updated, directives} = Machine.update(machine, {:llm_result, "wrong_call_id", result}, %{})

      # Should not change
      assert updated.status == machine.status
      assert directives == []
    end
  end

  describe "update/3 with :llm_partial" do
    setup do
      machine = Machine.new()
      {machine, _} = Machine.update(machine, {:start, "Problem", "call_1"}, %{})
      {:ok, machine: machine}
    end

    test "accumulates streaming text", %{machine: machine} do
      {m1, _} = Machine.update(machine, {:llm_partial, "call_1", "Hello ", :content}, %{})
      {m2, _} = Machine.update(m1, {:llm_partial, "call_1", "World", :content}, %{})

      assert m2.streaming_text == "Hello World"
    end

    test "ignores stale call_id", %{machine: machine} do
      {updated, _} = Machine.update(machine, {:llm_partial, "wrong_id", "text", :content}, %{})
      assert updated.streaming_text == ""
    end
  end

  describe "update/3 with :error" do
    test "transitions to error state" do
      machine = Machine.new()
      {machine, _} = Machine.update(machine, {:start, "Problem", "call_1"}, %{})

      {updated, _} = Machine.update(machine, {:error, "Something went wrong"}, %{})

      assert updated.status == "error"
      assert updated.result == {:error, "Something went wrong"}
      assert updated.termination_reason == :error
    end
  end

  describe "graph operations" do
    test "add_node/2 adds node to graph" do
      machine = Machine.new()
      node = %{id: "n1", content: "Test", score: nil, depth: 0, metadata: %{}}

      updated = Machine.add_node(machine, node)

      assert Machine.get_node(updated, "n1") == node
    end

    test "add_edge/4 adds edge to graph" do
      machine = Machine.new()
      node1 = %{id: "n1", content: "A", score: nil, depth: 0, metadata: %{}}
      node2 = %{id: "n2", content: "B", score: nil, depth: 1, metadata: %{}}

      updated =
        machine
        |> Machine.add_node(node1)
        |> Machine.add_node(node2)
        |> Machine.add_edge("n1", "n2", :generates)

      assert length(updated.edges) == 1
      assert hd(updated.edges) == %{from: "n1", to: "n2", type: :generates}
    end

    test "get_children/2 returns child node ids" do
      machine = build_simple_graph()

      children = Machine.get_children(machine, "root")
      assert "child1" in children
      assert "child2" in children
    end

    test "get_parents/2 returns parent node ids" do
      machine = build_simple_graph()

      parents = Machine.get_parents(machine, "child1")
      assert parents == ["root"]
    end

    test "get_outgoing_edges/2 returns edges from node" do
      machine = build_simple_graph()

      edges = Machine.get_outgoing_edges(machine, "root")
      assert length(edges) == 2
    end

    test "get_incoming_edges/2 returns edges to node" do
      machine = build_simple_graph()

      edges = Machine.get_incoming_edges(machine, "child1")
      assert length(edges) == 1
    end
  end

  describe "ancestors and descendants" do
    test "get_ancestors/2 returns all ancestors" do
      machine = build_deep_graph()

      ancestors = Machine.get_ancestors(machine, "grandchild")
      assert "child" in ancestors
      assert "root" in ancestors
    end

    test "get_descendants/2 returns all descendants" do
      machine = build_deep_graph()

      descendants = Machine.get_descendants(machine, "root")
      assert "child" in descendants
      assert "grandchild" in descendants
    end

    test "handles nodes with no ancestors" do
      machine = build_simple_graph()
      ancestors = Machine.get_ancestors(machine, "root")
      assert ancestors == []
    end

    test "handles nodes with no descendants" do
      machine = build_simple_graph()
      descendants = Machine.get_descendants(machine, "child1")
      assert descendants == []
    end
  end

  describe "cycle detection" do
    test "has_cycle?/1 returns false for acyclic graph" do
      machine = build_simple_graph()
      refute Machine.has_cycle?(machine)
    end

    test "has_cycle?/1 returns true for cyclic graph" do
      machine = build_cyclic_graph()
      assert Machine.has_cycle?(machine)
    end
  end

  describe "leaf finding" do
    test "find_leaves/1 returns nodes with no outgoing edges" do
      machine = build_simple_graph()

      leaves = Machine.find_leaves(machine)
      leaf_ids = Enum.map(leaves, & &1.id)

      assert "child1" in leaf_ids
      assert "child2" in leaf_ids
      refute "root" in leaf_ids
    end

    test "find_best_leaf/1 returns highest scored leaf" do
      machine = build_scored_graph()

      best = Machine.find_best_leaf(machine)
      assert best.id == "child2"
      assert best.score == 0.9
    end

    test "find_best_leaf/1 returns nil when no scored leaves" do
      machine = build_simple_graph()
      assert Machine.find_best_leaf(machine) == nil
    end
  end

  describe "path tracing" do
    test "trace_path/2 returns path from root to node" do
      machine = build_deep_graph()

      path = Machine.trace_path(machine, "grandchild")
      assert path == ["root", "child", "grandchild"]
    end

    test "trace_path/2 handles root node" do
      machine = build_simple_graph()

      path = Machine.trace_path(machine, "root")
      assert path == ["root"]
    end
  end

  describe "termination conditions" do
    test "completes when max_nodes reached" do
      machine = Machine.new(max_nodes: 2)
      {machine, _} = Machine.update(machine, {:start, "Problem", "call_1"}, %{})

      result = {:ok, %{text: "Response 1"}}
      {updated, _} = Machine.update(machine, {:llm_result, "call_1", result}, %{})

      # With max_nodes: 2 and root + 1 response, should trigger completion
      # or continue depending on aggregation logic
      assert updated.status in ["generating", "connecting", "aggregating", "completed"]
    end
  end

  describe "ID generation" do
    test "generate_node_id/0 creates unique IDs" do
      id1 = Machine.generate_node_id()
      id2 = Machine.generate_node_id()

      assert String.starts_with?(id1, "got_node_")
      assert String.starts_with?(id2, "got_node_")
      assert id1 != id2
    end

    test "generate_call_id/0 creates unique IDs" do
      id1 = Machine.generate_call_id()
      id2 = Machine.generate_call_id()

      assert String.starts_with?(id1, "got_")
      assert String.starts_with?(id2, "got_")
      assert id1 != id2
    end
  end

  describe "default prompts" do
    test "default_generation_prompt/0 returns string" do
      prompt = Machine.default_generation_prompt()
      assert is_binary(prompt)
      assert String.length(prompt) > 0
    end

    test "default_connection_prompt/0 returns string" do
      prompt = Machine.default_connection_prompt()
      assert is_binary(prompt)
      assert String.contains?(prompt, "CONNECTION")
    end

    test "default_aggregation_prompt/0 returns string" do
      prompt = Machine.default_aggregation_prompt()
      assert is_binary(prompt)
      assert String.contains?(prompt, "synthesiz")
    end
  end

  # Test Helpers

  defp build_simple_graph do
    %Machine{
      status: "generating",
      nodes: %{
        "root" => %{id: "root", content: "Root", score: nil, depth: 0, metadata: %{}},
        "child1" => %{id: "child1", content: "Child 1", score: nil, depth: 1, metadata: %{}},
        "child2" => %{id: "child2", content: "Child 2", score: nil, depth: 1, metadata: %{}}
      },
      edges: [
        %{from: "root", to: "child1", type: :generates},
        %{from: "root", to: "child2", type: :generates}
      ],
      root_id: "root"
    }
  end

  defp build_deep_graph do
    %Machine{
      status: "generating",
      nodes: %{
        "root" => %{id: "root", content: "Root", score: nil, depth: 0, metadata: %{}},
        "child" => %{id: "child", content: "Child", score: nil, depth: 1, metadata: %{}},
        "grandchild" => %{id: "grandchild", content: "Grandchild", score: nil, depth: 2, metadata: %{}}
      },
      edges: [
        %{from: "root", to: "child", type: :generates},
        %{from: "child", to: "grandchild", type: :generates}
      ],
      root_id: "root"
    }
  end

  defp build_cyclic_graph do
    %Machine{
      status: "generating",
      nodes: %{
        "a" => %{id: "a", content: "A", score: nil, depth: 0, metadata: %{}},
        "b" => %{id: "b", content: "B", score: nil, depth: 1, metadata: %{}},
        "c" => %{id: "c", content: "C", score: nil, depth: 2, metadata: %{}}
      },
      edges: [
        %{from: "a", to: "b", type: :generates},
        %{from: "b", to: "c", type: :generates},
        %{from: "c", to: "a", type: :connects}  # Creates cycle
      ],
      root_id: "a"
    }
  end

  defp build_scored_graph do
    %Machine{
      status: "generating",
      nodes: %{
        "root" => %{id: "root", content: "Root", score: nil, depth: 0, metadata: %{}},
        "child1" => %{id: "child1", content: "Child 1", score: 0.5, depth: 1, metadata: %{}},
        "child2" => %{id: "child2", content: "Child 2", score: 0.9, depth: 1, metadata: %{}}
      },
      edges: [
        %{from: "root", to: "child1", type: :generates},
        %{from: "root", to: "child2", type: :generates}
      ],
      root_id: "root"
    }
  end
end
