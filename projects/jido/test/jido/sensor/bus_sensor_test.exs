# defmodule Jido.Sensors.BusTest do
#   use JidoTest.Case, async: false
#   alias Jido.Sensors.Bus, as: BusSensor

#   @moduletag :capture_log

#   setup do
#     # Start a test bus with a unique name for each test
#     bus_name = :"test_bus_#{:erlang.unique_integer()}"
#     start_supervised!({Jido.Bus, name: bus_name, adapter: :in_memory})
#     {:ok, pid} = Jido.Bus.whereis(bus_name)
#     {:ok, %{bus_name: bus_name, bus: pid}}
#   end

#   describe "Bus Sensor" do
#     test "initializes with required config", %{bus_name: bus_name} do
#       opts = [
#         id: "test_bus",
#         target: {:pid, target: self()},
#         bus_name: bus_name,
#         stream_id: "test_stream"
#       ]

#       {:ok, pid} = BusSensor.start_link(opts)
#       state = :sys.get_state(pid)

#       assert state.id == "test_bus"
#       assert state.config.bus_name == bus_name
#       assert state.config.stream_id == "test_stream"
#       assert Map.get(state.config, :filter_source) == nil

#       :ok = GenServer.stop(pid)
#     end

#     test "forwards signals matching stream_id", %{bus_name: bus_name, bus: bus} do
#       opts = [
#         id: "test_bus",
#         target: {:pid, target: self()},
#         bus_name: bus_name,
#         stream_id: "test_stream"
#       ]

#       {:ok, pid} = BusSensor.start_link(opts)

#       # Wait for subscription confirmation
#       assert_receive {:subscribed, _subscription}, 200

#       # Create a signal with matching stream_id
#       signal = %Jido.Signal{
#         id: "test_signal_1",
#         type: "test.event",
#         source: "test_source",
#         data: %{value: 1},
#         jido_metadata: %{"stream_id" => "test_stream"}
#       }

#       # Publish the signal
#       :ok = Jido.Bus.publish(bus, "test_stream", :any_version, [signal])

#       assert_receive {:signal, {:ok, received_signal}}, 200
#       assert received_signal.type == "test.event"
#       assert received_signal.data == %{value: 1}
#       assert received_signal.source =~ "bus_sensor:test_bus"
#       assert received_signal.jido_metadata["original_stream"] == "test_stream"
#       assert received_signal.jido_metadata["original_source"] == "test_source"

#       :ok = GenServer.stop(pid)
#     end

#     test "filters out signals with non-matching stream_id", %{bus_name: bus_name, bus: bus} do
#       opts = [
#         id: "test_bus",
#         target: {:pid, target: self()},
#         bus_name: bus_name,
#         stream_id: "test_stream"
#       ]

#       {:ok, pid} = BusSensor.start_link(opts)

#       # Wait for subscription confirmation
#       assert_receive {:subscribed, _subscription}, 200

#       # Create a signal with non-matching stream_id
#       signal = %Jido.Signal{
#         id: "test_signal_2",
#         type: "test.event",
#         source: "test_source",
#         data: %{value: 2},
#         jido_metadata: %{"stream_id" => "other_stream"}
#       }

#       # Publish the signal
#       :ok = Jido.Bus.publish(bus, "other_stream", :any_version, [signal])

#       refute_receive {:signal, _}, 200

#       :ok = GenServer.stop(pid)
#     end

#     test "handles subscription format with subscription reference", %{
#       bus_name: bus_name,
#       bus: bus
#     } do
#       opts = [
#         id: "test_bus",
#         target: {:pid, target: self()},
#         bus_name: bus_name,
#         stream_id: "test_stream"
#       ]

#       {:ok, pid} = BusSensor.start_link(opts)

#       # Wait for subscription confirmation
#       assert_receive {:subscribed, _subscription}, 200

#       # Create a signal
#       signal = %Jido.Signal{
#         id: "test_signal_4",
#         type: "test.event",
#         source: "test_source",
#         data: %{value: 4},
#         jido_metadata: %{"stream_id" => "test_stream"}
#       }

#       # Publish the signal
#       :ok = Jido.Bus.publish(bus, "test_stream", :any_version, [signal])

#       assert_receive {:signal, {:ok, received_signal}}, 200
#       assert received_signal.type == "test.event"
#       assert received_signal.data == %{value: 4}
#       assert received_signal.source =~ "bus_sensor:test_bus"
#       assert received_signal.jido_metadata["original_source"] == "test_source"

#       :ok = GenServer.stop(pid)
#     end

#     test "unsubscribes from bus on shutdown", %{bus_name: bus_name} do
#       opts = [
#         id: "test_bus",
#         target: {:pid, target: self()},
#         bus_name: bus_name,
#         stream_id: "test_stream"
#       ]

#       {:ok, pid} = BusSensor.start_link(opts)

#       # Wait for subscription confirmation
#       assert_receive {:subscribed, _subscription}, 200

#       # Trigger shutdown
#       :ok = GenServer.stop(pid)

#       # Verify process terminated
#       refute Process.alive?(pid)
#     end
#   end
# end
