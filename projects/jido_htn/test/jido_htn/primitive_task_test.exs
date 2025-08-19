defmodule JidoTest.HTN.PrimitiveTaskTest do
  use ExUnit.Case, async: true

  alias Jido.HTN.PrimitiveTask
  @moduletag :capture_log

  defmodule TestModule do
    @moduledoc false
    def run(_, _, _), do: {:ok, %{}}
  end

  describe "new/3" do
    test "creates a new PrimitiveTask" do
      task =
        PrimitiveTask.new(
          "test_task",
          {TestModule, key: :value},
          preconditions: [fn _ -> true end],
          effects: [fn _ -> %{} end],
          expected_effects: [fn _ -> %{} end],
          cost: 10,
          duration: 1000
        )

      assert %PrimitiveTask{
               name: "test_task",
               preconditions: [_],
               task: {TestModule, [key: :value]},
               effects: [_],
               expected_effects: [_],
               cost: 10,
               duration: 1000
             } = task
    end

    test "creates a PrimitiveTask with default values" do
      task = PrimitiveTask.new("test_task", {TestModule, []})

      assert %PrimitiveTask{
               name: "test_task",
               task: {TestModule, []},
               preconditions: [],
               effects: [],
               expected_effects: [],
               cost: nil,
               duration: nil,
               scheduling_constraints: nil
             } = task
    end

    test "accepts any cost and duration values" do
      # Negative values are allowed at the PrimitiveTask level
      # Domain validation will catch invalid values
      task = PrimitiveTask.new("test_task", {TestModule, []}, cost: -1, duration: -1000)
      assert task.cost == -1
      assert task.duration == -1000

      # Zero is allowed
      task = PrimitiveTask.new("test_task", {TestModule, []}, cost: 0, duration: 0)
      assert task.cost == 0
      assert task.duration == 0

      # Positive values are allowed
      task = PrimitiveTask.new("test_task", {TestModule, []}, cost: 100, duration: 5000)
      assert task.cost == 100
      assert task.duration == 5000
    end

    test "accepts scheduling constraints" do
      # Test with earliest start time
      task =
        PrimitiveTask.new(
          "test_task",
          {TestModule, []},
          scheduling_constraints: %{earliest_start_time: 1000}
        )

      assert task.scheduling_constraints == %{earliest_start_time: 1000}

      # Test with latest end time
      task =
        PrimitiveTask.new(
          "test_task",
          {TestModule, []},
          scheduling_constraints: %{latest_end_time: 2000}
        )

      assert task.scheduling_constraints == %{latest_end_time: 2000}

      # Test with both constraints
      task =
        PrimitiveTask.new(
          "test_task",
          {TestModule, []},
          scheduling_constraints: %{earliest_start_time: 1000, latest_end_time: 2000}
        )

      assert task.scheduling_constraints == %{earliest_start_time: 1000, latest_end_time: 2000}
    end
  end
end
