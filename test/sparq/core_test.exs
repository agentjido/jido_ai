defmodule Sparq.CoreTest do
  use ExUnit.Case, async: true
  alias Sparq.{Core, Context}

  describe "execute/2" do
    test "executes single command" do
      assert {:ok, 42, %Context{} = ctx} = Core.execute(42)
      assert ctx.execution_time_ns > 0
      assert ctx.status == :halted
    end

    test "executes list of commands" do
      commands = [1, 2, 3]
      assert {:ok, 3, %Context{} = ctx} = Core.execute(commands)
      # Returns last value
      assert ctx.execution_time_ns > 0
      assert ctx.status == :halted
    end

    test "initializes new context with root frame" do
      assert {:ok, _, ctx} = Core.execute([])
      assert ctx.current_frame != nil
      assert %{type: :root} = ctx.current_frame
    end

    test "tracks execution timing" do
      assert {:ok, _, ctx} = Core.execute([])
      assert ctx.start_time != nil
      assert ctx.end_time != nil
      assert ctx.execution_time_ns > 0
    end

    test "preserves custom context options" do
      opts = [debug_mode: true, step_mode: true]
      assert {:ok, _, ctx} = Core.execute([], opts)
      assert ctx.debug_mode == true
      assert ctx.step_mode == true
    end

    test "handles block nodes" do
      block = {:block, [], [1, 2, 3]}
      assert {:ok, 3, _ctx} = Core.execute(block)
    end

    test "handles errors" do
      bad_command = {:bad, [], []}
      assert {:error, error, ctx} = Core.execute(bad_command)
      assert error != nil
      assert ctx.status == :error
    end
  end

  describe "execute_args/2" do
    test "evaluates list of arguments" do
      context = Context.new()
      {results, _ctx} = Core.execute_args([1, 2, 3], context)
      assert results == [1, 2, 3]
    end

    test "maintains execution context" do
      context = Context.new(debug_mode: true)
      {_results, new_ctx} = Core.execute_args([], context)
      assert new_ctx.debug_mode == true
    end
  end
end
