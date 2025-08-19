defmodule JidoTest.HTN.MethodTest do
  use ExUnit.Case, async: true

  alias Jido.HTN.Method
  @moduletag :capture_log
  describe "new/1" do
    test "creates a new Method" do
      method =
        Method.new(
          conditions: [fn _ -> true end],
          subtasks: ["subtask1", "subtask2"]
        )

      assert %Method{
               conditions: [_],
               subtasks: ["subtask1", "subtask2"]
             } = method
    end

    test "creates a Method with default values" do
      method = Method.new()
      assert %Method{conditions: [], subtasks: []} = method
    end
  end
end
