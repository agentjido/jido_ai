defmodule Jido.Signal.BusSpyTest do
  use ExUnit.Case, async: true

  alias Jido.Signal
  alias Jido.Signal.Bus
  alias Jido.Signal.BusSpy

  setup do
    # Generate unique bus name for this test
    bus_name = :"test_bus_spy_#{System.unique_integer([:positive])}"

    # Start a test bus
    {:ok, _bus_pid} = Bus.start_link(name: bus_name)

    on_exit(fn ->
      case Bus.whereis(bus_name) do
        {:ok, pid} when is_pid(pid) ->
          if Process.alive?(pid) do
            try do
              GenServer.stop(pid, :normal, 1000)
            catch
              :exit, _ -> :ok
            end
          end

        _ ->
          :ok
      end
    end)

    {:ok, bus_name: bus_name}
  end

  test "spy captures signals crossing bus boundaries", %{bus_name: bus_name} do
    # Start the spy
    spy = BusSpy.start_spy()

    # Subscribe to test events
    {:ok, _sub_id} = Bus.subscribe(bus_name, "test.*", [])

    # Create and publish a test signal
    {:ok, signal} =
      Signal.new(%{
        type: "test.event",
        source: "test_source",
        data: %{message: "hello world"}
      })

    {:ok, _recorded} = Bus.publish(bus_name, [signal])

    # Give the telemetry events time to be processed
    Process.sleep(50)

    # Check that the spy captured the signal
    dispatched_signals = BusSpy.get_dispatched_signals(spy)
    assert length(dispatched_signals) >= 1

    # Find our test event
    test_events = BusSpy.get_signals_by_type(spy, "test.event")
    assert length(test_events) >= 1

    # Get the first event (before_dispatch)
    event = hd(test_events)
    assert event.event == :before_dispatch
    assert event.bus_name == bus_name
    assert event.signal_type == "test.event"
    assert event.signal.data.message == "hello world"

    BusSpy.stop_spy(spy)
  end

  test "spy can wait for specific signals", %{bus_name: bus_name} do
    spy = BusSpy.start_spy()

    # Subscribe to test events
    {:ok, _sub_id} = Bus.subscribe(bus_name, "async.*", [])

    # Start a task to publish signal after delay
    Task.start(fn ->
      Process.sleep(100)

      {:ok, signal} =
        Signal.new(%{
          type: "async.test",
          source: "delayed_source",
          data: %{delayed: true}
        })

      Bus.publish(bus_name, [signal])
    end)

    # Wait for the signal to arrive
    assert {:ok, event} = BusSpy.wait_for_signal(spy, "async.test", 1000)
    assert event.signal.data.delayed == true

    BusSpy.stop_spy(spy)
  end

  test "spy pattern matching works correctly", %{bus_name: bus_name} do
    spy = BusSpy.start_spy()

    # Subscribe to user and order events
    {:ok, _user_sub} = Bus.subscribe(bus_name, "user.*", [])
    {:ok, _order_sub} = Bus.subscribe(bus_name, "order.*", [])

    # Publish various signals
    signals = [
      %{type: "user.created", source: "auth", data: %{id: 1}},
      %{type: "user.updated", source: "auth", data: %{id: 1}},
      %{type: "order.placed", source: "shop", data: %{id: 2}},
      %{type: "order.cancelled", source: "shop", data: %{id: 2}}
    ]

    for signal_data <- signals do
      {:ok, signal} = Signal.new(signal_data)
      Bus.publish(bus_name, [signal])
    end

    Process.sleep(50)

    # Test different pattern matches
    user_events = BusSpy.get_signals_by_type(spy, "user.*")

    # At least before_dispatch events
    assert length(user_events) >= 2

    order_events = BusSpy.get_signals_by_type(spy, "order.*")
    # At least before_dispatch events
    assert length(order_events) >= 2

    all_events = BusSpy.get_dispatched_signals(spy)
    # At least 4 events (4 signals, each with before_dispatch)
    assert length(all_events) >= 4

    exact_match = BusSpy.get_signals_by_type(spy, "user.created")
    assert length(exact_match) >= 1
    assert hd(exact_match).signal.type == "user.created"

    BusSpy.stop_spy(spy)
  end

  test "spy captures dispatch results and errors", %{bus_name: bus_name} do
    spy = BusSpy.start_spy()

    # Subscribe with a pid dispatch to self() 
    {:ok, _sub_id} =
      Bus.subscribe(bus_name, "result.*",
        dispatch: {:pid, [target: self(), delivery_mode: :async]}
      )

    # Create test signal
    {:ok, signal} =
      Signal.new(%{
        type: "result.test",
        source: "test",
        data: %{test: true}
      })

    {:ok, _recorded} = Bus.publish(bus_name, [signal])

    Process.sleep(50)

    # Check for after_dispatch events with results
    dispatched_signals = BusSpy.get_dispatched_signals(spy)
    after_dispatch_events = Enum.filter(dispatched_signals, &(&1.event == :after_dispatch))

    assert length(after_dispatch_events) >= 1
    event = hd(after_dispatch_events)
    assert event.dispatch_result == :ok

    BusSpy.stop_spy(spy)
  end

  test "spy clears events correctly", %{bus_name: bus_name} do
    spy = BusSpy.start_spy()

    {:ok, _sub_id} = Bus.subscribe(bus_name, "clear.*", [])

    {:ok, signal} =
      Signal.new(%{
        type: "clear.test",
        source: "test",
        data: %{}
      })

    Bus.publish(bus_name, [signal])
    Process.sleep(50)

    # Verify events exist
    events = BusSpy.get_dispatched_signals(spy)
    refute Enum.empty?(events)

    # Clear events
    :ok = BusSpy.clear_events(spy)

    # Verify events are cleared
    events = BusSpy.get_dispatched_signals(spy)
    assert events == []

    BusSpy.stop_spy(spy)
  end
end
