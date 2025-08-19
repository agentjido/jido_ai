defmodule Kodo.InstanceManager do
  @moduledoc """
  Manages multiple Kodo instances, allowing creation, destruction, and lookup
  of named, isolated Kodo environments.

  Each instance is a supervised process tree that provides complete isolation
  with its own VFS, command registry, job manager, and user sessions.
  """
  use GenServer
  require Logger

  # Client API

  @doc """
  Starts the InstanceManager.
  """
  @spec start_link(any()) :: GenServer.on_start()
  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc """
  Starts a new Kodo instance with the given name asynchronously.

  Returns `{:ok, :starting}` immediately if the operation is initiated,
  or `{:ok, pid}` if the instance already exists.
  Use `monitor_operation/2` to be notified of completion.
  """
  @spec start(atom()) :: {:ok, :starting | pid()} | {:error, term()}
  def start(name) when is_atom(name) do
    GenServer.call(__MODULE__, {:start_async, name})
  end

  @doc """
  Stops an existing Kodo instance asynchronously.

  Returns `{:ok, :stopping}` immediately if the operation is initiated,
  or `{:error, :not_found}` if instance doesn't exist.
  Use `monitor_operation/2` to be notified of completion.
  """
  @spec stop(atom()) :: {:ok, :stopping} | {:error, :not_found}
  def stop(name) when is_atom(name) do
    GenServer.call(__MODULE__, {:stop_async, name})
  end

  @doc """
  Gets the supervisor PID for a named instance.

  Returns `{:ok, pid}` if found, `{:ok, :starting}` if starting,
  `{:ok, :stopping}` if stopping, or `{:error, :not_found}` if not found.
  """
  @spec get(atom()) :: {:ok, pid() | :starting | :stopping} | {:error, :not_found}
  def get(name) when is_atom(name) do
    GenServer.call(__MODULE__, {:get, name})
  end

  @doc """
  Lists all active instance names.
  """
  @spec list() :: [atom()]
  def list do
    GenServer.call(__MODULE__, :list)
  end

  @doc """
  Monitors an async operation for completion.

  Returns a reference that can be used with `receive` to get notifications.
  Notifications are sent as `{:instance_operation, ref, name, result}` where
  result is `{:ok, pid}`, `{:error, reason}`, or `:stopped`.
  """
  @spec monitor_operation(atom(), :start | :stop) :: reference()
  def monitor_operation(name, operation) when is_atom(name) and operation in [:start, :stop] do
    GenServer.call(__MODULE__, {:monitor_operation, name, operation})
  end

  @doc """
  Checks if an instance exists.
  """
  @spec exists?(atom()) :: boolean()
  def exists?(name) when is_atom(name) do
    case get(name) do
      {:ok, pid} when is_pid(pid) -> true
      {:ok, _state} -> true
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
      instance_supervisor: instance_supervisor,
      operation_monitors: %{}
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
  def handle_call({:start_async, name}, _from, state) do
    case Map.get(state.instances, name) do
      nil ->
        new_instances = Map.put(state.instances, name, :starting)
        new_state = %{state | instances: new_instances}
        GenServer.cast(__MODULE__, {:do_start, name})
        {:reply, {:ok, :starting}, new_state}

      :starting ->
        {:reply, {:ok, :starting}, state}

      :stopping ->
        {:reply, {:error, :instance_stopping}, state}

      pid when is_pid(pid) ->
        {:reply, {:ok, pid}, state}
    end
  end

  @impl true
  def handle_call({:stop_async, name}, _from, state) do
    case Map.get(state.instances, name) do
      nil ->
        {:reply, {:error, :not_found}, state}

      :starting ->
        {:reply, {:error, :instance_starting}, state}

      :stopping ->
        {:reply, {:ok, :stopping}, state}

      pid when is_pid(pid) ->
        new_instances = Map.put(state.instances, name, :stopping)
        new_state = %{state | instances: new_instances}
        GenServer.cast(__MODULE__, {:do_stop, name, pid})
        {:reply, {:ok, :stopping}, new_state}
    end
  end

  @impl true
  def handle_call({:get, name}, _from, state) do
    case Map.get(state.instances, name) do
      nil -> {:reply, {:error, :not_found}, state}
      value -> {:reply, {:ok, value}, state}
    end
  end

  @impl true
  def handle_call({:monitor_operation, name, operation}, {from_pid, _tag}, state) do
    ref = make_ref()
    monitor_key = {name, operation}
    monitors = Map.get(state.operation_monitors, monitor_key, [])
    new_monitors = [{ref, from_pid} | monitors]
    new_operation_monitors = Map.put(state.operation_monitors, monitor_key, new_monitors)
    new_state = %{state | operation_monitors: new_operation_monitors}
    {:reply, ref, new_state}
  end

  @impl true
  def handle_call(:list, _from, state) do
    instances = Map.keys(state.instances)
    {:reply, instances, state}
  end

  @impl true
  def handle_cast({:do_start, name}, state) do
    case start_instance_process(name, state) do
      {:ok, pid, new_state} ->
        Logger.info("Started Kodo instance: #{name} (#{inspect(pid)})")
        final_state = notify_monitors(new_state, name, :start, {:ok, pid})
        {:noreply, final_state}

      {:error, reason} ->
        Logger.error("Failed to start instance #{name}: #{inspect(reason)}")
        new_instances = Map.delete(state.instances, name)
        new_state = %{state | instances: new_instances}
        final_state = notify_monitors(new_state, name, :start, {:error, reason})
        {:noreply, final_state}
    end
  end

  @impl true
  def handle_cast({:do_stop, name, pid}, state) do
    case DynamicSupervisor.terminate_child(state.instance_supervisor, pid) do
      :ok ->
        new_instances = Map.delete(state.instances, name)
        new_state = %{state | instances: new_instances}
        Logger.info("Stopped Kodo instance: #{name}")
        final_state = notify_monitors(new_state, name, :stop, :stopped)
        {:noreply, final_state}

      {:error, reason} ->
        Logger.error("Failed to stop instance #{name}: #{inspect(reason)}")
        # Revert back to the original PID since stop failed
        new_instances = Map.put(state.instances, name, pid)
        new_state = %{state | instances: new_instances}
        final_state = notify_monitors(new_state, name, :stop, {:error, reason})
        {:noreply, final_state}
    end
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
        Logger.warning("Instance #{name} crashed: #{inspect(reason)}")
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

  defp notify_monitors(state, name, operation, result) do
    monitor_key = {name, operation}
    monitors = Map.get(state.operation_monitors, monitor_key, [])
    
    Enum.each(monitors, fn {ref, pid} ->
      send(pid, {:instance_operation, ref, name, result})
    end)
    
    # Clean up monitors after notification
    new_operation_monitors = Map.delete(state.operation_monitors, monitor_key)
    %{state | operation_monitors: new_operation_monitors}
  end
end
