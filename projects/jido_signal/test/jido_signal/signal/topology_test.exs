defmodule JidoTest.Signal.TopologyTest do
  use ExUnit.Case, async: true

  alias Jido.Signal.Topology
  alias Jido.Signal.Topology.ProcessNode

  @moduletag :capture_log

  # Simple GenServer for testing state retrieval
  defmodule TestGenServer do
    use GenServer

    def start_link(initial_state) do
      GenServer.start_link(__MODULE__, initial_state)
    end

    @impl true
    def init(state) do
      {:ok, state}
    end

    @impl true
    def handle_call(:get_state, _from, state) do
      {:reply, {:ok, state}, state}
    end

    @impl true
    def handle_call({:update_state, new_state}, _from, _state) do
      {:reply, :ok, new_state}
    end
  end

  describe "new/0" do
    test "creates an empty topology" do
      topology = Topology.new()
      assert %Topology{processes: processes, root_ids: root_ids} = topology
      assert map_size(processes) == 0
      assert MapSet.size(root_ids) == 0
    end
  end

  describe "register/4" do
    test "registers a process without parent (root process)" do
      topology = Topology.new()
      {:ok, pid} = TestGenServer.start_link(%{name: "root"})

      assert {:ok, updated_topology} =
               Topology.register(topology, "root1", pid, name: "Root Process")

      assert Topology.count(updated_topology) == 1
      assert MapSet.member?(updated_topology.root_ids, "root1")

      process = updated_topology.processes["root1"]

      assert %ProcessNode{
               id: "root1",
               pid: ^pid,
               name: "Root Process",
               parent_id: nil,
               child_ids: child_ids,
               metadata: %{}
             } = process

      assert MapSet.size(child_ids) == 0
    end

    test "registers a process with metadata" do
      topology = Topology.new()
      {:ok, pid} = TestGenServer.start_link(%{})
      metadata = %{type: "worker", priority: :high}

      assert {:ok, updated_topology} =
               Topology.register(topology, "worker1", pid, metadata: metadata)

      process = updated_topology.processes["worker1"]
      assert process.metadata == metadata
    end

    test "registers a child process" do
      topology = Topology.new()
      {:ok, parent_pid} = TestGenServer.start_link(%{})
      {:ok, child_pid} = TestGenServer.start_link(%{})

      # Register parent first
      {:ok, topology} = Topology.register(topology, "parent", parent_pid)

      # Register child
      assert {:ok, updated_topology} =
               Topology.register(topology, "child", child_pid, parent_id: "parent")

      # Check parent-child relationship
      parent = updated_topology.processes["parent"]
      child = updated_topology.processes["child"]

      assert MapSet.member?(parent.child_ids, "child")
      assert child.parent_id == "parent"

      # Child should not be in root_ids
      refute MapSet.member?(updated_topology.root_ids, "child")
      assert MapSet.member?(updated_topology.root_ids, "parent")
    end

    test "returns error when process ID already exists" do
      topology = Topology.new()
      {:ok, pid1} = TestGenServer.start_link(%{})
      {:ok, pid2} = TestGenServer.start_link(%{})

      {:ok, topology} = Topology.register(topology, "process1", pid1)

      assert {:error, :already_exists} =
               Topology.register(topology, "process1", pid2)
    end

    test "returns error when parent does not exist" do
      topology = Topology.new()
      {:ok, pid} = TestGenServer.start_link(%{})

      assert {:error, :parent_not_found} =
               Topology.register(topology, "child", pid, parent_id: "nonexistent")
    end

    test "registers with all optional parameters" do
      topology = Topology.new()
      {:ok, parent_pid} = TestGenServer.start_link(%{})
      {:ok, child_pid} = TestGenServer.start_link(%{})

      {:ok, topology} = Topology.register(topology, "parent", parent_pid)

      assert {:ok, updated_topology} =
               Topology.register(
                 topology,
                 "child",
                 child_pid,
                 name: "Child Process",
                 metadata: %{type: "worker"},
                 parent_id: "parent"
               )

      child = updated_topology.processes["child"]
      assert child.name == "Child Process"
      assert child.metadata == %{type: "worker"}
      assert child.parent_id == "parent"
    end
  end

  describe "unregister/2" do
    test "unregisters a root process" do
      topology = Topology.new()
      {:ok, pid} = TestGenServer.start_link(%{})

      {:ok, topology} = Topology.register(topology, "root1", pid)
      assert Topology.count(topology) == 1

      assert {:ok, updated_topology} = Topology.unregister(topology, "root1")
      assert Topology.count(updated_topology) == 0
      assert MapSet.size(updated_topology.root_ids) == 0
    end

    test "unregisters a child process and removes from parent" do
      topology = Topology.new()
      {:ok, parent_pid} = TestGenServer.start_link(%{})
      {:ok, child_pid} = TestGenServer.start_link(%{})

      {:ok, topology} = Topology.register(topology, "parent", parent_pid)
      {:ok, topology} = Topology.register(topology, "child", child_pid, parent_id: "parent")

      assert {:ok, updated_topology} = Topology.unregister(topology, "child")

      # Child should be removed
      refute Map.has_key?(updated_topology.processes, "child")

      # Parent should no longer have child in its child_ids
      parent = updated_topology.processes["parent"]
      refute MapSet.member?(parent.child_ids, "child")
    end

    test "unregisters process with all its descendants" do
      topology = Topology.new()
      {:ok, root_pid} = TestGenServer.start_link(%{})
      {:ok, child1_pid} = TestGenServer.start_link(%{})
      {:ok, child2_pid} = TestGenServer.start_link(%{})
      {:ok, grandchild_pid} = TestGenServer.start_link(%{})

      # Build hierarchy: root -> child1 -> grandchild
      #                        -> child2
      {:ok, topology} = Topology.register(topology, "root", root_pid)
      {:ok, topology} = Topology.register(topology, "child1", child1_pid, parent_id: "root")
      {:ok, topology} = Topology.register(topology, "child2", child2_pid, parent_id: "root")

      {:ok, topology} =
        Topology.register(topology, "grandchild", grandchild_pid, parent_id: "child1")

      assert Topology.count(topology) == 4

      # Unregister root - should remove all descendants
      assert {:ok, updated_topology} = Topology.unregister(topology, "root")
      assert Topology.count(updated_topology) == 0
    end

    test "returns error when process does not exist" do
      topology = Topology.new()
      assert {:error, :not_found} = Topology.unregister(topology, "nonexistent")
    end
  end

  describe "set_parent/3" do
    test "establishes parent-child relationship" do
      topology = Topology.new()
      {:ok, parent_pid} = TestGenServer.start_link(%{})
      {:ok, child_pid} = TestGenServer.start_link(%{})

      {:ok, topology} = Topology.register(topology, "parent", parent_pid)
      {:ok, topology} = Topology.register(topology, "child", child_pid)

      assert {:ok, updated_topology} = Topology.set_parent(topology, "parent", "child")

      parent = updated_topology.processes["parent"]
      child = updated_topology.processes["child"]

      assert MapSet.member?(parent.child_ids, "child")
      assert child.parent_id == "parent"

      # Child should no longer be a root
      refute MapSet.member?(updated_topology.root_ids, "child")
    end

    test "moves child from one parent to another" do
      topology = Topology.new()
      {:ok, parent1_pid} = TestGenServer.start_link(%{})
      {:ok, parent2_pid} = TestGenServer.start_link(%{})
      {:ok, child_pid} = TestGenServer.start_link(%{})

      {:ok, topology} = Topology.register(topology, "parent1", parent1_pid)
      {:ok, topology} = Topology.register(topology, "parent2", parent2_pid)
      {:ok, topology} = Topology.register(topology, "child", child_pid, parent_id: "parent1")

      # Move child to parent2
      assert {:ok, updated_topology} = Topology.set_parent(topology, "parent2", "child")

      parent1 = updated_topology.processes["parent1"]
      parent2 = updated_topology.processes["parent2"]
      child = updated_topology.processes["child"]

      # Child should be removed from parent1
      refute MapSet.member?(parent1.child_ids, "child")

      # Child should be added to parent2
      assert MapSet.member?(parent2.child_ids, "child")
      assert child.parent_id == "parent2"
    end

    test "returns error when either process does not exist" do
      topology = Topology.new()
      {:ok, pid} = TestGenServer.start_link(%{})

      {:ok, topology} = Topology.register(topology, "existing", pid)

      assert {:error, :not_found} = Topology.set_parent(topology, "nonexistent", "existing")
      assert {:error, :not_found} = Topology.set_parent(topology, "existing", "nonexistent")
    end

    test "returns error when setting parent would create cycle" do
      topology = Topology.new()
      {:ok, pid1} = TestGenServer.start_link(%{})
      {:ok, pid2} = TestGenServer.start_link(%{})
      {:ok, pid3} = TestGenServer.start_link(%{})

      # Create chain: grandparent -> parent -> child
      {:ok, topology} = Topology.register(topology, "grandparent", pid1)
      {:ok, topology} = Topology.register(topology, "parent", pid2, parent_id: "grandparent")
      {:ok, topology} = Topology.register(topology, "child", pid3, parent_id: "parent")

      # Try to make grandparent a child of child (would create cycle)
      assert {:error, :cycle_detected} = Topology.set_parent(topology, "child", "grandparent")

      # Try to make parent a child of child (would create cycle)  
      assert {:error, :cycle_detected} = Topology.set_parent(topology, "child", "parent")

      # Try to make process parent of itself
      assert {:error, :cycle_detected} = Topology.set_parent(topology, "parent", "parent")
    end
  end

  describe "list_all/1" do
    test "returns empty list for empty topology" do
      topology = Topology.new()
      assert Topology.list_all(topology) == []
    end

    test "returns all processes" do
      topology = Topology.new()
      {:ok, pid1} = TestGenServer.start_link(%{})
      {:ok, pid2} = TestGenServer.start_link(%{})

      {:ok, topology} = Topology.register(topology, "proc1", pid1)
      {:ok, topology} = Topology.register(topology, "proc2", pid2)

      all_processes = Topology.list_all(topology)
      assert length(all_processes) == 2

      process_ids = Enum.map(all_processes, & &1.id)
      assert "proc1" in process_ids
      assert "proc2" in process_ids
    end
  end

  describe "list_roots/1" do
    test "returns empty list for empty topology" do
      topology = Topology.new()
      assert Topology.list_roots(topology) == []
    end

    test "returns only root processes" do
      topology = Topology.new()
      {:ok, root_pid} = TestGenServer.start_link(%{})
      {:ok, child_pid} = TestGenServer.start_link(%{})

      {:ok, topology} = Topology.register(topology, "root", root_pid)
      {:ok, topology} = Topology.register(topology, "child", child_pid, parent_id: "root")

      roots = Topology.list_roots(topology)
      assert length(roots) == 1
      assert [%ProcessNode{id: "root"}] = roots
    end
  end

  describe "list_children/2" do
    test "returns empty list for nonexistent process" do
      topology = Topology.new()
      assert Topology.list_children(topology, "nonexistent") == []
    end

    test "returns empty list for process with no children" do
      topology = Topology.new()
      {:ok, pid} = TestGenServer.start_link(%{})

      {:ok, topology} = Topology.register(topology, "parent", pid)
      assert Topology.list_children(topology, "parent") == []
    end

    test "returns direct children only" do
      topology = Topology.new()
      {:ok, parent_pid} = TestGenServer.start_link(%{})
      {:ok, child1_pid} = TestGenServer.start_link(%{})
      {:ok, child2_pid} = TestGenServer.start_link(%{})
      {:ok, grandchild_pid} = TestGenServer.start_link(%{})

      {:ok, topology} = Topology.register(topology, "parent", parent_pid)
      {:ok, topology} = Topology.register(topology, "child1", child1_pid, parent_id: "parent")
      {:ok, topology} = Topology.register(topology, "child2", child2_pid, parent_id: "parent")

      {:ok, topology} =
        Topology.register(topology, "grandchild", grandchild_pid, parent_id: "child1")

      children = Topology.list_children(topology, "parent")
      assert length(children) == 2

      child_ids = Enum.map(children, & &1.id)
      assert "child1" in child_ids
      assert "child2" in child_ids
      refute "grandchild" in child_ids
    end
  end

  describe "list_descendants/2" do
    test "returns empty list for nonexistent process" do
      topology = Topology.new()
      assert Topology.list_descendants(topology, "nonexistent") == []
    end

    test "returns all descendants recursively" do
      topology = Topology.new()
      {:ok, root_pid} = TestGenServer.start_link(%{})
      {:ok, child1_pid} = TestGenServer.start_link(%{})
      {:ok, child2_pid} = TestGenServer.start_link(%{})
      {:ok, grandchild_pid} = TestGenServer.start_link(%{})

      {:ok, topology} = Topology.register(topology, "root", root_pid)
      {:ok, topology} = Topology.register(topology, "child1", child1_pid, parent_id: "root")
      {:ok, topology} = Topology.register(topology, "child2", child2_pid, parent_id: "root")

      {:ok, topology} =
        Topology.register(topology, "grandchild", grandchild_pid, parent_id: "child1")

      descendants = Topology.list_descendants(topology, "root")
      assert length(descendants) == 3

      descendant_ids = Enum.map(descendants, & &1.id)
      assert "child1" in descendant_ids
      assert "child2" in descendant_ids
      assert "grandchild" in descendant_ids
    end
  end

  describe "get_state/2" do
    test "returns error for nonexistent process" do
      topology = Topology.new()
      assert {:error, :not_found} = Topology.get_state(topology, "nonexistent")
    end

    test "retrieves state from GenServer process" do
      topology = Topology.new()
      initial_state = %{counter: 42, name: "test"}
      {:ok, pid} = TestGenServer.start_link(initial_state)

      {:ok, topology} = Topology.register(topology, "genserver", pid)

      assert {:ok, retrieved_state} = Topology.get_state(topology, "genserver")
      assert retrieved_state == initial_state
    end

    test "handles GenServer call failure" do
      topology = Topology.new()
      {:ok, pid} = TestGenServer.start_link(%{})

      {:ok, topology} = Topology.register(topology, "genserver", pid)

      # Stop the process to simulate failure
      GenServer.stop(pid)

      assert {:error, _reason} = Topology.get_state(topology, "genserver")
    end
  end

  describe "get_all_states/1" do
    test "returns empty map for empty topology" do
      topology = Topology.new()
      assert Topology.get_all_states(topology) == %{}
    end

    test "retrieves states from all processes" do
      topology = Topology.new()
      {:ok, pid1} = TestGenServer.start_link(%{id: 1})
      {:ok, pid2} = TestGenServer.start_link(%{id: 2})

      {:ok, topology} = Topology.register(topology, "proc1", pid1)
      {:ok, topology} = Topology.register(topology, "proc2", pid2)

      states = Topology.get_all_states(topology)
      assert states["proc1"] == %{id: 1}
      assert states["proc2"] == %{id: 2}
    end

    test "excludes processes that fail to return state" do
      topology = Topology.new()
      {:ok, pid1} = TestGenServer.start_link(%{id: 1})
      {:ok, pid2} = TestGenServer.start_link(%{id: 2})

      {:ok, topology} = Topology.register(topology, "proc1", pid1)
      {:ok, topology} = Topology.register(topology, "proc2", pid2)

      # Stop one process
      GenServer.stop(pid2)

      states = Topology.get_all_states(topology)
      assert states["proc1"] == %{id: 1}
      refute Map.has_key?(states, "proc2")
    end
  end

  describe "get_descendant_states/2" do
    test "returns empty map for nonexistent process" do
      topology = Topology.new()
      assert Topology.get_descendant_states(topology, "nonexistent") == %{}
    end

    test "retrieves states from all descendants" do
      topology = Topology.new()
      {:ok, parent_pid} = TestGenServer.start_link(%{role: "parent"})
      {:ok, child1_pid} = TestGenServer.start_link(%{role: "child1"})
      {:ok, child2_pid} = TestGenServer.start_link(%{role: "child2"})
      {:ok, grandchild_pid} = TestGenServer.start_link(%{role: "grandchild"})

      {:ok, topology} = Topology.register(topology, "parent", parent_pid)
      {:ok, topology} = Topology.register(topology, "child1", child1_pid, parent_id: "parent")
      {:ok, topology} = Topology.register(topology, "child2", child2_pid, parent_id: "parent")

      {:ok, topology} =
        Topology.register(topology, "grandchild", grandchild_pid, parent_id: "child1")

      states = Topology.get_descendant_states(topology, "parent")
      assert states["child1"] == %{role: "child1"}
      assert states["child2"] == %{role: "child2"}
      assert states["grandchild"] == %{role: "grandchild"}
      # Parent itself is not included
      refute Map.has_key?(states, "parent")
    end
  end

  describe "to_tree/2" do
    test "returns empty list for empty topology" do
      topology = Topology.new()
      assert Topology.to_tree(topology) == []
    end

    test "returns forest from all root processes" do
      topology = Topology.new()
      {:ok, root1_pid} = TestGenServer.start_link(%{name: "root1"})
      {:ok, root2_pid} = TestGenServer.start_link(%{name: "root2"})

      {:ok, topology} = Topology.register(topology, "root1", root1_pid)
      {:ok, topology} = Topology.register(topology, "root2", root2_pid)

      tree = Topology.to_tree(topology)
      assert length(tree) == 2

      # Each root should be a tree node
      root_names = Enum.map(tree, fn node -> node.process.id end)
      assert "root1" in root_names
      assert "root2" in root_names
    end

    test "returns tree from specific process" do
      topology = Topology.new()
      {:ok, parent_pid} = TestGenServer.start_link(%{role: "parent"})
      {:ok, child_pid} = TestGenServer.start_link(%{role: "child"})

      {:ok, topology} = Topology.register(topology, "parent", parent_pid)
      {:ok, topology} = Topology.register(topology, "child", child_pid, parent_id: "parent")

      tree = Topology.to_tree(topology, "parent")
      assert [parent_node] = tree
      assert parent_node.process.id == "parent"
      assert parent_node.state == %{role: "parent"}
      assert [child_node] = parent_node.children
      assert child_node.process.id == "child"
    end

    test "returns empty list for nonexistent process" do
      topology = Topology.new()
      assert Topology.to_tree(topology, "nonexistent") == []
    end

    test "handles complex hierarchy" do
      topology = Topology.new()
      {:ok, root_pid} = TestGenServer.start_link(%{})
      {:ok, child1_pid} = TestGenServer.start_link(%{})
      {:ok, child2_pid} = TestGenServer.start_link(%{})
      {:ok, grandchild_pid} = TestGenServer.start_link(%{})

      {:ok, topology} = Topology.register(topology, "root", root_pid)
      {:ok, topology} = Topology.register(topology, "child1", child1_pid, parent_id: "root")
      {:ok, topology} = Topology.register(topology, "child2", child2_pid, parent_id: "root")

      {:ok, topology} =
        Topology.register(topology, "grandchild", grandchild_pid, parent_id: "child1")

      tree = Topology.to_tree(topology, "root")
      assert [root_node] = tree
      assert length(root_node.children) == 2

      child1_node = Enum.find(root_node.children, fn node -> node.process.id == "child1" end)
      assert [grandchild_node] = child1_node.children
      assert grandchild_node.process.id == "grandchild"
    end
  end

  describe "print/2" do
    @tag :capture_log
    test "prints without error" do
      topology = Topology.new()
      {:ok, pid} = TestGenServer.start_link(%{})
      {:ok, topology} = Topology.register(topology, "test", pid, name: "Test Process")

      # Should not raise any errors
      assert :ok = Topology.print(topology)
      assert :ok = Topology.print(topology, "test")
    end
  end

  describe "count/1" do
    test "returns 0 for empty topology" do
      topology = Topology.new()
      assert Topology.count(topology) == 0
    end

    test "returns correct count" do
      topology = Topology.new()
      {:ok, pid1} = TestGenServer.start_link(%{})
      {:ok, pid2} = TestGenServer.start_link(%{})

      {:ok, topology} = Topology.register(topology, "proc1", pid1)
      assert Topology.count(topology) == 1

      {:ok, topology} = Topology.register(topology, "proc2", pid2)
      assert Topology.count(topology) == 2
    end
  end

  describe "update_metadata/3" do
    test "updates metadata for existing process" do
      topology = Topology.new()
      {:ok, pid} = TestGenServer.start_link(%{})

      {:ok, topology} = Topology.register(topology, "proc1", pid, metadata: %{type: "worker"})

      new_metadata = %{priority: :high, status: :active}
      assert {:ok, updated_topology} = Topology.update_metadata(topology, "proc1", new_metadata)

      process = updated_topology.processes["proc1"]
      assert process.metadata == %{type: "worker", priority: :high, status: :active}
    end

    test "returns error for nonexistent process" do
      topology = Topology.new()
      assert {:error, :not_found} = Topology.update_metadata(topology, "nonexistent", %{})
    end

    test "merges with existing metadata" do
      topology = Topology.new()
      {:ok, pid} = TestGenServer.start_link(%{})

      initial_metadata = %{type: "worker", version: 1}
      {:ok, topology} = Topology.register(topology, "proc1", pid, metadata: initial_metadata)

      update_metadata = %{version: 2, status: :active}
      {:ok, updated_topology} = Topology.update_metadata(topology, "proc1", update_metadata)

      process = updated_topology.processes["proc1"]
      expected_metadata = %{type: "worker", version: 2, status: :active}
      assert process.metadata == expected_metadata
    end
  end

  describe "ProcessNode struct" do
    test "has default values" do
      now = DateTime.utc_now()
      process = %ProcessNode{id: "test", pid: self(), registered_at: now}

      assert process.id == "test"
      assert process.pid == self()
      assert process.name == nil
      assert process.metadata == %{}
      assert process.parent_id == nil
      assert MapSet.size(process.child_ids) == 0
      assert process.registered_at == now
    end

    test "registered_at is set during topology registration" do
      topology = Topology.new()
      {:ok, topology} = Topology.register(topology, "test", self())

      process = topology.processes["test"]

      # Verify the timestamp is recent (within last 5 seconds)
      now = DateTime.utc_now()
      time_diff_seconds = DateTime.diff(now, process.registered_at, :second)
      assert time_diff_seconds >= 0
      assert time_diff_seconds <= 5
    end
  end

  describe "complex scenarios and edge cases" do
    test "handles large hierarchy efficiently" do
      topology = Topology.new()

      # Create a tree with 100 processes
      {:ok, root_pid} = TestGenServer.start_link(%{})
      {:ok, topology} = Topology.register(topology, "root", root_pid)

      topology =
        Enum.reduce(1..99, topology, fn i, acc ->
          {:ok, pid} = TestGenServer.start_link(%{id: i})
          parent_id = if i <= 10, do: "root", else: "child#{div(i, 10)}"
          {:ok, updated} = Topology.register(acc, "child#{i}", pid, parent_id: parent_id)
          updated
        end)

      assert Topology.count(topology) == 100
      descendants = Topology.list_descendants(topology, "root")
      assert length(descendants) == 99
    end

    test "concurrent operations are safe" do
      topology = Topology.new()
      {:ok, root_pid} = TestGenServer.start_link(%{})
      {:ok, topology} = Topology.register(topology, "root", root_pid)

      # Spawn multiple processes to perform concurrent operations
      tasks =
        for i <- 1..10 do
          Task.async(fn ->
            {:ok, pid} = TestGenServer.start_link(%{id: i})
            Topology.register(topology, "child#{i}", pid, parent_id: "root")
          end)
        end

      results = Task.await_many(tasks)
      successful_results = Enum.filter(results, &match?({:ok, _}, &1))

      # All should succeed (though they operate on different topology copies)
      assert length(successful_results) == 10
    end
  end
end
