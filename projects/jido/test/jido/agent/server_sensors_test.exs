defmodule JidoTest.Agent.Server.SensorsTest do
  use JidoTest.Case, async: true
  alias Jido.Agent.Server.Sensors, as: ServerSensors
  alias Jido.Agent.Server.State, as: ServerState

  setup do
    state = %ServerState{
      router: nil,
      agent: nil,
      dispatch: nil,
      status: :idle,
      pending_signals: [],
      max_queue_size: 1000
    }

    {:ok, state: state}
  end

  describe "build/3" do
    test "returns error for invalid agent pid", %{state: state} do
      assert {:error, :invalid_agent_pid} = ServerSensors.build(state, [], :not_a_pid)
    end

    test "returns error for invalid sensors config", %{state: state} do
      agent_pid = spawn(fn -> :ok end)

      assert {:error, :invalid_sensors_config} =
               ServerSensors.build(state, [sensors: :invalid], agent_pid)
    end

    test "handles empty sensor list", %{state: state} do
      agent_pid = spawn(fn -> :ok end)
      assert {:ok, ^state, opts} = ServerSensors.build(state, [], agent_pid)
      assert Keyword.get(opts, :child_specs, []) == []
    end

    test "configures sensors with agent pid as target", %{state: state} do
      agent_pid = spawn(fn -> :ok end)
      sensor_module = TestSensor
      sensor_opts = [name: :test_sensor]

      opts = [sensors: [{sensor_module, sensor_opts}]]

      assert {:ok, ^state, updated_opts} = ServerSensors.build(state, opts, agent_pid)

      child_specs = Keyword.get(updated_opts, :child_specs, [])
      assert length(child_specs) == 1

      {^sensor_module, configured_opts} = hd(child_specs)
      assert Keyword.get(configured_opts, :target) == agent_pid
    end

    test "preserves existing targets when adding agent pid", %{state: state} do
      agent_pid = spawn(fn -> :ok end)
      existing_target = spawn(fn -> :ok end)
      sensor_module = TestSensor
      sensor_opts = [name: :test_sensor, target: existing_target]

      opts = [sensors: [{sensor_module, sensor_opts}]]

      assert {:ok, ^state, updated_opts} = ServerSensors.build(state, opts, agent_pid)

      child_specs = Keyword.get(updated_opts, :child_specs, [])
      {^sensor_module, configured_opts} = hd(child_specs)
      assert Keyword.get(configured_opts, :target) == [existing_target, agent_pid]
    end

    test "handles multiple sensors", %{state: state} do
      agent_pid = spawn(fn -> :ok end)

      sensor_specs = [
        {TestSensor1, [name: :sensor1]},
        {TestSensor2, [name: :sensor2]}
      ]

      opts = [sensors: sensor_specs]

      assert {:ok, ^state, updated_opts} = ServerSensors.build(state, opts, agent_pid)

      child_specs = Keyword.get(updated_opts, :child_specs, [])
      assert length(child_specs) == 2

      Enum.each(child_specs, fn {_module, opts} ->
        assert Keyword.get(opts, :target) == agent_pid
      end)
    end

    test "merges with existing child_specs", %{state: state} do
      agent_pid = spawn(fn -> :ok end)
      existing_spec = {ExistingModule, [name: :existing]}
      sensor_specs = [{TestSensor, [name: :new_sensor]}]

      opts = [child_specs: [existing_spec], sensors: sensor_specs]

      assert {:ok, ^state, updated_opts} = ServerSensors.build(state, opts, agent_pid)

      child_specs = Keyword.get(updated_opts, :child_specs, [])
      assert length(child_specs) == 2
      assert Enum.member?(child_specs, existing_spec)
    end
  end
end
