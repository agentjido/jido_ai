defmodule JidoTest.HTN.PlannerTest do
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

  describe "plan/3" do
    test "requires root task by default" do
      # First verify current behavior with single root
      {:ok, domain} =
        "Test Domain"
        |> Domain.new()
        |> Domain.compound("root", methods: [%{subtasks: ["task1"]}])
        |> Domain.primitive("task1", {TestAction, []})
        |> Domain.allow("TestAction", TestAction)
        |> Domain.build()

      assert {:ok, [{TestAction, []}], _mtr} = HTN.plan(domain, %{})

      # Now test with multiple root tasks but no "root" task
      {:ok, domain_multi} =
        "Test Domain"
        |> Domain.new()
        |> Domain.compound("root1", methods: [%{subtasks: ["task1"]}])
        |> Domain.compound("root2", methods: [%{subtasks: ["task2"]}])
        |> Domain.primitive("task1", {TestAction, []})
        |> Domain.primitive("task2", {AnotherTestAction, []})
        |> Domain.allow("TestAction", TestAction)
        |> Domain.allow("AnotherTestAction", AnotherTestAction)
        |> Domain.build()

      # This should fail since there's no "root" task
      assert {:error, "Unknown task: \"root\""} = HTN.plan(domain_multi, %{})
    end

    test "supports multiple root tasks with explicit root list" do
      {:ok, domain} =
        "Test Domain"
        |> Domain.new()
        |> Domain.compound("root1", methods: [%{subtasks: ["task1"]}])
        |> Domain.compound("root2", methods: [%{subtasks: ["task2"]}])
        |> Domain.primitive("task1", {TestAction, []})
        |> Domain.primitive("task2", {AnotherTestAction, []})
        |> Domain.allow("TestAction", TestAction)
        |> Domain.allow("AnotherTestAction", AnotherTestAction)
        |> Domain.build()

      # Should succeed with both tasks executed in order
      assert {:ok, [{AnotherTestAction, []}, {TestAction, []}], _mtr} =
               HTN.plan(domain, %{}, root_tasks: ["root1", "root2"])
    end

    test "validates root_tasks option" do
      {:ok, domain} =
        "Test Domain"
        |> Domain.new()
        |> Domain.compound("root1", methods: [%{subtasks: ["task1"]}])
        |> Domain.primitive("task1", {TestAction, []})
        |> Domain.allow("TestAction", TestAction)
        |> Domain.build()

      # Test invalid root task name
      assert_raise ArgumentError, "Root task 'nonexistent' not found in domain", fn ->
        HTN.plan(domain, %{}, root_tasks: ["nonexistent"])
      end

      # Test non-compound root task
      assert_raise ArgumentError, "Root task 'task1' must be a compound task", fn ->
        HTN.plan(domain, %{}, root_tasks: ["task1"])
      end

      # Test invalid root_tasks type
      assert_raise ArgumentError, ~r/root_tasks must be a list/, fn ->
        HTN.plan(domain, %{}, root_tasks: "root1")
      end
    end
  end
end
