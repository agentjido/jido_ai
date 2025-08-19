defmodule JidoTest.HTN.CompoundTaskTest do
  use ExUnit.Case, async: true

  alias Jido.HTN.CompoundTask
  alias Jido.HTN.Method
  @moduletag :capture_log
  describe "new/2" do
    test "creates a new CompoundTask" do
      task = CompoundTask.new("test_task")
      assert %CompoundTask{name: "test_task", methods: []} = task
    end

    test "creates a new CompoundTask with methods" do
      method = Method.new(conditions: [fn _ -> true end], subtasks: ["subtask1"])
      task = CompoundTask.new("test_task", [method])
      assert %CompoundTask{name: "test_task", methods: [^method]} = task
    end
  end

  describe "add_method/2" do
    test "adds a method to the CompoundTask" do
      task = CompoundTask.new("test_task")
      method = Method.new(conditions: [fn _ -> true end], subtasks: ["subtask1"])

      updated_task = CompoundTask.add_method(task, method)
      assert length(updated_task.methods) == 1
      assert hd(updated_task.methods) == method
    end
  end
end
