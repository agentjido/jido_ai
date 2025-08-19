defmodule TestAction do
  @moduledoc false
  def run(_, _, _), do: {:ok, %{}}
end

defmodule Jido.HTN.SerializerTest do
  use ExUnit.Case
  alias Jido.HTN.{Domain, CompoundTask, PrimitiveTask, Method, Domain.Serializer}

  describe "domain serialization" do
    test "successfully serializes and deserializes a complex domain" do
      # Create a test domain with various task types and references
      domain = create_test_domain()

      # Serialize the domain
      serialized = Serializer.serialize(domain)

      # Verify the serialized string contains expected content
      assert serialized =~ "test_domain"
      assert serialized =~ "root_task"
      assert serialized =~ "subtask1"
      assert serialized =~ "subtask2"
      assert serialized =~ "name"

      # Deserialize the domain
      {:ok, deserialized_domain} = Serializer.deserialize(serialized)

      # Verify the deserialized domain matches the original
      assert deserialized_domain.name == domain.name
      assert deserialized_domain.root_tasks == domain.root_tasks
      assert map_size(deserialized_domain.tasks) == map_size(domain.tasks)
      assert map_size(deserialized_domain.allowed_workflows) == map_size(domain.allowed_workflows)
      assert map_size(deserialized_domain.callbacks) == map_size(domain.callbacks)

      # Verify task structure and references
      verify_task_structure(deserialized_domain)
    end

    test "handles primitive tasks with cost and duration" do
      domain = create_domain_with_cost_and_duration()

      # Serialize and deserialize
      serialized = Serializer.serialize(domain)
      {:ok, deserialized_domain} = Serializer.deserialize(serialized)

      # Verify cost and duration are preserved
      task = Map.get(deserialized_domain.tasks, "costly_task")
      assert task.cost == 10
      assert task.duration == 5
    end

    test "handles function references in callbacks" do
      domain = create_domain_with_callbacks()

      # Serialize and deserialize
      serialized = Serializer.serialize(domain)
      {:ok, deserialized_domain} = Serializer.deserialize(serialized)

      # Verify callback functions are preserved
      assert Map.has_key?(deserialized_domain.callbacks, "on_start")
      assert Map.has_key?(deserialized_domain.callbacks, "on_complete")
    end
  end

  # Helper functions

  defp create_test_domain do
    %Domain{
      name: "test_domain",
      tasks: %{
        "root_task" => %CompoundTask{
          name: "root_task",
          methods: [
            %Method{
              name: "method1",
              priority: 1,
              conditions: [
                fn state -> Map.get(state, :condition1) end,
                fn state -> Map.get(state, :condition2) end
              ],
              subtasks: ["subtask1", "subtask2"],
              ordering: [{"subtask1", "subtask2"}]
            }
          ]
        },
        "subtask1" => %PrimitiveTask{
          name: "subtask1",
          task: {TestAction, []},
          preconditions: [fn state -> Map.get(state, :precondition1) end],
          effects: [fn state -> Map.put(state, :effect1, true) end],
          expected_effects: [fn state -> Map.put(state, :expected1, true) end],
          cost: 1,
          duration: 1
        },
        "subtask2" => %PrimitiveTask{
          name: "subtask2",
          task: {TestAction, []},
          preconditions: [fn state -> Map.get(state, :precondition2) end],
          effects: [fn state -> Map.put(state, :effect2, true) end],
          expected_effects: [fn state -> Map.put(state, :expected2, true) end],
          cost: 2,
          duration: 2
        }
      },
      allowed_workflows: %{"TestAction" => TestAction},
      callbacks: %{
        "on_start" => fn domain -> {:ok, domain} end,
        "on_complete" => fn domain -> {:ok, domain} end
      },
      root_tasks: MapSet.new(["root_task"])
    }
  end

  defp create_domain_with_cost_and_duration do
    %Domain{
      name: "cost_domain",
      tasks: %{
        "costly_task" => %PrimitiveTask{
          name: "costly_task",
          task: {TestAction, []},
          preconditions: [],
          effects: [],
          expected_effects: [],
          cost: 10,
          duration: 5
        }
      },
      allowed_workflows: %{"TestAction" => TestAction},
      callbacks: %{},
      root_tasks: MapSet.new(["costly_task"])
    }
  end

  defp create_domain_with_callbacks do
    %Domain{
      name: "callback_domain",
      tasks: %{
        "simple_task" => %PrimitiveTask{
          name: "simple_task",
          task: {TestAction, []},
          preconditions: [],
          effects: [],
          expected_effects: [],
          cost: 1,
          duration: 1
        }
      },
      allowed_workflows: %{"TestAction" => TestAction},
      callbacks: %{
        "on_start" => fn domain -> {:ok, domain} end,
        "on_complete" => fn domain -> {:ok, domain} end
      },
      root_tasks: MapSet.new(["simple_task"])
    }
  end

  defp verify_task_structure(domain) do
    # Verify root task exists and has correct structure
    root_task = Map.get(domain.tasks, "root_task")
    assert %CompoundTask{} = root_task
    assert length(root_task.methods) == 1
    assert length(List.first(root_task.methods).subtasks) == 2

    # Verify subtasks exist and have correct structure
    subtask1 = Map.get(domain.tasks, "subtask1")
    assert %PrimitiveTask{} = subtask1
    assert subtask1.cost == 1
    assert subtask1.duration == 1
    assert length(subtask1.preconditions) == 1
    assert length(subtask1.effects) == 1
    assert length(subtask1.expected_effects) == 1

    subtask2 = Map.get(domain.tasks, "subtask2")
    assert %PrimitiveTask{} = subtask2
    assert subtask2.cost == 2
    assert subtask2.duration == 2
    assert length(subtask2.preconditions) == 1
    assert length(subtask2.effects) == 1
    assert length(subtask2.expected_effects) == 1
  end
end
