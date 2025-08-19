defmodule Jido.HTN.Planner.PerformanceTest do
  use ExUnit.Case, async: true
  alias Jido.HTN
  alias Jido.HTN.Domain
  alias Jido.HTN.{CompoundTask, PrimitiveTask, Method}

  @moduletag :performance

  defmodule TestAction do
    @moduledoc false
    def run(_, _, _), do: {:ok, %{}}
  end

  describe "performance with complex domains" do
    test "handles large number of tasks efficiently" do
      domain = create_complex_domain(100, 100)
      {_time, {:ok, plan, _mtr}} = :timer.tc(fn -> HTN.plan(domain, %{}) end)

      assert is_list(plan)
      assert length(plan) > 0
    end

    test "handles deeply nested task hierarchies" do
      domain = create_deeply_nested_domain(10)
      {_time, {:ok, plan, _mtr}} = :timer.tc(fn -> HTN.plan(domain, %{}) end)

      assert is_list(plan)
      assert length(plan) > 0
    end

    test "handles many method alternatives efficiently" do
      domain = create_many_alternatives_domain(20)
      {_time, {:ok, plan, _mtr}} = :timer.tc(fn -> HTN.plan(domain, %{}) end)

      assert is_list(plan)
      assert length(plan) > 0
    end
  end

  # Helper functions

  defp create_complex_domain(num_compound_tasks, num_primitive_tasks) do
    # Create primitive tasks
    primitive_tasks =
      for i <- 1..num_primitive_tasks do
        {"primitive_#{i}",
         %PrimitiveTask{
           name: "primitive_#{i}",
           task: {TestAction, []},
           preconditions: [],
           effects: [],
           expected_effects: [],
           cost: nil,
           duration: nil,
           scheduling_constraints: nil,
           background: false
         }}
      end

    # Create compound tasks
    compound_tasks =
      for i <- 1..num_compound_tasks do
        {"compound_#{i}",
         %CompoundTask{
           name: "compound_#{i}",
           methods:
             for j <- 1..5 do
               %Method{
                 name: "method_#{j}",
                 priority: nil,
                 conditions: [],
                 subtasks: ["primitive_#{:rand.uniform(num_primitive_tasks)}"],
                 ordering: []
               }
             end
         }}
      end

    # Create domain
    %Domain{
      name: "Complex Domain",
      tasks: Map.new(primitive_tasks ++ compound_tasks),
      allowed_workflows: %{"TestAction" => TestAction},
      callbacks: %{},
      root_tasks: MapSet.new(["compound_1"])
    }
  end

  defp create_deeply_nested_domain(depth) do
    # Create primitive tasks
    primitive_tasks =
      for i <- 1..depth do
        {"primitive_#{i}",
         %PrimitiveTask{
           name: "primitive_#{i}",
           task: {TestAction, []},
           preconditions: [],
           effects: [],
           expected_effects: [],
           cost: nil,
           duration: nil,
           scheduling_constraints: nil,
           background: false
         }}
      end

    # Create compound tasks that form a chain
    compound_tasks =
      for i <- 1..depth do
        next_task = if i == depth, do: "primitive_#{i}", else: "compound_#{i + 1}"

        {"compound_#{i}",
         %CompoundTask{
           name: "compound_#{i}",
           methods: [
             %Method{
               name: "method_#{i}",
               priority: nil,
               conditions: [],
               subtasks: [next_task],
               ordering: []
             }
           ]
         }}
      end

    # Create domain
    %Domain{
      name: "Deeply Nested Domain",
      tasks: Map.new(primitive_tasks ++ compound_tasks),
      allowed_workflows: %{"TestAction" => TestAction},
      callbacks: %{},
      root_tasks: MapSet.new(["compound_1"])
    }
  end

  defp create_many_alternatives_domain(num_alternatives) do
    # Create primitive tasks
    primitive_tasks =
      for i <- 1..num_alternatives do
        {"primitive_#{i}",
         %PrimitiveTask{
           name: "primitive_#{i}",
           task: {TestAction, []},
           preconditions: [],
           effects: [],
           expected_effects: [],
           cost: nil,
           duration: nil,
           scheduling_constraints: nil,
           background: false
         }}
      end

    # Create a compound task with many methods
    compound_tasks = [
      {"compound_1",
       %CompoundTask{
         name: "compound_1",
         methods:
           for i <- 1..num_alternatives do
             %Method{
               name: "method_#{i}",
               priority: nil,
               conditions: [],
               subtasks: ["primitive_#{i}"],
               ordering: []
             }
           end
       }}
    ]

    # Create domain
    %Domain{
      name: "Many Alternatives Domain",
      tasks: Map.new(primitive_tasks ++ compound_tasks),
      allowed_workflows: %{"TestAction" => TestAction},
      callbacks: %{},
      root_tasks: MapSet.new(["compound_1"])
    }
  end
end
