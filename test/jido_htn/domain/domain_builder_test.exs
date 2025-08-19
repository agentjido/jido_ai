defmodule JidoTest.HTN.Domain.BuilderTest do
  use ExUnit.Case, async: true

  alias Jido.HTN.Domain
  @moduletag :capture_log

  defmodule TestAction do
    @moduledoc false
    def run(_, _, _), do: {:ok, %{}}
  end

  describe "root/2" do
    test "marks a task as a root task" do
      {:ok, domain} =
        "Test Domain"
        |> Domain.new()
        |> Domain.compound("task1", methods: [%{subtasks: ["subtask1"]}])
        |> Domain.primitive("subtask1", {TestAction, []})
        |> Domain.root("task1")
        |> Domain.allow("TestAction", TestAction)
        |> Domain.build()

      assert MapSet.member?(domain.root_tasks, "task1")
    end

    test "can mark multiple tasks as root tasks" do
      {:ok, domain} =
        "Test Domain"
        |> Domain.new()
        |> Domain.compound("task1", methods: [%{subtasks: ["subtask1"]}])
        |> Domain.compound("task2", methods: [%{subtasks: ["subtask2"]}])
        |> Domain.primitive("subtask1", {TestAction, []})
        |> Domain.primitive("subtask2", {TestAction, []})
        |> Domain.root("task1")
        |> Domain.root("task2")
        |> Domain.allow("TestAction", TestAction)
        |> Domain.build()

      assert MapSet.member?(domain.root_tasks, "task1")
      assert MapSet.member?(domain.root_tasks, "task2")
    end

    test "raises error when marking non-existent task as root" do
      assert_raise ArgumentError, "Cannot mark 'nonexistent' as root: task not found", fn ->
        "Test Domain"
        |> Domain.new()
        |> Domain.root("nonexistent")
        |> Domain.build()
      end
    end

    test "raises error when marking primitive task as root" do
      assert_raise ArgumentError, "Cannot mark 'task1' as root: must be a compound task", fn ->
        "Test Domain"
        |> Domain.new()
        |> Domain.primitive("task1", {TestAction, []})
        |> Domain.root("task1")
        |> Domain.build()
      end
    end
  end
end
