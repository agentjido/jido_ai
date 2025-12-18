defmodule Jido.Agent.Server.Sensors do
  @moduledoc false
  use ExDbug, enabled: false

  @doc """
  Builds sensor configuration by injecting the agent pid into sensor targets and preparing child specs.

  ## Parameters
  - state: Current server state
  - opts: Configuration options containing sensor specs
  - agent_pid: PID of the agent process that will receive sensor signals

  ## Returns
  - `{:ok, state, opts}` - Sensors configured successfully
  - `{:error, reason}` - Failed to configure sensors
  """
  def build(state, opts, agent_pid) when is_pid(agent_pid) do
    dbug("Building sensor configuration", state: state, opts: opts, agent_pid: agent_pid)

    case get_sensor_specs(opts) do
      {:ok, sensors} ->
        dbug("Got sensor specs", sensors: sensors)
        # Prepare sensors with agent_pid as target
        sensors_with_target = prepare_sensor_specs(sensors, agent_pid)
        dbug("Prepared sensor specs with target", sensors_with_target: sensors_with_target)

        # Update opts with prepared sensors in child_specs
        updated_opts =
          opts
          |> Keyword.update(:child_specs, sensors_with_target, fn existing_specs ->
            (List.wrap(existing_specs) ++ sensors_with_target)
            |> Enum.uniq()
          end)

        dbug("Updated options with sensor child specs", updated_opts: updated_opts)
        {:ok, state, updated_opts}

      {:error, _} = error ->
        dbug("Failed to get sensor specs", error: error)
        error
    end
  end

  def build(_state, _opts, _agent_pid) do
    dbug("Invalid agent PID provided")
    {:error, :invalid_agent_pid}
  end

  # Private Functions

  defp get_sensor_specs(opts) do
    dbug("Getting sensor specs from options", opts: opts)

    case Keyword.get(opts, :sensors) do
      nil ->
        dbug("No sensors configured")
        {:ok, []}

      sensors when is_list(sensors) ->
        dbug("Found sensor configuration", sensors: sensors)
        {:ok, sensors}

      _invalid ->
        dbug("Invalid sensors configuration")
        {:error, :invalid_sensors_config}
    end
  end

  defp prepare_sensor_specs(sensors, agent_pid) do
    dbug("Preparing sensor specs", sensors: sensors, agent_pid: agent_pid)

    prepared =
      Enum.map(sensors, fn
        {module, sensor_opts} when is_list(sensor_opts) ->
          dbug("Preparing sensor module with options", module: module, sensor_opts: sensor_opts)
          {module, add_target_to_opts(sensor_opts, agent_pid)}

        other ->
          dbug("Passing through other sensor spec", other: other)
          other
      end)

    dbug("Prepared sensor specs", prepared: prepared)
    prepared
  end

  defp add_target_to_opts(sensor_opts, agent_pid) when is_list(sensor_opts) do
    dbug("Adding target to sensor options", sensor_opts: sensor_opts, agent_pid: agent_pid)

    case Keyword.get(sensor_opts, :target) do
      nil ->
        dbug("No existing target, setting agent PID")
        Keyword.put(sensor_opts, :target, agent_pid)

      existing_target when is_list(existing_target) ->
        dbug("Adding agent PID to existing target list", existing_target: existing_target)
        Keyword.put(sensor_opts, :target, existing_target ++ [agent_pid])

      existing_target ->
        dbug("Converting single target to list with agent PID", existing_target: existing_target)
        Keyword.put(sensor_opts, :target, [existing_target, agent_pid])
    end
  end
end
