# defmodule JidoTest.Sensor.Examples.RegistrationCounterSensorTest do
#   use JidoTest.Case, async: true

#   @moduletag :capture_log
#   defmodule RegistrationCounterSensor do
#     @moduledoc """
#     Tracks user registration success and failure metrics, emitting signals with statistics.
#     """
#     use Jido.Sensor,
#       name: "registration_counter_sensor",
#       description: "Monitors registration successes and failures",
#       category: :metrics,
#       tags: [:registration, :counter],
#       vsn: "1.0.0",
#       schema: [
#         emit_interval: [
#           type: :pos_integer,
#           default: 1000,
#           doc: "Interval between metric emissions in ms"
#         ]
#       ]

#     def mount(opts) do
#       state =
#         Map.merge(opts, %{
#           successful: 0,
#           failed: 0
#         })

#       schedule_emit(state)
#       {:ok, state}
#     end

#     def generate_signal(state) do
#       total = state.successful + state.failed
#       success_rate = if total > 0, do: state.successful / total * 100, else: 0

#       signal =
#         Jido.Signal.new(%{
#           source: "#{state.sensor.name}:#{state.id}",
#           subject: "registration_counts",
#           type: "registration.metrics",
#           data: %{
#             successful: state.successful,
#             failed: state.failed,
#             total: total,
#             success_rate: success_rate
#           }
#         })

#       {:ok, signal}
#     end

#     def handle_info(:emit, state) do
#       case generate_signal(state) do
#         {:ok, signal} ->
#           :ok = publish_signal(signal, state)
#           schedule_emit(state)
#           {:noreply, state}
#       end
#     end

#     def handle_info({:registration, :success}, state) do
#       new_state = %{state | successful: state.successful + 1}

#       case generate_signal(new_state) do
#         {:ok, signal} ->
#           :ok = publish_signal(signal, new_state)
#           {:noreply, new_state}
#       end
#     end

#     def handle_info({:registration, :failure}, state) do
#       new_state = %{state | failed: state.failed + 1}

#       case generate_signal(new_state) do
#         {:ok, signal} ->
#           :ok = publish_signal(signal, new_state)
#           {:noreply, new_state}
#       end
#     end

#     defp schedule_emit(state) do
#       Process.send_after(self(), :emit, state.emit_interval)
#     end
#   end

#   setup context do
#     bus_name = :"test_bus_#{context.test}"
#     start_supervised!({Jido.Bus, name: bus_name})
#     {:ok, bus_name: bus_name}
#   end

#   describe "RegistrationCounterSensor" do
#     test "initializes with correct default values", %{bus_name: bus_name} do
#       {:ok, pid} =
#         start_supervised(
#           {RegistrationCounterSensor, bus_name: bus_name, stream_id: "test_stream"}
#         )

#       state = :sys.get_state(pid)

#       assert state.successful == 0
#       assert state.failed == 0
#       assert state.emit_interval == 1000
#     end

#     test "tracks successful registrations", %{bus_name: bus_name} do
#       {:ok, pid} =
#         start_supervised(
#           {RegistrationCounterSensor,
#            bus_name: bus_name, stream_id: "test_stream", emit_interval: 100}
#         )

#       :ok = Jido.Bus.subscribe(bus_name, "test_stream")

#       # Record successes and wait for each signal
#       send(pid, {:registration, :success})
#       assert_receive {:bus_event, ^bus_name, "test_stream", [signal1]}, 200
#       assert signal1.data.successful == 1

#       send(pid, {:registration, :success})
#       assert_receive {:bus_event, ^bus_name, "test_stream", [signal2]}, 200
#       assert signal2.data.successful == 2
#       assert signal2.data.failed == 0
#       assert signal2.data.total == 2
#       assert signal2.data.success_rate == 100.0
#     end

#     test "tracks failed registrations", %{bus_name: bus_name} do
#       {:ok, pid} =
#         start_supervised(
#           {RegistrationCounterSensor,
#            bus_name: bus_name, stream_id: "test_stream", emit_interval: 100}
#         )

#       :ok = Jido.Bus.subscribe(bus_name, "test_stream")

#       # Record some failures
#       send(pid, {:registration, :failure})
#       assert_receive {:bus_event, ^bus_name, "test_stream", [signal1]}, 200
#       assert signal1.data.failed == 1

#       # Wait for signal
#       send(pid, {:registration, :failure})
#       assert_receive {:bus_event, ^bus_name, "test_stream", [signal2]}, 200
#       assert signal2.data.successful == 0
#       assert signal2.data.failed == 2
#       assert signal2.data.total == 2
#       assert signal2.data.success_rate == 0.0
#     end

#     test "calculates mixed success rate", %{bus_name: bus_name} do
#       {:ok, pid} =
#         start_supervised(
#           {RegistrationCounterSensor,
#            bus_name: bus_name, stream_id: "test_stream", emit_interval: 100}
#         )

#       :ok = Jido.Bus.subscribe(bus_name, "test_stream")

#       # Mix of successes and failures
#       send(pid, {:registration, :success})
#       assert_receive {:bus_event, ^bus_name, "test_stream", [signal1]}, 200
#       assert signal1.data.successful == 1
#       assert signal1.data.failed == 0
#       assert signal1.data.total == 1

#       send(pid, {:registration, :success})
#       assert_receive {:bus_event, ^bus_name, "test_stream", [signal2]}, 200
#       assert signal2.data.successful == 2
#       assert signal2.data.failed == 0
#       assert signal2.data.total == 2
#       assert signal2.data.success_rate == 100.0

#       send(pid, {:registration, :failure})
#       assert_receive {:bus_event, ^bus_name, "test_stream", [signal3]}, 200
#       assert signal3.data.successful == 2
#       assert signal3.data.failed == 1
#       assert signal3.data.total == 3
#       assert_in_delta signal3.data.success_rate, 66.67, 0.01
#     end

#     test "emits regular metric updates", %{bus_name: bus_name} do
#       {:ok, pid} =
#         start_supervised(
#           {RegistrationCounterSensor,
#            bus_name: bus_name, stream_id: "test_stream", emit_interval: 100}
#         )

#       :ok = Jido.Bus.subscribe(bus_name, "test_stream")

#       # Should get regular updates even without activity
#       assert_receive {:bus_event, ^bus_name, "test_stream", [signal1]}, 200
#       assert signal1.type == "registration.metrics"
#       assert signal1.data.total == 0

#       assert_receive {:bus_event, ^bus_name, "test_stream", [signal2]}, 200
#       assert signal2.type == "registration.metrics"
#     end
#   end
# end
