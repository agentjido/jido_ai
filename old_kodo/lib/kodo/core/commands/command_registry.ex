defmodule Kodo.Core.Commands.CommandRegistry do
  @moduledoc """
  Manages command registration and lookup.
  """
  use GenServer
  require Logger

  # Client API

  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    instance = Keyword.get(opts, :instance)
    GenServer.start_link(__MODULE__, instance, name: name)
  end

  def register_command(registry_pid \\ __MODULE__, module) when is_atom(module) do
    GenServer.call(registry_pid, {:register, module})
  end

  def get_command(registry_pid \\ __MODULE__, name) do
    GenServer.call(registry_pid, {:get, name})
  end

  def list_commands(registry_pid \\ __MODULE__) do
    GenServer.call(registry_pid, :list)
  end

  # Server callbacks

  @impl true
  def init(instance) do
    {:ok, %{instance: instance, commands: %{}}}
  end

  @impl true
  def handle_call({:register, module}, _from, state) do
    case validate_command_module(module) do
      :ok ->
        name = module.name()

        Logger.debug("Registering command",
          instance: state.instance,
          name: name,
          module: module
        )

        new_commands = Map.put(state.commands, name, module)
        {:reply, :ok, %{state | commands: new_commands}}

      {:error, reason} = error ->
        Logger.warning("Failed to register command",
          instance: state.instance,
          module: module,
          reason: reason
        )

        {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:get, name}, _from, state) do
    {:reply, Map.fetch(state.commands, name), state}
  end

  @impl true
  def handle_call(:list, _from, state) do
    {:reply, state.commands, state}
  end

  # Private functions

  defp validate_command_module(module) do
    if implements_command_behavior?(module) do
      :ok
    else
      {:error, "Module does not implement Kodo.Ports.Command behavior"}
    end
  end

  defp implements_command_behavior?(module) do
    behaviours = module.module_info(:attributes)[:behaviour] || []
    Kodo.Ports.Command in behaviours
  end
end
