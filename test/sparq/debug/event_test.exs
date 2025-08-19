defmodule Sparq.Debug.EventTest do
  use ExUnit.Case, async: true

  alias Sparq.Debug.Event

  describe "new/3" do
    test "creates event with minimal fields" do
      event = Event.new(:frame_entry)
      assert event.type == :frame_entry
      assert is_integer(event.timestamp)
      assert event.context_ref == nil
      assert event.frame_ref == nil
      assert event.data == %{}
      refute is_nil(event.process_info)
      assert event.process_info.pid == self()
    end

    test "creates event with data" do
      data = %{message: "test"}
      event = Event.new(:error, data)
      assert event.type == :error
      assert event.data == data
    end

    test "creates event with options" do
      context_ref = make_ref()
      frame_ref = make_ref()
      opts = [context_ref: context_ref, frame_ref: frame_ref]
      event = Event.new(:variable_write, %{name: "x", value: 42}, opts)

      assert event.type == :variable_write
      assert event.context_ref == context_ref
      assert event.frame_ref == frame_ref
      assert event.data == %{name: "x", value: 42}
    end

    test "includes process info" do
      event = Event.new(:step_complete)
      assert %{pid: pid, status: status} = event.process_info
      assert pid == self()
      assert is_atom(status)
    end
  end

  describe "format/1" do
    test "formats event with no refs" do
      event = Event.new(:frame_entry, %{name: "test"})
      formatted = Event.format(event)
      # timestamp
      assert formatted =~ ~r/\d{2}:\d{2}:\d{2}\.\d{6}/
      assert formatted =~ "[frame_entry]"
      assert formatted =~ "at unknown"
      assert formatted =~ ~s(name: "test")
    end

    test "formats event with context ref" do
      context_ref = make_ref()
      event = Event.new(:error, %{reason: "test"}, context_ref: context_ref)
      formatted = Event.format(event)
      assert formatted =~ "context:#{inspect(context_ref)}"
      assert formatted =~ ~s(reason: "test")
    end

    test "formats event with frame ref" do
      frame_ref = make_ref()
      event = Event.new(:variable_read, %{name: "x"}, frame_ref: frame_ref)
      formatted = Event.format(event)
      assert formatted =~ "frame:#{inspect(frame_ref)}"
      assert formatted =~ ~s(name: "x")
    end

    test "formats event with both refs" do
      context_ref = make_ref()
      frame_ref = make_ref()
      event = Event.new(:step_complete, %{}, context_ref: context_ref, frame_ref: frame_ref)
      formatted = Event.format(event)
      assert formatted =~ "context:#{inspect(context_ref)}"
      assert formatted =~ "frame:#{inspect(frame_ref)}"
    end

    test "formats event with non-map data" do
      event = %Event{
        type: :test,
        timestamp: System.monotonic_time(:nanosecond),
        data: "test data"
      }

      formatted = Event.format(event)
      assert formatted =~ ~s("test data")
    end
  end
end
