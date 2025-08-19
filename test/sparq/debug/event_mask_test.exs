defmodule Sparq.Debug.EventMaskTest do
  use ExUnit.Case, async: true
  alias Sparq.Debug.EventMask

  describe "predefined masks" do
    test "all/0 enables all events" do
      mask = EventMask.all()
      assert EventMask.has_event?(mask, :frame_entry)
      assert EventMask.has_event?(mask, :frame_exit)
      assert EventMask.has_event?(mask, :variable_read)
      assert EventMask.has_event?(mask, :variable_write)
      assert EventMask.has_event?(mask, :error)
      assert EventMask.has_event?(mask, :step_complete)
      assert EventMask.has_event?(mask, :module_load)
      assert EventMask.has_event?(mask, :module_unload)
      assert EventMask.has_event?(mask, :function_call)
      assert EventMask.has_event?(mask, :function_return)
      assert EventMask.has_event?(mask, :breakpoint_hit)
    end

    test "none/0 disables all events" do
      mask = EventMask.none()
      refute EventMask.has_event?(mask, :frame_entry)
      refute EventMask.has_event?(mask, :frame_exit)
      refute EventMask.has_event?(mask, :variable_read)
      refute EventMask.has_event?(mask, :variable_write)
      refute EventMask.has_event?(mask, :error)
      refute EventMask.has_event?(mask, :step_complete)
      refute EventMask.has_event?(mask, :module_load)
      refute EventMask.has_event?(mask, :module_unload)
      refute EventMask.has_event?(mask, :function_call)
      refute EventMask.has_event?(mask, :function_return)
      refute EventMask.has_event?(mask, :breakpoint_hit)
    end

    test "frames_only/0 enables only frame events" do
      mask = EventMask.frames_only()
      assert EventMask.has_event?(mask, :frame_entry)
      assert EventMask.has_event?(mask, :frame_exit)
      refute EventMask.has_event?(mask, :variable_read)
      refute EventMask.has_event?(mask, :error)
    end

    test "variables_only/0 enables only variable events" do
      mask = EventMask.variables_only()
      assert EventMask.has_event?(mask, :variable_read)
      assert EventMask.has_event?(mask, :variable_write)
      refute EventMask.has_event?(mask, :frame_entry)
      refute EventMask.has_event?(mask, :error)
    end

    test "errors_only/0 enables only error events" do
      mask = EventMask.errors_only()
      assert EventMask.has_event?(mask, :error)
      refute EventMask.has_event?(mask, :frame_entry)
      refute EventMask.has_event?(mask, :variable_read)
    end

    test "steps_only/0 enables only step events" do
      mask = EventMask.steps_only()
      assert EventMask.has_event?(mask, :step_complete)
      refute EventMask.has_event?(mask, :frame_entry)
      refute EventMask.has_event?(mask, :error)
    end

    test "modules_only/0 enables only module events" do
      mask = EventMask.modules_only()
      assert EventMask.has_event?(mask, :module_load)
      assert EventMask.has_event?(mask, :module_unload)
      refute EventMask.has_event?(mask, :frame_entry)
      refute EventMask.has_event?(mask, :error)
    end

    test "functions_only/0 enables only function events" do
      mask = EventMask.functions_only()
      assert EventMask.has_event?(mask, :function_call)
      assert EventMask.has_event?(mask, :function_return)
      refute EventMask.has_event?(mask, :frame_entry)
      refute EventMask.has_event?(mask, :error)
    end

    test "breakpoints_only/0 enables only breakpoint events" do
      mask = EventMask.breakpoints_only()
      assert EventMask.has_event?(mask, :breakpoint_hit)
      refute EventMask.has_event?(mask, :frame_entry)
      refute EventMask.has_event?(mask, :error)
    end
  end

  describe "enable/2" do
    test "enables single event type" do
      mask = EventMask.none()
      mask = EventMask.enable(mask, :frame_entry)
      assert EventMask.has_event?(mask, :frame_entry)
      refute EventMask.has_event?(mask, :error)
    end

    test "enables multiple event types" do
      mask = EventMask.none()
      mask = EventMask.enable(mask, [:frame_entry, :frame_exit, :error])
      assert EventMask.has_event?(mask, :frame_entry)
      assert EventMask.has_event?(mask, :frame_exit)
      assert EventMask.has_event?(mask, :error)
      refute EventMask.has_event?(mask, :variable_read)
    end

    test "preserves existing enabled events" do
      mask = EventMask.frames_only()
      mask = EventMask.enable(mask, :error)
      assert EventMask.has_event?(mask, :frame_entry)
      assert EventMask.has_event?(mask, :frame_exit)
      assert EventMask.has_event?(mask, :error)
    end
  end

  describe "disable/2" do
    test "disables single event type" do
      mask = EventMask.all()
      mask = EventMask.disable(mask, :frame_entry)
      refute EventMask.has_event?(mask, :frame_entry)
      assert EventMask.has_event?(mask, :error)
    end

    test "disables multiple event types" do
      mask = EventMask.all()
      mask = EventMask.disable(mask, [:frame_entry, :frame_exit, :error])
      refute EventMask.has_event?(mask, :frame_entry)
      refute EventMask.has_event?(mask, :frame_exit)
      refute EventMask.has_event?(mask, :error)
      assert EventMask.has_event?(mask, :variable_read)
    end

    test "preserves other disabled events" do
      mask =
        EventMask.all()
        |> EventMask.disable(:variable_read)
        |> EventMask.disable(:error)

      refute EventMask.has_event?(mask, :variable_read)
      refute EventMask.has_event?(mask, :error)
      assert EventMask.has_event?(mask, :frame_entry)
    end
  end
end
