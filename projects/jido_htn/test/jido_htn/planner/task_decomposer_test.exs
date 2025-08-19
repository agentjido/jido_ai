defmodule Jido.HTN.Planner.TaskDecomposerTest do
  use ExUnit.Case, async: true
  alias Jido.HTN.{Domain, CompoundTask, PrimitiveTask}
  alias Jido.HTN.Method
  alias Jido.HTN.Planner.TaskDecomposer

  describe "backtracking" do
    test "backtracks to alternative method when subtasks fail" do
      # Create a domain with a compound task that has two methods:
      # 1. First method has subtasks that will fail mid-decomposition
      # 2. Second method has subtasks that will succeed
      {:ok, domain} =
        "Test Domain"
        |> Domain.new()
        |> Domain.compound("root",
          methods: [
            # First method - will fail mid-decomposition
            %{
              name: "method1",
              subtasks: ["task1", "will_fail", "task3"],
              conditions: []
            },
            # Second method - will succeed
            %{
              name: "method2",
              subtasks: ["task1", "task2", "task3"],
              conditions: []
            }
          ]
        )
        |> Domain.primitive("task1", {TestAction, []})
        |> Domain.primitive("will_fail", {TestAction, []}, preconditions: ["always_false"])
        |> Domain.primitive("task2", {TestAction, []})
        |> Domain.primitive("task3", {TestAction, []})
        |> Domain.allow("TestAction", TestAction)
        |> Domain.callback("always_false", fn _ -> false end)
        |> Domain.build()

      # When we decompose the root task
      {:ok, plan, _world_state, _mtr, debug_tree} =
        TaskDecomposer.decompose_task(domain, "root", %{}, [], [], 0, true)

      # Then the plan should contain 3 actions from method2
      assert length(plan) == 3

      # And the debug tree should show method1 failed and method2 succeeded
      assert {:compound, "root", true, debug_methods} = debug_tree

      assert [
               {false, "method1", [], {:empty, "", false, []}},
               {true, "method2", [], {:compound, "root", true, _subtasks}}
             ] = debug_methods
    end
  end

  describe "method priorities" do
    test "tries methods in priority order" do
      # Create a domain with a compound task that has three methods with different priorities
      {:ok, domain} =
        "Test Domain"
        |> Domain.new()
        |> Domain.compound("root",
          methods: [
            # Low priority method (2) - would succeed but shouldn't be tried first
            %{
              name: "low_priority",
              priority: 2,
              subtasks: ["task1"],
              conditions: []
            },
            # Lowest priority method (3) - would succeed but shouldn't be tried first
            %{
              name: "lowest_priority",
              priority: 3,
              subtasks: ["task2"],
              conditions: []
            },
            # Highest priority method (1) - should be tried first and succeed
            %{
              name: "high_priority",
              priority: 1,
              subtasks: ["task3"],
              conditions: []
            }
          ]
        )
        |> Domain.primitive("task1", {TestAction, []})
        |> Domain.primitive("task2", {TestAction, []})
        |> Domain.primitive("task3", {TestAction, []})
        |> Domain.allow("TestAction", TestAction)
        |> Domain.build()

      # When we decompose the root task
      {:ok, plan, _world_state, _mtr, debug_tree} =
        TaskDecomposer.decompose_task(domain, "root", %{}, [], [], 0, true)

      # Then the plan should contain 1 action from the highest priority method
      assert length(plan) == 1

      # And the debug tree should show only the highest priority method was tried
      assert {:compound, "root", true, debug_methods} = debug_tree

      assert [
               {true, "high_priority", [], {:compound, "root", true, _subtasks}}
             ] = debug_methods
    end
  end

  describe "ordering constraints" do
    test "respects ordering constraints in method decomposition" do
      # Create a simple domain with ordered tasks
      domain = %Domain{
        tasks: %{
          "root" => %CompoundTask{
            name: "root",
            methods: [
              %Method{
                subtasks: ["task1", "task2", "task3"],
                ordering: [{"task2", "task3"}, {"task1", "task2"}]
              }
            ]
          },
          "task1" => %PrimitiveTask{name: "task1", task: {TestAction, []}},
          "task2" => %PrimitiveTask{name: "task2", task: {TestAction, []}},
          "task3" => %PrimitiveTask{name: "task3", task: {TestAction, []}}
        },
        allowed_workflows: %{"test" => TestAction}
      }

      {:ok, plan, _, _mtr, _} =
        TaskDecomposer.decompose_task(domain, "root", %{}, [], [], 0, false)

      # Extract just the task names from the plan for easier comparison
      task_names =
        Enum.map(plan, fn {module, _} ->
          module |> to_string |> String.replace("Elixir.", "")
        end)

      # Verify tasks appear in the correct order
      assert task_names == ["TestAction", "TestAction", "TestAction"]

      # Verify the plan length is correct
      assert length(plan) == 3
    end
  end
end
