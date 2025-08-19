defmodule Kodo.InstanceManager do
  @moduledoc """
  Manages multiple Kodo instances, allowing creation, destruction, and lookup
  of named, isolated Kodo environments.
  """
  use GenServer
  require Logger

  # Client API

  @doc """
  Starts the InstanceManager.
  """
  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc """
  Starts a new Kodo instance.
  """
  @spec start(atom()) :: {:ok, pid()} | {:error, term()}
  def start(name) when is_atom(name) do
    GenServer.call(__MODULE__, {:start, name})
  end

  @doc """
  Stops an existing Kodo instance.
  """
  @spec stop(atom()) :: :ok | {:error, :not_found}
  def stop(name) when is_atom(name) do
    GenServer.call(__MODULE__, {:stop, name})
  end

  @doc """
  Gets the supervisor PID for a named instance.
  """
  @spec get(atom()) :: {:ok, pid()} | {:error, :not_found}
  def get(name) when is_atom(name) do
    GenServer.call(__MODULE__, {:get, name})
  end

  @doc """
  Lists all active instances.
  """
  @spec list() :: [atom()]
  def list do
    GenServer.call(__MODULE__, :list)
  end

  @doc """
  Checks if an instance exists.
  """
  @spec exists?(atom()) :: boolean()
  def exists?(name) when is_atom(name) do
    case get(name) do
      {:ok, _pid} -> true
      {:error, :not_found} -> false
    end
  end

  # Server callbacks

  @impl true
  def init(_) do
    # Create a DynamicSupervisor to manage instances
    {:ok, instance_supervisor} =
      DynamicSupervisor.start_link(
        strategy: :one_for_one,
        name: Kodo.InstanceSupervisor
      )

    state = %{
      instances: %{},
      instance_supervisor: instance_supervisor
    }

    # Start the default instance
    case start_instance_process(:default, state) do
      {:ok, _pid, new_state} ->
        Logger.info("Started default Kodo instance")
        {:ok, new_state}

      {:error, reason} ->
        Logger.error("Failed to start default instance: #{inspect(reason)}")
        {:ok, state}
    end
  end

  @impl true
  def handle_call({:start, name}, _from, state) do
    case Map.get(state.instances, name) do
      nil ->
        case start_instance_process(name, state) do
          {:ok, pid, new_state} ->
            Logger.info("Started Kodo instance", instance: name, pid: inspect(pid))
            {:reply, {:ok, pid}, new_state}

          {:error, reason} = error ->
            Logger.error("Failed to start instance", instance: name, reason: inspect(reason))
            {:reply, error, state}
        end

      pid ->
        {:reply, {:ok, pid}, state}
    end
  end

  @impl true
  def handle_call({:stop, name}, _from, state) do
    case Map.get(state.instances, name) do
      nil ->
        {:reply, {:error, :not_found}, state}

      pid ->
        case DynamicSupervisor.terminate_child(state.instance_supervisor, pid) do
          :ok ->
            new_instances = Map.delete(state.instances, name)
            new_state = %{state | instances: new_instances}
            Logger.info("Stopped Kodo instance", instance: name)
            {:reply, :ok, new_state}

          {:error, reason} ->
            Logger.error("Failed to stop instance", instance: name, reason: inspect(reason))
            {:reply, {:error, reason}, state}
        end
    end
  end

  @impl true
  def handle_call({:get, name}, _from, state) do
    case Map.get(state.instances, name) do
      nil -> {:reply, {:error, :not_found}, state}
      pid -> {:reply, {:ok, pid}, state}
    end
  end

  @impl true
  def handle_call(:list, _from, state) do
    instances = Map.keys(state.instances)
    {:reply, instances, state}
  end

  # Handle instance process exits
  @impl true
  def handle_info({:DOWN, _ref, :process, pid, reason}, state) do
    # Find the instance name for this PID
    instance_entry =
      Enum.find(state.instances, fn {_name, instance_pid} ->
        instance_pid == pid
      end)

    case instance_entry do
      {name, _pid} ->
        Logger.warning("Instance crashed", instance: name, reason: inspect(reason))
        new_instances = Map.delete(state.instances, name)
        new_state = %{state | instances: new_instances}
        {:noreply, new_state}

      nil ->
        {:noreply, state}
    end
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("InstanceManager received unknown message: #{inspect(msg)}")
    {:noreply, state}
  end

  # Private functions

  defp start_instance_process(name, state) do
    child_spec = {Kodo.Instance, [name: name]}

    case DynamicSupervisor.start_child(state.instance_supervisor, child_spec) do
      {:ok, pid} ->
        # Monitor the instance process
        Process.monitor(pid)
        new_instances = Map.put(state.instances, name, pid)
        new_state = %{state | instances: new_instances}
        {:ok, pid, new_state}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
