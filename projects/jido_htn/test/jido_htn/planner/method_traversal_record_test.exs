defmodule JidoTest.HTN.Planner.MethodTraversalRecordTest do
  use ExUnit.Case, async: true

  alias Jido.HTN.Domain
  alias Jido.HTN.Planner.TaskDecomposer

  test "method traversal record records method choices during decomposition" do
    # Given a domain with nested compound tasks
    {:ok, domain} =
      "Test Domain"
      |> Domain.new()
      |> Domain.primitive("task1", {TestAction, []})
      |> Domain.primitive("task2", {TestAction, []})
      |> Domain.compound("nested_task",
        methods: [
          %{
            name: "nested_method",
            priority: 1,
            subtasks: ["task1"]
          }
        ]
      )
      |> Domain.compound("root",
        methods: [
          %{
            name: "root_method",
            priority: 1,
            subtasks: ["nested_task", "task2"]
          }
        ]
      )
      |> Domain.allow("TestAction", TestAction)
      |> Domain.build()

    # When we decompose the root task
    {:ok, _plan, _world_state, _mtr, debug_tree} =
      TaskDecomposer.decompose_task(domain, "root", %{}, [], [], 0, true)

    # Then the debug tree should show the method choices
    assert {:compound, "root", true,
            [
              {true, "root_method", [],
               {:compound, "root", true,
                [
                  {:compound, "root", true,
                   [
                     {:compound, "nested_task", true,
                      [
                        {true, "nested_method", [],
                         {:compound, "nested_task", true,
                          [{:compound, "root", true, [{:primitive, "task1", true, []}]}]}}
                      ]},
                     {:primitive, "task2", true, []}
                   ]}
                ]}}
            ]} = debug_tree
  end

  test "method traversal record records method choices when backtracking" do
    # Given a domain with a compound task that has two methods
    # The first method will fail because its preconditions are not met
    # The second method will succeed
    {:ok, domain} =
      "Test Domain"
      |> Domain.new()
      |> Domain.primitive("task1", {TestAction, []})
      |> Domain.compound("root",
        methods: [
          %{
            name: "method1",
            priority: 1,
            subtasks: ["task1"],
            preconditions: ["always_false"]
          },
          %{
            name: "method2",
            priority: 2,
            subtasks: ["task1"]
          }
        ]
      )
      |> Domain.allow("TestAction", TestAction)
      |> Domain.callback("always_false", fn _ -> false end)
      |> Domain.build()

    # When we decompose the root task
    {:ok, _plan, _world_state, _mtr, debug_tree} =
      TaskDecomposer.decompose_task(domain, "root", %{}, [], [], 0, true)

    # Then the debug tree should show both method attempts
    assert {:compound, "root", true,
            [
              {true, "method1", [],
               {:compound, "root", true,
                [{:compound, "root", true, [{:primitive, "task1", true, []}]}]}}
            ]} = debug_tree
  end

  test "planner explores all paths if no current_plan_mtr is provided" do
    {:ok, domain} =
      "Culling Test Domain"
      |> Domain.new()
      |> Domain.primitive("A1", {TestAction, []})
      |> Domain.primitive("B1", {TestAction, []})
      |> Domain.compound("Root",
        methods: [
          %{name: "MethodA", priority: 10, subtasks: ["A1"]},
          %{name: "MethodB", priority: 20, subtasks: ["B1"]}
        ]
      )
      |> Domain.allow("TestAction", TestAction)
      |> Domain.build()

    {:ok, plan, mtr} = Jido.HTN.plan(domain, %{}, root_tasks: ["Root"])
    assert plan == [{TestAction, []}]
    assert mtr.choices == [{"Root", "MethodA", 10}]
  end

  test "planner culls lower priority paths when current_plan_mtr is provided" do
    {:ok, domain} =
      "Culling Test Domain"
      |> Domain.new()
      |> Domain.primitive("A1", {TestAction, []})
      |> Domain.primitive("B1", {TestAction, []})
      |> Domain.compound("Root",
        methods: [
          %{name: "MethodA", priority: 10, subtasks: ["A1"]},
          %{name: "MethodB", priority: 20, subtasks: ["B1"]}
        ]
      )
      |> Domain.allow("TestAction", TestAction)
      |> Domain.build()

    # First, get the MTR for MethodA
    {:ok, _plan, mtr_a} = Jido.HTN.plan(domain, %{}, root_tasks: ["Root"])
    # Now, try to plan with current_plan_mtr set to mtr_a, but only MethodB is available
    domain_b = %{
      domain
      | tasks:
          Map.update!(domain.tasks, "Root", fn task ->
            %{task | methods: [%{name: "MethodB", priority: 20, subtasks: ["B1"]}]}
          end)
    }

    result = Jido.HTN.plan(domain_b, %{}, current_plan_mtr: mtr_a, root_tasks: ["Root"])
    assert match?({:error, _}, result)
  end

  test "planner finds a higher priority path even if current_plan_mtr is provided" do
    {:ok, domain} =
      "Culling Test Domain"
      |> Domain.new()
      |> Domain.primitive("A1", {TestAction, []})
      |> Domain.primitive("B1", {TestAction, []})
      |> Domain.compound("Root",
        methods: [
          %{name: "MethodA", priority: 10, subtasks: ["A1"]},
          %{name: "MethodB", priority: 20, subtasks: ["B1"]}
        ]
      )
      |> Domain.allow("TestAction", TestAction)
      |> Domain.build()

    # First, get the MTR for MethodB (lower priority)
    domain_b = %{
      domain
      | tasks:
          Map.update!(domain.tasks, "Root", fn task ->
            %{
              task
              | methods: [
                  %{name: "MethodB", priority: 20, subtasks: ["B1"], conditions: []},
                  %{name: "MethodA", priority: 10, subtasks: ["A1"], conditions: []}
                ]
            }
          end)
    }

    {:ok, _plan_b, mtr_b} = Jido.HTN.plan(domain_b, %{}, root_tasks: ["Root"])
    # Now, try to plan with current_plan_mtr set to mtr_b, but both methods are available
    {:ok, plan, mtr} = Jido.HTN.plan(domain, %{}, current_plan_mtr: mtr_b, root_tasks: ["Root"])
    assert plan == [{TestAction, []}]
    assert mtr.choices == [{"Root", "MethodA", 10}]
  end
end
