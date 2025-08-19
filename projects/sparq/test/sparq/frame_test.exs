defmodule Sparq.FrameTest do
  use ExUnit.Case, async: true

  alias Sparq.Frame

  describe "new/1" do
    test "creates frame with default values" do
      frame = Frame.new()
      assert frame.type == :block
      assert frame.status == :active
      assert frame.variables == %{}
      assert frame.depth == 0
      assert is_reference(frame.ref)
      assert is_integer(frame.entered_at)
    end

    test "creates frame with custom values" do
      frame = Frame.new(type: :function, name: "test_fn", depth: 1)
      assert frame.type == :function
      assert frame.name == "test_fn"
      assert frame.depth == 1
    end
  end

  describe "add_variable/3" do
    test "adds variable to frame scope" do
      frame = Frame.new()
      frame = Frame.add_variable(frame, "x", 42)
      assert frame.variables == %{"x" => 42}
    end

    test "updates existing variable" do
      frame = Frame.new()
      frame = Frame.add_variable(frame, "x", 42)
      frame = Frame.add_variable(frame, "x", 43)
      assert frame.variables == %{"x" => 43}
    end
  end

  describe "get_variable/2" do
    test "retrieves existing variable" do
      frame = Frame.new() |> Frame.add_variable("x", 42)
      assert Frame.get_variable(frame, "x") == 42
    end

    test "returns nil for non-existent variable" do
      frame = Frame.new()
      assert Frame.get_variable(frame, "x") == nil
    end
  end

  describe "complete_frame/2" do
    test "completes frame with return value" do
      frame = Frame.new()
      frame = Frame.complete_frame(frame, 42)
      assert frame.status == :completed
      assert frame.return_value == 42
      assert is_integer(frame.exited_at)
    end

    test "completes frame without return value" do
      frame = Frame.new()
      frame = Frame.complete_frame(frame)
      assert frame.status == :completed
      assert frame.return_value == nil
      assert is_integer(frame.exited_at)
    end
  end

  describe "to_map/1" do
    test "converts frame to map representation" do
      frame =
        Frame.new(
          type: :function,
          name: "test_fn",
          file: "test.ex",
          line: 42,
          module: Test,
          args: [1, 2]
        )
        |> Frame.add_variable("x", 42)
        |> Frame.complete_frame(100)

      map = Frame.to_map(frame)
      assert map.type == :function
      assert map.name == "test_fn"
      assert map.location.file == "test.ex"
      assert map.location.line == 42
      assert map.location.module == Test
      assert map.variables == %{"x" => 42}
      assert map.args == [1, 2]
      assert map.return_value == 100
      assert map.status == :completed
    end
  end

  describe "get_timing/1" do
    test "returns timing for active frame" do
      frame = Frame.new()
      timing = Frame.get_timing(frame)
      assert is_integer(timing.entered_at)
      refute Map.has_key?(timing, :exited_at)
      refute Map.has_key?(timing, :duration_ns)
    end

    test "returns timing for completed frame" do
      frame = Frame.new() |> Frame.complete_frame(42)
      timing = Frame.get_timing(frame)
      assert is_integer(timing.entered_at)
      assert is_integer(timing.exited_at)
      assert is_integer(timing.duration_ns)
      assert timing.duration_ns >= 0
    end
  end

  describe "get_variables/2" do
    test "returns all variables without filter" do
      frame =
        Frame.new()
        |> Frame.add_variable("x", 1)
        |> Frame.add_variable("y", 2)

      vars = Frame.get_variables(frame)
      assert vars == %{"x" => 1, "y" => 2}
    end

    test "returns filtered variables" do
      frame =
        Frame.new()
        |> Frame.add_variable("x", 1)
        |> Frame.add_variable("y", "two")
        |> Frame.add_variable("z", 3)

      vars = Frame.get_variables(frame, fn _name, value -> is_integer(value) end)
      assert vars == %{"x" => 1, "z" => 3}
    end
  end
end
