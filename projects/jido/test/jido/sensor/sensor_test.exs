# defmodule JidoTest.SensorTest do
#   use JidoTest.Case, async: true

#   import ExUnit.CaptureLog
#   alias JidoTest.TestSensors.TestSensor

#   @moduletag :capture_log

#   setup context do
#     bus_name = :"test_bus_#{context.test}"
#     start_supervised!({Jido.Bus, name: bus_name})
#     {:ok, bus_name: bus_name}
#   end

#   describe "Sensor initialization" do
#     test "starts the sensor with valid options", %{bus_name: bus_name} do
#       opts = [
#         id: "test_id",
#         target: {:bus, [target: bus_name, stream: "test"]},
#         test_param: 42
#       ]

#       assert {:ok, pid} = TestSensor.start_link(opts)
#       assert Process.alive?(pid)

#       state = :sys.get_state(pid)
#       assert state.id == "test_id"
#       assert state.config.test_param == 42
#     end

#     test "uses default values when not provided", %{bus_name: bus_name} do
#       opts = [
#         target: {:bus, [target: bus_name, stream: "test"]}
#       ]

#       assert {:ok, pid} = TestSensor.start_link(opts)
#       state = :sys.get_state(pid)

#       assert is_binary(state.id)
#       assert state.config.test_param == 0
#       assert state.retain_last == 10
#     end

#     test "fails to start with invalid options", %{bus_name: bus_name} do
#       opts = [
#         target: {:bus, [target: bus_name, stream: "test"]},
#         test_param: "not an integer"
#       ]

#       assert {:error, reason} = TestSensor.start_link(opts)
#       assert reason =~ "test_param"
#     end

#     test "fails to start without required target option" do
#       assert {:error, reason} = TestSensor.start_link([])
#       assert reason =~ "required :target option not found"
#     end
#   end

#   describe "Configuration management" do
#     setup %{bus_name: bus_name} do
#       opts = [
#         target: {:bus, [target: bus_name, stream: "test"]},
#         test_param: 42
#       ]

#       {:ok, pid} = TestSensor.start_link(opts)
#       %{pid: pid}
#     end

#     test "gets complete configuration", %{pid: pid} do
#       state = :sys.get_state(pid)
#       assert is_map(state.config)
#       assert state.config.test_param == 42
#     end

#     test "gets specific configuration value", %{pid: pid} do
#       assert {:ok, 42} = TestSensor.get_config(pid, :test_param)
#       assert {:error, :not_found} = TestSensor.get_config(pid, :nonexistent)
#     end

#     test "updates multiple configuration values", %{pid: pid} do
#       assert :ok = TestSensor.set_config(pid, %{test_param: 100, new_param: "value"})
#       assert {:ok, 100} = TestSensor.get_config(pid, :test_param)
#       assert {:ok, "value"} = TestSensor.get_config(pid, :new_param)
#     end

#     test "updates single configuration value", %{pid: pid} do
#       assert :ok = TestSensor.set_config(pid, :test_param, 200)
#       assert {:ok, 200} = TestSensor.get_config(pid, :test_param)
#     end
#   end

#   describe "Sensor behavior" do
#     setup %{bus_name: bus_name} do
#       opts = [
#         target: {:bus, [target: bus_name, stream: "test"]},
#         test_param: 42
#       ]

#       {:ok, pid} = TestSensor.start_link(opts)
#       %{pid: pid}
#     end

#     test "retains last values", %{pid: pid} do
#       Enum.each(1..15, fn i ->
#         signal = %Jido.Signal{
#           id: Jido.Util.generate_id(),
#           source: "test_sensor",
#           type: "test.signal",
#           subject: "test_signal",
#           data: %{value: i}
#         }

#         send(pid, {:sensor_signal, signal})
#       end)

#       state = :sys.get_state(pid)
#       last_values = :queue.to_list(state.last_values)

#       assert length(last_values) == 10
#       assert Enum.map(last_values, & &1.data.value) == Enum.to_list(6..15)
#     end

#     test "validates signals before publishing", %{pid: pid} do
#       :ok = TestSensor.set_config(pid, :test_param, 42)
#       state = :sys.get_state(pid)
#       {:ok, signal} = TestSensor.deliver_signal(state)
#       assert {:error, :invalid_value} = TestSensor.on_before_deliver(signal, state)
#     end
#   end

#   describe "Error handling" do
#     test "handles invalid server options", %{bus_name: bus_name} do
#       opts = [
#         target: {:bus, [target: bus_name, stream: "test"]},
#         test_param: "not an integer"
#       ]

#       assert {:error, reason} = TestSensor.start_link(opts)
#       assert reason =~ "test_param"
#     end

#     test "handles errors in generate_signal", %{bus_name: bus_name} do
#       {:ok, pid} =
#         JidoTest.TestSensors.ErrorSensor1.start_link(
#           target: {:bus, [target: bus_name, stream: "test"]}
#         )

#       log =
#         capture_log(fn ->
#           state = :sys.get_state(pid)
#           {:error, :test_error} = JidoTest.TestSensors.ErrorSensor1.deliver_signal(state)
#         end)

#       assert log =~ "Test error in generate_signal"
#     end

#     test "handles errors in before_publish", %{bus_name: bus_name} do
#       {:ok, pid} =
#         JidoTest.TestSensors.ErrorSensor2.start_link(
#           target: {:bus, [target: bus_name, stream: "test"]}
#         )

#       log =
#         capture_log(fn ->
#           state = :sys.get_state(pid)
#           {:ok, signal} = JidoTest.TestSensors.ErrorSensor2.deliver_signal(state)

#           {:error, :test_error} =
#             JidoTest.TestSensors.ErrorSensor2.on_before_deliver(signal, state)
#         end)

#       assert log =~ "Test error in before_publish"
#     end
#   end

#   describe "Sensor metadata" do
#     test "returns correct metadata" do
#       assert metadata = TestSensor.__sensor_metadata__()
#       assert metadata.name == "test_sensor"
#       assert metadata.description == "A sensor for testing"
#       assert metadata.category == :test
#       assert metadata.tags == [:test, :unit]
#       assert metadata.vsn == "1.0.0"
#       assert is_list(metadata.schema)
#     end

#     test "converts metadata to JSON-compatible format" do
#       json = TestSensor.to_json()
#       assert is_map(json)
#       assert json.name == "test_sensor"
#       assert json.category == :test
#       assert json.tags == [:test, :unit]
#     end
#   end
# end
