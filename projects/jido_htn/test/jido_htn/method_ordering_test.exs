defmodule JidoTest.HTN.MethodOrderingTest do
  use ExUnit.Case, async: true
  alias Jido.HTN
  alias Jido.HTN.Domain

  @moduletag :capture_log

  defmodule TestAction do
    @moduledoc false
    def run(_, _, _), do: {:ok, %{}}
  end

  defmodule AnotherTestAction do
    @moduledoc false
    def run(_, _, _), do: {:ok, %{}}
  end

  defmodule ThirdTestAction do
    @moduledoc false
    def run(_, _, _), do: {:ok, %{}}
  end

  describe "method ordering" do
    test "respects ordering constraints between subtasks" do
      # Create a domain with a method that has ordering constraints
      {:ok, domain} =
        "Test Domain"
        |> Domain.new()
        |> Domain.compound("root",
          methods: [
            %{
              subtasks: ["task1", "task2", "task3"],
              ordering: [
                # task2 must come before task3
                {"task2", "task3"},
                # task1 must come before task3
                {"task1", "task3"}
              ]
            }
          ]
        )
        |> Domain.primitive("task1", {TestAction, []})
        |> Domain.primitive("task2", {AnotherTestAction, []})
        |> Domain.primitive("task3", {ThirdTestAction, []})
        |> Domain.allow("TestAction", TestAction)
        |> Domain.allow("AnotherTestAction", AnotherTestAction)
        |> Domain.allow("ThirdTestAction", ThirdTestAction)
        |> Domain.build()

      # Plan should respect the ordering constraints
      # task3 must come after both task1 and task2
      assert {:ok, plan, _mtr} = HTN.plan(domain, %{})
      assert length(plan) == 3

      # Extract just the modules to check ordering
      modules = Enum.map(plan, fn {module, _} -> module end)

      # Find positions of each task in the plan
      task1_pos = Enum.find_index(modules, &(&1 == TestAction))
      task2_pos = Enum.find_index(modules, &(&1 == AnotherTestAction))
      task3_pos = Enum.find_index(modules, &(&1 == ThirdTestAction))

      # Verify task3 comes after both task1 and task2
      assert task3_pos > task1_pos
      assert task3_pos > task2_pos
    end

    test "validates ordering constraints reference valid subtasks" do
      # This should fail validation because task4 is not in subtasks
      assert_raise ArgumentError, ~r/Invalid ordering constraint/, fn ->
        "Test Domain"
        |> Domain.new()
        |> Domain.compound("root",
          methods: [
            %{
              subtasks: ["task1", "task2", "task3"],
              # task4 doesn't exist
              ordering: [{"task1", "task4"}]
            }
          ]
        )
        |> Domain.primitive("task1", {TestAction, []})
        |> Domain.primitive("task2", {AnotherTestAction, []})
        |> Domain.primitive("task3", {ThirdTestAction, []})
        |> Domain.allow("TestAction", TestAction)
        |> Domain.build()
      end
    end

    test "detects cycles in ordering constraints" do
      # This should fail validation because of cyclic dependencies
      assert_raise ArgumentError, ~r/Cyclic dependency/, fn ->
        "Test Domain"
        |> Domain.new()
        |> Domain.compound("root",
          methods: [
            %{
              subtasks: ["task1", "task2", "task3"],
              ordering: [
                {"task1", "task2"},
                {"task2", "task3"},
                # Creates a cycle
                {"task3", "task1"}
              ]
            }
          ]
        )
        |> Domain.primitive("task1", {TestAction, []})
        |> Domain.primitive("task2", {AnotherTestAction, []})
        |> Domain.primitive("task3", {ThirdTestAction, []})
        |> Domain.allow("TestAction", TestAction)
        |> Domain.build()
      end
    end
  end
end
