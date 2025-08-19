defmodule Jido.HTN.Domain.CloneHelpersTest do
  use ExUnit.Case
  alias Jido.HTN.{Domain, CompoundTask, PrimitiveTask, Method, Domain.CloneHelpers}

  describe "domain cloning" do
    @tag :skip
    test "creates a deep copy of a domain" do
      # Create a test domain
      domain = create_test_domain()

      # Clone the domain
      cloned_domain = CloneHelpers.clone(domain)

      # Verify the clone is a separate instance
      refute cloned_domain === domain

      # Verify all fields are copied correctly
      assert cloned_domain.name == domain.name
      assert cloned_domain.allowed_workflows == domain.allowed_workflows
      assert cloned_domain.root_tasks == domain.root_tasks

      # Verify tasks are cloned
      assert length(Map.keys(cloned_domain.tasks)) == length(Map.keys(domain.tasks))

      # Verify task references are maintained
      verify_task_references(cloned_domain)
    end
  end

  describe "domain merging" do
    test "merges domains without conflicts" do
      domain1 = create_test_domain()
      domain2 = create_another_test_domain()

      merged_domain = CloneHelpers.merge(domain1, domain2)

      # Verify merged domain contains all tasks
      assert length(Map.keys(merged_domain.tasks)) ==
               length(Map.keys(domain1.tasks)) + length(Map.keys(domain2.tasks))

      # Verify task references are maintained
      verify_task_references(merged_domain)
    end

    @tag :skip
    test "handles task name conflicts during merge" do
      domain1 = create_test_domain()
      domain2 = create_conflicting_test_domain()

      merged_domain = CloneHelpers.merge(domain1, domain2)

      # Verify all tasks are present
      assert length(Map.keys(merged_domain.tasks)) ==
               length(Map.keys(domain1.tasks)) + length(Map.keys(domain2.tasks))

      # Verify conflicting tasks are renamed
      assert Map.has_key?(merged_domain.tasks, "conflicting_task")
      assert Map.has_key?(merged_domain.tasks, "conflicting_task_from_compoundtask")

      # Verify task references are maintained
      verify_task_references(merged_domain)
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
              conditions: [],
              subtasks: ["subtask1", "subtask2"],
              ordering: [{"subtask1", "subtask2"}]
            }
          ]
        },
        "subtask1" => %PrimitiveTask{
          name: "subtask1",
          task: fn -> :ok end,
          preconditions: [],
          effects: [],
          expected_effects: [],
          cost: 1,
          duration: 1
        },
        "subtask2" => %PrimitiveTask{
          name: "subtask2",
          task: fn -> :ok end,
          preconditions: [],
          effects: [],
          expected_effects: [],
          cost: 1,
          duration: 1
        }
      },
      allowed_workflows: %{},
      callbacks: %{},
      root_tasks: MapSet.new(["root_task"])
    }
  end

  defp create_another_test_domain do
    %Domain{
      name: "another_domain",
      tasks: %{
        "another_root" => %CompoundTask{
          name: "another_root",
          methods: [
            %Method{
              name: "method1",
              priority: 1,
              conditions: [],
              subtasks: ["another_subtask"],
              ordering: []
            }
          ]
        },
        "another_subtask" => %PrimitiveTask{
          name: "another_subtask",
          task: fn -> :ok end,
          preconditions: [],
          effects: [],
          expected_effects: [],
          cost: 1,
          duration: 1
        }
      },
      allowed_workflows: %{},
      callbacks: %{},
      root_tasks: MapSet.new(["another_root"])
    }
  end

  defp create_conflicting_test_domain do
    %Domain{
      name: "conflicting_domain",
      tasks: %{
        "conflicting_task" => %CompoundTask{
          name: "conflicting_task",
          methods: [
            %Method{
              name: "method1",
              priority: 1,
              conditions: [],
              subtasks: ["conflicting_subtask"],
              ordering: []
            }
          ]
        },
        "conflicting_subtask" => %PrimitiveTask{
          name: "conflicting_subtask",
          task: fn -> :ok end,
          preconditions: [],
          effects: [],
          expected_effects: [],
          cost: 1,
          duration: 1
        }
      },
      allowed_workflows: %{},
      callbacks: %{},
      root_tasks: MapSet.new(["conflicting_task"])
    }
  end

  defp verify_task_references(domain) do
    Enum.each(domain.tasks, fn {_name, task} ->
      case task do
        %CompoundTask{} ->
          Enum.each(task.methods, fn method ->
            # Verify all subtasks exist
            Enum.each(method.subtasks, fn subtask ->
              assert Map.has_key?(domain.tasks, subtask)
            end)

            # Verify all ordering constraints reference existing tasks
            Enum.each(method.ordering, fn {before, after_task} ->
              assert Map.has_key?(domain.tasks, before)
              assert Map.has_key?(domain.tasks, after_task)
            end)
          end)

        %PrimitiveTask{} ->
          :ok
      end
    end)
  end
end
