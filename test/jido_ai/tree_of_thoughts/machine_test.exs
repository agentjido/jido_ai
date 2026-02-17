defmodule Jido.AI.Reasoning.TreeOfThoughts.MachineTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Reasoning.TreeOfThoughts.Machine

  # ============================================================================
  # Machine Creation
  # ============================================================================

  describe "new/0 and new/1" do
    test "creates machine in idle state with defaults" do
      machine = Machine.new()
      assert machine.status == "idle"
      assert machine.nodes == %{}
      assert machine.root_id == nil
      assert machine.branching_factor == 3
      assert machine.max_depth == 3
      assert machine.traversal_strategy == :best_first
      assert machine.usage == %{}
      assert machine.started_at == nil
    end

    test "accepts custom branching_factor" do
      machine = Machine.new(branching_factor: 5)
      assert machine.branching_factor == 5
    end

    test "accepts custom max_depth" do
      machine = Machine.new(max_depth: 5)
      assert machine.max_depth == 5
    end

    test "accepts custom traversal_strategy" do
      machine = Machine.new(traversal_strategy: :dfs)
      assert machine.traversal_strategy == :dfs

      machine = Machine.new(traversal_strategy: :bfs)
      assert machine.traversal_strategy == :bfs
    end
  end

  # ============================================================================
  # Start Transition
  # ============================================================================

  describe "update/3 with :start message" do
    test "transitions from idle to generating" do
      machine = Machine.new()
      env = %{}

      {machine, _directives} = Machine.update(machine, {:start, "Solve puzzle", "tot_123"}, env)

      assert machine.status == "generating"
      assert machine.prompt == "Solve puzzle"
    end

    test "creates root node" do
      machine = Machine.new()

      {machine, _directives} = Machine.update(machine, {:start, "Test problem", "tot_123"}, %{})

      assert machine.root_id != nil
      assert Map.has_key?(machine.nodes, machine.root_id)

      root = Machine.get_node(machine, machine.root_id)
      assert root.content == "Test problem"
      assert root.parent_id == nil
      assert root.depth == 0
      assert root.children == []
    end

    test "initializes usage and started_at" do
      machine = Machine.new()

      before = System.monotonic_time(:millisecond)
      {machine, _directives} = Machine.update(machine, {:start, "Test", "tot_123"}, %{})
      after_time = System.monotonic_time(:millisecond)

      assert machine.usage == %{}
      assert is_integer(machine.started_at)
      assert machine.started_at >= before
      assert machine.started_at <= after_time
    end

    test "returns generate_thoughts directive" do
      machine = Machine.new(branching_factor: 3)

      {_machine, directives} = Machine.update(machine, {:start, "Problem", "tot_123"}, %{})

      assert [{:generate_thoughts, "tot_123", context, 3}] = directives
      assert length(context) == 2
      assert Enum.at(context, 0).role == :system
      assert Enum.at(context, 1).role == :user
    end
  end

  # ============================================================================
  # Thoughts Generated
  # ============================================================================

  describe "update/3 with :thoughts_generated message" do
    test "transitions to evaluating and returns evaluate directive" do
      machine = %Machine{
        status: "generating",
        current_call_id: "tot_123",
        nodes: %{"root" => %{id: "root", parent_id: nil, content: "Problem", score: nil, children: [], depth: 0}},
        root_id: "root",
        current_node_id: "root",
        branching_factor: 3,
        max_depth: 3,
        started_at: System.monotonic_time(:millisecond)
      }

      thoughts = ["Approach A", "Approach B", "Approach C"]
      {machine, directives} = Machine.update(machine, {:thoughts_generated, "tot_123", thoughts}, %{})

      assert machine.status == "evaluating"
      assert machine.pending_thoughts == thoughts
      assert [{:evaluate_thoughts, _call_id, ^thoughts}] = directives
    end

    test "ignores message with wrong call_id" do
      machine = %Machine{
        status: "generating",
        current_call_id: "tot_123",
        nodes: %{},
        started_at: System.monotonic_time(:millisecond)
      }

      thoughts = ["Approach A"]
      {machine, directives} = Machine.update(machine, {:thoughts_generated, "wrong_id", thoughts}, %{})

      assert machine.status == "generating"
      assert directives == []
    end
  end

  # ============================================================================
  # Thoughts Evaluated
  # ============================================================================

  describe "update/3 with :thoughts_evaluated message" do
    setup do
      machine = %Machine{
        status: "evaluating",
        current_call_id: "tot_123",
        nodes: %{"root" => %{id: "root", parent_id: nil, content: "Problem", score: nil, children: [], depth: 0}},
        root_id: "root",
        current_node_id: "root",
        pending_thoughts: ["Approach A", "Approach B", "Approach C"],
        branching_factor: 3,
        max_depth: 3,
        traversal_strategy: :best_first,
        frontier: [],
        started_at: System.monotonic_time(:millisecond)
      }

      %{machine: machine}
    end

    test "creates child nodes with scores", %{machine: machine} do
      scores = %{"Approach A" => 0.7, "Approach B" => 0.9, "Approach C" => 0.5}

      {machine, _directives} = Machine.update(machine, {:thoughts_evaluated, "tot_123", scores}, %{})

      root = Machine.get_node(machine, "root")
      assert length(root.children) == 3

      children = Machine.get_children(machine, "root")
      assert length(children) == 3

      # Check scores are assigned
      scores_found = Enum.map(children, & &1.score) |> Enum.sort()
      assert scores_found == [0.5, 0.7, 0.9]
    end

    test "completes when solution has score 1.0", %{machine: machine} do
      scores = %{"Approach A" => 0.7, "Approach B" => 1.0, "Approach C" => 0.5}

      {machine, _directives} = Machine.update(machine, {:thoughts_evaluated, "tot_123", scores}, %{})

      assert machine.status == "completed"
      assert machine.termination_reason == :success
      assert machine.result == "Approach B"
    end

    test "completes with max_depth when no perfect solution", %{machine: machine} do
      # Set max_depth to 1 so children hit the limit
      machine = %{machine | max_depth: 1}
      scores = %{"Approach A" => 0.7, "Approach B" => 0.9, "Approach C" => 0.5}

      {machine, _directives} = Machine.update(machine, {:thoughts_evaluated, "tot_123", scores}, %{})

      assert machine.status == "completed"
      assert machine.termination_reason == :max_depth
      # Best scoring approach
      assert machine.result == "Approach B"
    end

    test "continues expanding when below max_depth", %{machine: machine} do
      scores = %{"Approach A" => 0.7, "Approach B" => 0.9, "Approach C" => 0.5}

      {machine, directives} = Machine.update(machine, {:thoughts_evaluated, "tot_123", scores}, %{})

      assert machine.status == "generating"
      # Should have a new generate_thoughts directive
      assert [{:generate_thoughts, _call_id, _context, 3}] = directives
    end
  end

  # ============================================================================
  # LLM Result Handling
  # ============================================================================

  describe "update/3 with :llm_result message in generating state" do
    test "parses thoughts from response and transitions to evaluating" do
      machine = %Machine{
        status: "generating",
        current_call_id: "tot_123",
        nodes: %{"root" => %{id: "root", parent_id: nil, content: "Problem", score: nil, children: [], depth: 0}},
        root_id: "root",
        current_node_id: "root",
        branching_factor: 3,
        max_depth: 3,
        started_at: System.monotonic_time(:millisecond)
      }

      result = {:ok, %{text: "1. First approach\n2. Second approach\n3. Third approach"}}
      {machine, directives} = Machine.update(machine, {:llm_result, "tot_123", result}, %{})

      assert machine.status == "evaluating"
      assert length(machine.pending_thoughts) == 3
      assert [{:evaluate_thoughts, _call_id, _thoughts}] = directives
    end

    test "accumulates usage from result" do
      machine = %Machine{
        status: "generating",
        current_call_id: "tot_123",
        nodes: %{"root" => %{id: "root", parent_id: nil, content: "Problem", score: nil, children: [], depth: 0}},
        root_id: "root",
        current_node_id: "root",
        usage: %{},
        branching_factor: 3,
        max_depth: 3,
        started_at: System.monotonic_time(:millisecond)
      }

      result = {:ok, %{text: "1. Approach", usage: %{input_tokens: 100, output_tokens: 50}}}
      {machine, _directives} = Machine.update(machine, {:llm_result, "tot_123", result}, %{})

      assert machine.usage == %{input_tokens: 100, output_tokens: 50}
    end

    test "transitions to error on failure" do
      machine = %Machine{
        status: "generating",
        current_call_id: "tot_123",
        nodes: %{},
        started_at: System.monotonic_time(:millisecond)
      }

      result = {:error, :rate_limited}
      {machine, _directives} = Machine.update(machine, {:llm_result, "tot_123", result}, %{})

      assert machine.status == "error"
      assert machine.termination_reason == :error
    end
  end

  describe "update/3 with :llm_result message in evaluating state" do
    test "parses scores from response" do
      machine = %Machine{
        status: "evaluating",
        current_call_id: "tot_123",
        nodes: %{"root" => %{id: "root", parent_id: nil, content: "Problem", score: nil, children: [], depth: 0}},
        root_id: "root",
        current_node_id: "root",
        pending_thoughts: ["Approach A", "Approach B", "Approach C"],
        branching_factor: 3,
        max_depth: 3,
        traversal_strategy: :best_first,
        frontier: [],
        started_at: System.monotonic_time(:millisecond)
      }

      result = {:ok, %{text: "1: 0.7 - Good\n2: 0.9 - Best\n3: 0.5 - OK"}}
      {machine, _directives} = Machine.update(machine, {:llm_result, "tot_123", result}, %{})

      # Should have created children with scores
      children = Machine.get_children(machine, "root")
      scores = Enum.map(children, & &1.score) |> Enum.sort()
      assert scores == [0.5, 0.7, 0.9]
    end
  end

  # ============================================================================
  # Streaming Partial Updates
  # ============================================================================

  describe "update/3 with :llm_partial message" do
    test "accumulates content delta in streaming_text" do
      machine = %Machine{
        status: "generating",
        current_call_id: "tot_123",
        streaming_text: "Hello"
      }

      {machine, _directives} = Machine.update(machine, {:llm_partial, "tot_123", " world", :content}, %{})

      assert machine.streaming_text == "Hello world"
    end

    test "ignores partial from wrong call_id" do
      machine = %Machine{
        status: "generating",
        current_call_id: "tot_123",
        streaming_text: "Hello"
      }

      {machine, _directives} = Machine.update(machine, {:llm_partial, "wrong_id", " world", :content}, %{})

      assert machine.streaming_text == "Hello"
    end
  end

  # ============================================================================
  # Thought Parsing
  # ============================================================================

  describe "parse_thoughts/1" do
    test "parses numbered thoughts with periods" do
      text = """
      1. First approach to solve
      2. Second approach here
      3. Third different method
      """

      thoughts = Machine.parse_thoughts(text)

      assert length(thoughts) == 3
      assert Enum.at(thoughts, 0) =~ "First approach"
      assert Enum.at(thoughts, 1) =~ "Second approach"
      assert Enum.at(thoughts, 2) =~ "Third different"
    end

    test "parses numbered thoughts with colons" do
      text = """
      1: First approach
      2: Second approach
      3: Third approach
      """

      thoughts = Machine.parse_thoughts(text)
      assert length(thoughts) == 3
    end

    test "parses numbered thoughts with parentheses" do
      text = """
      1) First approach
      2) Second approach
      3) Third approach
      """

      thoughts = Machine.parse_thoughts(text)
      assert length(thoughts) == 3
    end

    test "handles empty input" do
      assert Machine.parse_thoughts("") == []
      assert Machine.parse_thoughts(nil) == []
    end
  end

  # ============================================================================
  # Score Parsing
  # ============================================================================

  describe "parse_scores/2" do
    test "parses scores with colons" do
      text = "1: 0.7 - explanation\n2: 0.9 - good\n3: 0.5 - ok"
      thoughts = ["A", "B", "C"]

      scores = Machine.parse_scores(text, thoughts)

      assert scores["A"] == 0.7
      assert scores["B"] == 0.9
      assert scores["C"] == 0.5
    end

    test "parses scores with periods" do
      text = "1. 0.8\n2. 0.6\n3. 0.4"
      thoughts = ["A", "B", "C"]

      scores = Machine.parse_scores(text, thoughts)

      assert scores["A"] == 0.8
      assert scores["B"] == 0.6
      assert scores["C"] == 0.4
    end

    test "clamps scores above 1.0" do
      text = "1: 1.5\n2: 0.3"
      thoughts = ["A", "B"]

      scores = Machine.parse_scores(text, thoughts)

      assert scores["A"] == 1.0
      assert scores["B"] == 0.3
    end

    test "defaults to 0.5 for unparseable scores" do
      text = "1: 0.7\n2: invalid"
      thoughts = ["A", "B"]

      scores = Machine.parse_scores(text, thoughts)

      assert scores["A"] == 0.7
      # "invalid" can't be parsed, so defaults to 0.5
      assert scores["B"] == 0.5
    end

    test "defaults to 0.5 for missing scores" do
      text = "1: 0.7"
      thoughts = ["A", "B", "C"]

      scores = Machine.parse_scores(text, thoughts)

      assert scores["A"] == 0.7
      assert scores["B"] == 0.5
      assert scores["C"] == 0.5
    end
  end

  # ============================================================================
  # Tree Operations
  # ============================================================================

  describe "tree operations" do
    setup do
      # Build a small tree
      # root -> [child1, child2]
      # child1 -> [grandchild1]
      nodes = %{
        "root" => %{id: "root", parent_id: nil, content: "Root", score: nil, children: ["child1", "child2"], depth: 0},
        "child1" => %{
          id: "child1",
          parent_id: "root",
          content: "Child 1",
          score: 0.8,
          children: ["grandchild1"],
          depth: 1
        },
        "child2" => %{id: "child2", parent_id: "root", content: "Child 2", score: 0.6, children: [], depth: 1},
        "grandchild1" => %{
          id: "grandchild1",
          parent_id: "child1",
          content: "Grandchild",
          score: 0.9,
          children: [],
          depth: 2
        }
      }

      machine = %Machine{
        status: "completed",
        nodes: nodes,
        root_id: "root"
      }

      %{machine: machine}
    end

    test "get_node returns node by id", %{machine: machine} do
      node = Machine.get_node(machine, "child1")
      assert node.content == "Child 1"
      assert node.score == 0.8
    end

    test "get_node returns nil for unknown id", %{machine: machine} do
      assert Machine.get_node(machine, "unknown") == nil
    end

    test "get_children returns child nodes", %{machine: machine} do
      children = Machine.get_children(machine, "root")
      assert length(children) == 2
      assert Enum.any?(children, &(&1.id == "child1"))
      assert Enum.any?(children, &(&1.id == "child2"))
    end

    test "get_children returns empty for leaf", %{machine: machine} do
      children = Machine.get_children(machine, "child2")
      assert children == []
    end

    test "get_path_to_node returns path from root", %{machine: machine} do
      path = Machine.get_path_to_node(machine, "grandchild1")
      assert length(path) == 3
      assert Enum.at(path, 0).id == "root"
      assert Enum.at(path, 1).id == "child1"
      assert Enum.at(path, 2).id == "grandchild1"
    end

    test "find_best_leaf returns highest scoring leaf", %{machine: machine} do
      best = Machine.find_best_leaf(machine)
      assert best.id == "grandchild1"
      assert best.score == 0.9
    end

    test "find_leaves returns all leaf nodes", %{machine: machine} do
      leaves = Machine.find_leaves(machine)
      assert length(leaves) == 2
      leaf_ids = Enum.map(leaves, & &1.id)
      assert "child2" in leaf_ids
      assert "grandchild1" in leaf_ids
    end
  end

  # ============================================================================
  # to_map/from_map
  # ============================================================================

  describe "to_map/1 and from_map/1" do
    test "round-trips machine state" do
      machine = %Machine{
        status: "completed",
        prompt: "Test problem",
        nodes: %{"root" => %{id: "root", parent_id: nil, content: "Root", score: nil, children: [], depth: 0}},
        root_id: "root",
        branching_factor: 4,
        max_depth: 5,
        traversal_strategy: :dfs,
        usage: %{input_tokens: 100},
        started_at: 12_345
      }

      map = Machine.to_map(machine)
      restored = Machine.from_map(map)

      assert restored.status == "completed"
      assert restored.prompt == "Test problem"
      assert restored.root_id == "root"
      assert restored.branching_factor == 4
      assert restored.max_depth == 5
      assert restored.traversal_strategy == :dfs
      assert restored.usage == %{input_tokens: 100}
      assert restored.started_at == 12_345
    end

    test "converts status to atom in to_map" do
      machine = %Machine{status: "generating"}
      map = Machine.to_map(machine)

      assert map.status == :generating
    end

    test "from_map handles atom status" do
      map = %{status: :completed}
      machine = Machine.from_map(map)

      assert machine.status == "completed"
    end
  end

  # ============================================================================
  # ID Generation
  # ============================================================================

  describe "ID generation" do
    test "generate_node_id returns unique IDs with prefix" do
      id1 = Machine.generate_node_id()
      id2 = Machine.generate_node_id()

      assert String.starts_with?(id1, "tot_node_")
      assert String.starts_with?(id2, "tot_node_")
      assert id1 != id2
    end

    test "generate_call_id returns unique IDs with prefix" do
      id1 = Machine.generate_call_id()
      id2 = Machine.generate_call_id()

      assert String.starts_with?(id1, "tot_")
      assert String.starts_with?(id2, "tot_")
      assert id1 != id2
    end
  end

  # ============================================================================
  # Default Prompts
  # ============================================================================

  describe "default prompts" do
    test "default_generation_prompt returns a prompt about generating approaches" do
      prompt = Machine.default_generation_prompt()

      assert is_binary(prompt)
      assert prompt =~ "generate"
    end

    test "default_evaluation_prompt returns a prompt about scoring" do
      prompt = Machine.default_evaluation_prompt()

      assert is_binary(prompt)
      assert prompt =~ "score"
    end
  end
end
