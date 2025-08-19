defmodule Sparq.ContextTest do
  use ExUnit.Case, async: true

  alias Sparq.{Context, Error}
  alias Sparq.Debug.EventMask

  describe "new/1" do
    test "creates context with default values" do
      context = Context.new()
      assert context.status == :ready
      assert is_reference(context.ref)
      assert :queue.is_empty(context.call_stack)
      assert context.current_frame == nil
      assert context.debug_mode == false
      assert context.step_mode == false
    end

    test "creates context with custom values" do
      context = Context.new(debug_mode: true, max_stack_depth: 50)
      assert context.debug_mode == true
      assert context.max_stack_depth == 50
    end
  end

  describe "frame management" do
    test "pushes frame onto empty stack" do
      context = Context.new()
      context = Context.push_frame(context, :block, name: "test")
      assert context.current_frame.type == :block
      assert context.current_frame.name == "test"
      assert length(:queue.to_list(context.call_stack)) == 1
    end

    test "pops frame from stack" do
      context =
        Context.new()
        |> Context.push_frame(:block, name: "frame1")
        |> Context.push_frame(:block, name: "frame2")

      context = Context.pop_frame(context)
      assert context.current_frame.name == "frame1"
      assert length(:queue.to_list(context.call_stack)) == 1
    end

    test "raises error when popping empty stack" do
      context = Context.new()

      assert_raise Error, "Stack underflow", fn ->
        Context.pop_frame(context)
      end
    end

    test "handles stack overflow" do
      context = Context.new(max_stack_depth: 1)
      context = Context.push_frame(context, :block)
      context = Context.push_frame(context, :block)
      assert context.status == :error
    end

    test "updates frame variables" do
      context =
        Context.new()
        |> Context.push_frame(:block, name: "frame1", variables: %{test_var: nil})
        |> Context.push_frame(:block, name: "frame2", variables: %{test_var: nil})

      {:ok, context} = Context.update_variable(context, :test_var, "value")
      assert Context.lookup_variable(context, :test_var) == {:ok, "value"}
    end

    test "maintains variable isolation between frames" do
      {:ok, context} =
        Context.new()
        |> Context.push_frame(:block, name: "frame1", variables: %{test_var: nil})
        |> Context.push_frame(:block, name: "frame2", variables: %{test_var: nil})
        |> Context.update_variable(:test_var, "value")

      # Verify value in current frame
      assert {:ok, "value"} = Context.lookup_variable(context, :test_var)

      # Pop frame and verify variable is undefined in parent frame
      context = Context.pop_frame(context)
      assert {:error, :undefined_variable} = Context.lookup_variable(context, :test_var)
    end
  end

  describe "execution timing" do
    test "tracks execution timing" do
      context =
        Context.new()
        |> Context.start_execution()

      assert context.status == :running
      assert is_integer(context.start_time)

      context = Context.halt_execution(context)
      assert context.status == :halted
      assert is_integer(context.end_time)
      assert is_integer(context.execution_time_ns)
    end
  end

  describe "error handling" do
    test "adds error to context" do
      context = Context.new()
      error = Error.new(:runtime_error, "test error")
      context = Context.add_error(context, error)
      assert context.status == :error
      assert {:value, {:error, ^error}} = :queue.peek_r(context.event_history)
    end

    test "handles error tuples in lookup_variable" do
      error = {:error, :some_error, "details"}
      assert ^error = Context.lookup_variable(error, :any_name)
    end

    test "handles error when updating undefined variable" do
      context = Context.new()
      assert {:error, :undefined_variable} = Context.update_variable(context, :test_var, "value")
    end
  end

  describe "stack traces" do
    test "generates stack trace" do
      context =
        Context.new()
        |> Context.push_frame(:function, name: "fn1", file: "test.ex", line: 1)
        |> Context.push_frame(:block, name: "block1", file: "test.ex", line: 2)

      trace = Context.get_stack_trace(context)
      assert length(trace) == 2
      assert Enum.at(trace, 0) =~ "function fn1"
      assert Enum.at(trace, 1) =~ "block block1"
    end
  end

  describe "variable operations" do
    setup do
      context =
        Context.new()
        |> Context.push_frame(:block, name: "test")

      {:ok, context: context}
    end

    test "declares new variable", %{context: context} do
      {:ok, context} = Context.declare_variable(context, "x", 42)
      assert {:ok, 42} = Context.lookup_variable(context, "x")
    end

    test "fails to declare variable without active frame" do
      context = Context.new()
      assert {:error, :no_active_frame} = Context.declare_variable(context, "x", 42)
    end

    test "fails to declare existing variable", %{context: context} do
      {:ok, context} = Context.declare_variable(context, "x", 42)
      assert {:error, :variable_already_exists} = Context.declare_variable(context, "x", 43)
    end

    test "updates existing variable", %{context: context} do
      {:ok, context} = Context.declare_variable(context, "x", 42)
      {:ok, context} = Context.update_variable(context, "x", 43)
      assert {:ok, 43} = Context.lookup_variable(context, "x")
    end

    test "fails to update non-existent variable", %{context: context} do
      assert {:error, :undefined_variable} = Context.update_variable(context, "x", 42)
    end

    test "looks up undefined variable", %{context: context} do
      assert {:error, :undefined_variable} = Context.lookup_variable(context, "x")
    end

    test "looks up variable in parent frame" do
      context =
        Context.new()
        |> Context.push_frame(:block, name: "outer", variables: %{"x" => 42})
        |> Context.push_frame(:block, name: "inner", variables: %{"y" => 43})

      assert {:ok, 42} = Context.lookup_variable(context, "x")
    end

    test "updates variable in outer frame" do
      context =
        Context.new()
        |> Context.push_frame(:block, name: "outer")

      {:ok, context} = Context.declare_variable(context, "x", 42)
      context = Context.push_frame(context, :block, name: "inner")
      {:ok, context} = Context.update_variable(context, "x", 43)

      assert {:ok, 43} = Context.lookup_variable(context, "x")
    end
  end

  describe "event management" do
    setup do
      context = Context.new()
      test_pid = self()
      {:ok, context: context, test_pid: test_pid}
    end

    test "subscribes to events", %{context: context, test_pid: test_pid} do
      context = Context.subscribe(context, test_pid)
      assert test_pid in context.subscribers
    end

    test "unsubscribes from events", %{context: context, test_pid: test_pid} do
      context =
        context
        |> Context.subscribe(test_pid)
        |> Context.unsubscribe(test_pid)

      refute test_pid in context.subscribers
    end

    test "controls event mask", %{context: context} do
      context = Context.set_event_mask(context, EventMask.frames_only())
      assert EventMask.has_event?(context.event_mask, :frame_entry)
      refute EventMask.has_event?(context.event_mask, :variable_read)
    end

    test "enables and disables events", %{context: context} do
      context =
        context
        |> Context.disable_events([:frame_entry, :frame_exit])
        |> Context.enable_events([:variable_read, :variable_write])

      refute EventMask.has_event?(context.event_mask, :frame_entry)
      assert EventMask.has_event?(context.event_mask, :variable_read)
    end

    test "adds events and notifies subscribers", %{context: context, test_pid: test_pid} do
      context = Context.subscribe(context, test_pid)
      _context = Context.add_event(context, :frame_entry, %{name: "test"})

      assert_receive {:debug_event, event}
      assert event.type == :frame_entry
      assert event.data.name == "test"
      assert event.context_ref == context.ref
    end

    test "filters events by mask", %{context: context, test_pid: test_pid} do
      _context =
        context
        |> Context.subscribe(test_pid)
        |> Context.disable_events([:frame_entry])
        |> Context.add_event(:frame_entry, %{name: "test"})

      refute_receive {:debug_event, _event}
    end

    test "retrieves events with filtering", %{context: context} do
      context =
        context
        |> Context.add_event(:frame_entry, %{name: "frame1"})
        |> Context.add_event(:variable_write, %{name: "x", value: 42})
        |> Context.add_event(:frame_entry, %{name: "frame2"})

      frame_events = Context.get_events(context, filter: &(&1.type == :frame_entry))
      assert length(frame_events) == 2
      assert Enum.all?(frame_events, &(&1.type == :frame_entry))
    end

    test "limits event history", %{context: context} do
      context =
        Enum.reduce(1..5, context, fn i, ctx ->
          Context.add_event(ctx, :frame_entry, %{name: "frame#{i}"})
        end)

      events = Context.get_events(context, limit: 3)
      assert length(events) == 3
    end

    test "clears event history", %{context: context} do
      context =
        context
        |> Context.add_event(:frame_entry, %{name: "test"})
        |> Context.clear_events()

      assert :queue.is_empty(context.event_history)
    end

    test "handles dead subscribers", %{context: context} do
      # Create a process that will die
      pid = spawn(fn -> :ok end)
      # Ensure process is dead
      Process.sleep(10)

      context =
        context
        |> Context.subscribe(pid)
        |> Context.add_event(:frame_entry)

      # Dead subscribers are automatically removed
      assert context.subscribers |> MapSet.size() == 0
    end

    test "notifies multiple subscribers", %{context: context, test_pid: test_pid} do
      other_pid =
        spawn(fn ->
          receive do
            {:debug_event, _} -> send(test_pid, :received)
          end
        end)

      _context =
        context
        |> Context.subscribe(test_pid)
        |> Context.subscribe(other_pid)
        |> Context.add_event(:frame_entry)

      assert_receive {:debug_event, _}
      assert_receive :received
    end
  end

  describe "stepping and error handling" do
    test "handles error tuple in maybe_step" do
      error = {:error, :some_error, "details"}
      assert ^error = Context.maybe_step(error, "message", %{})
    end

    test "increments step count" do
      context =
        Context.new()
        |> Map.put(:step_mode, true)

      context = Context.maybe_step(context, "test", %{})
      assert context.step_count == 1
    end

    test "handles ok tuple in maybe_step" do
      context = Context.new()
      assert {:ok, %Context{}} = Context.maybe_step({:ok, context}, "message", %{})
    end

    test "skips stepping when debug mode is off" do
      context = Context.new()
      assert ^context = Context.maybe_step(context, "test", %{})
    end

    test "skips stepping when step mode is off" do
      context = Context.new(debug_mode: true)
      assert ^context = Context.maybe_step(context, "test", %{})
    end
  end

  describe "location management" do
    test "updates source location tracking" do
      context =
        Context.new()
        |> Map.put(:file, "test.ex")
        |> Map.put(:line, 42)
        |> Map.put(:module, TestModule)

      assert context.file == "test.ex"
      assert context.line == 42
      assert context.module == TestModule
    end
  end
end
