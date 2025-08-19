defmodule Sparq.DebugTest do
  # async: false because we're testing IO
  use ExUnit.Case, async: false
  alias Sparq.{Context, Debug, Error, Frame}
  import ExUnit.CaptureIO
  import ExUnit.CaptureLog

  describe "debug mode" do
    test "enable/disable debug mode" do
      ctx = Context.new()
      assert ctx.debug_mode == false

      ctx = Debug.enable(ctx)
      assert ctx.debug_mode == true

      ctx = Debug.disable(ctx)
      assert ctx.debug_mode == false
    end

    test "enable/disable stepping" do
      ctx = Context.new()
      assert ctx.step_mode == false

      ctx = Debug.enable_stepping(ctx)
      assert ctx.step_mode == true

      ctx = Debug.disable_stepping(ctx)
      assert ctx.step_mode == false
    end
  end

  describe "breakpoint management" do
    test "add/remove/check breakpoints" do
      ctx = Context.new()
      module = MyModule
      line = 42

      ctx = Debug.add_breakpoint(ctx, module, line)
      assert Debug.has_breakpoint?(ctx, module, line)

      ctx = Debug.remove_breakpoint(ctx, module, line)
      refute Debug.has_breakpoint?(ctx, module, line)
    end
  end

  describe "event handling" do
    test "subscribe/unsubscribe" do
      ctx = Context.new()

      ctx = Debug.subscribe(ctx, self())
      assert MapSet.member?(ctx.subscribers, self())

      ctx = Debug.unsubscribe(ctx, self())
      refute MapSet.member?(ctx.subscribers, self())
    end

    test "get/clear events" do
      ctx =
        Context.new()
        |> Debug.enable()
        |> Context.add_event(:frame_entry, "data")

      assert [%{type: :frame_entry}] = Debug.get_events(ctx)

      ctx = Debug.clear_events(ctx)
      assert [] = Debug.get_events(ctx)
    end
  end

  describe "maybe_step/3" do
    test "skips stepping when debug mode is off" do
      ctx = Context.new()
      meta = [module: MyModule, line: 42]

      assert ctx == Debug.maybe_step(ctx, "test", meta)
    end

    test "handles stepping when debug mode is on" do
      ctx =
        Context.new()
        |> Debug.enable()
        |> Debug.enable_stepping()

      meta = [module: MyModule, line: 42]

      output =
        capture_io([input: "c\n"], fn ->
          ctx = Debug.maybe_step(ctx, "test message", meta)
          assert ctx.step_mode == true
        end)

      assert output =~ "test message"
      assert output =~ "MyModule:42"
      assert output =~ "Commands: continue (c)"
    end

    test "handles breakpoint hit" do
      ctx =
        Context.new()
        |> Debug.enable()

      module = MyModule
      line = 42
      meta = [module: module, line: line]

      ctx = Debug.add_breakpoint(ctx, module, line)

      log =
        capture_log(fn ->
          output =
            capture_io([input: "c\n"], fn ->
              ctx = Debug.maybe_step(ctx, "test message", meta)
              assert Debug.has_breakpoint?(ctx, module, line)
              ctx
            end)

          assert output =~ "test message"
          assert output =~ "MyModule:42"
        end)

      assert log =~ "Breakpoint hit at Elixir.MyModule:42"
    end
  end

  describe "debug commands" do
    setup do
      frame =
        Frame.new(type: :function, name: "test_frame")
        |> Frame.add_variable(:x, 42)

      queue =
        :queue.in(frame, :queue.new())

      ctx =
        Context.new()
        |> Debug.enable()
        |> Debug.enable_stepping()
        |> Map.put(:current_frame, frame)
        |> Map.put(:call_stack, queue)

      meta = [module: MyModule, line: 42]
      {:ok, ctx: ctx, meta: meta}
    end

    test "shows variables", %{ctx: ctx, meta: meta} do
      output =
        capture_io([input: "v\nc\n"], fn ->
          Debug.maybe_step(ctx, "test", meta)
        end)

      assert output =~ "x"
      assert output =~ "42"
    end

    test "shows stack trace", %{ctx: ctx, meta: meta} do
      output =
        capture_io([input: "t\nc\n"], fn ->
          Debug.maybe_step(ctx, "test", meta)
        end)

      assert output =~ "test_frame"
    end

    test "shows help", %{ctx: ctx, meta: meta} do
      output =
        capture_io([input: "h\nc\n"], fn ->
          Debug.maybe_step(ctx, "test", meta)
        end)

      assert output =~ "Debug Commands:"
      assert output =~ "c - Continue execution"
      assert output =~ "s - Step to next expression"
    end

    test "quits debug session", %{ctx: ctx, meta: meta} do
      assert_raise Error, "Debugging session terminated by user", fn ->
        capture_io([input: "q\n"], fn ->
          Debug.maybe_step(ctx, "test", meta)
        end)
      end
    end

    test "handles invalid command", %{ctx: ctx, meta: meta} do
      output =
        capture_io([input: "invalid\nc\n"], fn ->
          Debug.maybe_step(ctx, "test", meta)
        end)

      # Should show debug info again
      assert output =~ "test"
    end
  end

  describe "variable and stack inspection" do
    test "get_variables returns empty map for nil frame" do
      ctx = Context.new()
      assert Debug.get_variables(ctx) == %{}
    end

    test "get_variables returns frame variables" do
      frame =
        Frame.new(type: :function, name: "test")
        |> Frame.add_variable(:x, 42)

      ctx =
        Context.new()
        |> Map.put(:current_frame, frame)

      assert Debug.get_variables(ctx) == %{"x" => 42}
    end

    test "get_stack_trace returns stack frames" do
      frame1 = Frame.new(type: :function, name: "frame1")
      frame2 = Frame.new(type: :function, name: "frame2")

      queue =
        :queue.new()
        |> then(&:queue.in(frame1, &1))
        |> then(&:queue.in(frame2, &1))

      ctx =
        Context.new()
        |> Map.put(:call_stack, queue)

      trace = Debug.get_stack_trace(ctx)
      assert length(trace) == 2
      assert hd(trace) =~ "function frame1"
      assert Enum.at(trace, 1) =~ "function frame2"
    end
  end
end
