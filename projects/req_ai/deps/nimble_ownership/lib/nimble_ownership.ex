defmodule NimbleOwnership do
  @moduledoc """
  Module that allows you to manage ownership of resources across processes.

  The idea is that you can track ownership of terms (keys) across processes,
  and allow processes to use a key through processes that are already allowed.

  ```mermaid
  flowchart LR
    pidA["Process A"]
    pidB["Process B"]
    pidC["Process C"]
    res(["Resource (with associated metadata)"])

    pidA -->|Owns| res
    pidA -->|Allows| pidB
    pidB -->|Can access| res
    pidB -->|Allows| pidC
    pidC -->|Can access| res
  ```

  A typical use case for such a module is tracking resource ownership across processes
  in order to isolate access to resources in **test suites**. For example, the
  [Mox][mox] library uses this module to track ownership
  of mocks across processes (in shared mode).

  ## Usage

  To track ownership of resources, you need to start a `NimbleOwnership` server (a process),
  through `start_link/1` or `child_spec/1`.

  Then, you can allow a process access to a key through `allow/4`. You can then check
  if a PID can access the given key through `fetch_owner/3`.

  ### Metadata

  You can store arbitrary metadata (`t:metadata/0`) alongside each **owned resource**.
  This metadata is returned together with the owner PID when you call `fetch_owner/3`.

  ## Modes

  The ownership server can be in one of two modes:

    * **private** (the default): in this mode, you can only allow access to a key through
      the owner PID or PIDs that are already allowed to access the key. You can allow PIDs
      through `allow/4`. This mode is useful when you want to track ownership of resources
      in concurrent environments (such as in a test suite).

    * **shared**: in this mode, there is only one *shared owner PID* that owns all the keys
      in the ownership server. Any other PID can read the metadata associated with any key,
      but it cannot update the metadata (only the shared owner can).

  > #### Returning to Private Mode {: .warning}
  >
  > If the ownership server is in *shared mode* and the shared owner process terminates,
  > the server automatically returns to *private mode*.

  ## Cleanup

  When an owner PID goes down, the ownership server automatically cleans up all the
  allowances and owned keys associated with that owner PID. If you want to **manually**
  clean up the allowances and owned keys associated with an owner PID instead, you can
  use `set_owner_to_manual_cleanup/2` and `cleanup_owner/2`. `set_owner_to_manual_cleanup/2`
  sets the owner PID to manual cleanup mode, and `cleanup_owner/2` cleans up the allowances
  and owned keys associated with the owner PID.

  This is mostly useful if you're using this library to write tests, and your tests
  are based on *expectations*, that is, you first set an expectation (that you store
  in the ownership server) and then you verify that the expectation was met when exiting
  the test. Without digging too deep, a practical example of this is [Mox][mox] and its
  `Mox.expect/3` and `Mox.verify_on_exit!/1` functions.

  [mox]: https://hexdocs.pm/mox/Mox.html
  """

  defguardp is_timeout(val) when (is_integer(val) and val > 0) or val == :infinity

  use GenServer

  alias NimbleOwnership.Error

  @typedoc "Ownership server."
  @type server() :: GenServer.server()

  @typedoc "Arbitrary key."
  @type key() :: term()

  @typedoc "Arbitrary metadata associated with an owned `t:key/0`."
  @type metadata() :: term()

  @genserver_opts [
    :name,
    :timeout,
    :debug,
    :spawn_opt,
    :hibernate_after
  ]

  @doc """
  Starts an ownership server.

  ## Options

  This function supports all the options supported by `GenServer.start_link/3`, namely:

  #{Enum.map_join(@genserver_opts, "\n", &"  * `#{inspect(&1)}`")}
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(options \\ []) when is_list(options) do
    {genserver_opts, other_opts} = Keyword.split(options, @genserver_opts)

    if other_opts != [] do
      raise ArgumentError, "unknown options: #{inspect(Keyword.keys(other_opts))}"
    end

    GenServer.start_link(__MODULE__, [], genserver_opts)
  end

  @doc """
  Allows `pid_to_allow` to use `key` through `pid_with_access` (on the given `ownership_server`).

  Use this function when `pid_with_access` is allowed access to `key`, and you want
  to also allow `pid_to_allow` to use `key`.

  This function return an error in the following cases:

    * When `pid_to_allow` is already allowed to use `key` via **another owner PID**
      that is not the owner of `pid_with_access`. In this case, the `:reason` field of the returned
      `NimbleOwnership.Error` struct is set to `{:already_allowed, other_owner_pid}`.

    * When the ownership server is in [**shared mode**](#module-modes). In this case,
      the `:reason` field of the returned `NimbleOwnership.Error` struct is set to
      `:cant_allow_in_shared_mode`.

  > #### Tracking Callers {: .tip}
  >
  > The ownership server automatically considers all the direct and indirect "children"
  > of an owner PID as allowed to access the owner's keys. By children, we mean processes
  > that have been spawned by the owner PID or by any of its children, which is something
  > we determine by looking at the `:"$callers"` key in the process dictionary.
  > This is useful for many standard process kinds. For example, if a process owns a key
  > and starts a task with `Task.start_link/1`, then the task will be allowed to access
  > the key without having to explicitly call `allow/4`.

  ### Transitive Allowances

  Allowances are **transitive**. If `pid_with_access` allows `pid_to_allow`, it is equivalent
  to the owner of `pid_with_access` allowing `pid_to_allow`, effectively tying `pid_to_allow`
  with the owner. If `pid_with_access` terminates, `pid_to_allow` will still have access to the
  key, until the `owner_pid` itself terminates or removes the allowance.

  ### Deferred (lazy) allowances

  If the process is not yet started at the moment of allowance definition, it might be allowed
  as a function, assuming at the moment of invocation it would have been started.
  If the function cannot be resolved to a PID during invocation, the expectation will not succeed.

  The function might return a `t:pid/0` or a list of `t:pid/0`s. A list might be helpful
  if one needs to allow multiple PIDs that resolve from a single term, such as the list of workers in a pool.

  ## Examples

      iex> pid = spawn(fn -> Process.sleep(:infinity) end)
      iex> {:ok, server} = NimbleOwnership.start_link()
      iex> NimbleOwnership.get_and_update(server, self(), :my_key, fn _ -> {:updated, _meta = %{}} end)
      {:ok, :updated}
      iex> NimbleOwnership.allow(server, self(), pid, :my_key)
      :ok
      iex> NimbleOwnership.fetch_owner(server, [pid], :my_key)
      {:ok, self()}

  """
  @spec allow(server(), pid(), pid() | (-> resolved_pid), key()) ::
          :ok | {:error, Error.t()}
        when resolved_pid: pid() | [pid()]
  def allow(ownership_server, pid_with_access, pid_to_allow, key, timeout \\ 5000)
      when is_pid(pid_with_access) and (is_pid(pid_to_allow) or is_function(pid_to_allow, 0)) and
             is_timeout(timeout) do
    GenServer.call(ownership_server, {:allow, pid_with_access, pid_to_allow, key}, timeout)
  end

  @doc """
  Accesses `key` (owned by `owner_pid`) or initializes the ownership.

  Use this function for these purposes:

    * to initialize the ownership of a key
    * to update the metadata associated with a key

  ## Usage

  When `owner_pid` doesn't own `key`, the value passed to `fun` will be `nil`. Otherwise,
  it will be the current metadata associated with `key` under the owner `owner_pid`.

  `fun` must return `{get_value, new_meta}`. `owner_pid` will start owning
  `key` and `new_meta` will be the metadata associated with that ownership, or,
  in case `owner_pid` already owned `key`, then the metadata is updated to `new_meta`.

  If this function is successful, the return value is `{:ok, get_value}` where `get_value`
  is the value returned by `fun` in its return tuple. Otherwise, the return value is
  `{:error, reason}` (see also `NimbleOwnership.Error`).

  > #### Allowed Processes {: .warning}
  >
  > Processes that are allowed to access `key` under `owner_pid` **cannot update the metadata
  > using this function**. Only the owner PID can update the metadata.
  >
  > If an allowed process attempts to update the metadata under `key`, this function will return
  > `{:error, ...}`. This function only works if `owner_pid` doesn't own `key` and is not
  > allowed to access `key` by any other PID—in that case, it's considered as a new ownership and
  > `fun` receives `nil`.
  >
  > See the examples below for more information.

  ### Updating Metadata from an Allowed Process

  If you don't directly have access to the owner PID, but you want to update the metadata
  associated with the owner PID and `key` *from an allowed process*, do this instead:

    1. Fetch the owner of `key` through `fetch_owner/3`.
    2. Call `get_and_update/4` with the owner PID as `owner_pid`, passing in a callback
       function that returns the new metadata.

  ### Shared Mode

  When the ownership server is set to **shared mode**, you can only call this function
  with `owner_pid` set to the shared owner PID. See [the module documentation](#module-modes).

  ## Examples

  Initializing the ownership of a key:

      iex> pid = spawn(fn -> Process.sleep(:infinity) end)
      iex> {:ok, server} = NimbleOwnership.start_link()
      iex> NimbleOwnership.get_and_update(server, pid, :my_key, fn current -> {current, 1} end)
      {:ok, nil}

  Updating the metadata associated with a key:

      iex> pid = spawn(fn -> Process.sleep(:infinity) end)
      iex> {:ok, server} = NimbleOwnership.start_link()
      iex> NimbleOwnership.get_and_update(server, pid, :my_key, fn current -> {current, 1} end)
      {:ok, nil}
      iex> NimbleOwnership.get_and_update(server, pid, :my_key, fn current -> {current, 2} end)
      {:ok, 1}

  Attempting to update the metadata from an allowed process results in an error:

      iex> pid = spawn(fn -> Process.sleep(:infinity) end)
      iex> {:ok, server} = NimbleOwnership.start_link()
      iex> {:ok, _} = NimbleOwnership.get_and_update(server, pid, :some_key, fn _ -> {nil, 1} end)
      iex> :ok = NimbleOwnership.allow(server, pid, self(), :some_key)
      iex> {:error, error} = NimbleOwnership.get_and_update(server, self(), :some_key, fn current -> {current, 2} end)
      iex> %NimbleOwnership.Error{} = error
      iex> {:already_allowed, ^pid} = error.reason
      iex> error.key
      :some_key

  """
  @spec get_and_update(server(), pid(), key(), fun, timeout()) ::
          {:ok, get_value} | {:error, Error.t()}
        when fun: (nil | metadata() -> {get_value, updated_metadata :: metadata()}),
             get_value: term()
  def get_and_update(ownership_server, owner_pid, key, fun, timeout \\ 5000)
      when is_pid(owner_pid) and is_function(fun, 1) and is_timeout(timeout) do
    case GenServer.call(ownership_server, {:get_and_update, owner_pid, key, fun}, timeout) do
      {:ok, get_value} -> {:ok, get_value}
      {:error, %Error{} = error} -> {:error, error}
      {:__raise__, error} when is_exception(error) -> raise error
    end
  end

  @doc """
  Gets the owner of `key` through one of the `callers`.

  If one of the `callers` owns `key` or is allowed access to `key`,
  then this function returns `{:ok, {owner_pid, metadata}}` where `metadata` is the
  metadata associated with the `key` under the owner.

  If the ownership server is in [**shared mode**](#module-modes), then this function
  returns `{:shared_owner, shared_owner_pid}` where `shared_owner_pid` is the PID of the
  shared owner. This is regardless of the `callers`.

  If none of the callers owns `key` or is allowed access to `key`, then this function
  returns `{:error, reason}`.

  ## Examples

      iex> pid = spawn(fn -> Process.sleep(:infinity) end)
      iex> {:ok, server} = NimbleOwnership.start_link()
      iex> NimbleOwnership.set_mode_to_shared(server, pid)
      iex> {:shared_owner, owner_pid} = NimbleOwnership.fetch_owner(server, [self()], :whatever_key)
      iex> pid == owner_pid
      true

      iex> {:ok, server} = NimbleOwnership.start_link()
      iex> NimbleOwnership.fetch_owner(server, [self()], :whatever_key)
      :error

  """
  @spec fetch_owner(server(), [pid(), ...], key(), timeout()) ::
          {:ok, owner :: pid()}
          | {:shared_owner, shared_owner :: pid()}
          | :error
  def fetch_owner(ownership_server, [_ | _] = callers, key, timeout \\ 5000)
      when is_timeout(timeout) do
    GenServer.call(ownership_server, {:fetch_owner, callers, key}, timeout)
  end

  @doc """
  Gets all the keys owned by `owner_pid` with all their associated metadata.

  If `owner_pid` doesn't own any keys, then this function returns `default`.

  ## Examples

      iex> owner = spawn(fn -> Process.sleep(:infinity) end)
      iex> {:ok, server} = NimbleOwnership.start_link()
      iex> NimbleOwnership.get_and_update(server, owner, :my_key1, fn _ -> {:ok, 1} end)
      iex> NimbleOwnership.get_and_update(server, owner, :my_key2, fn _ -> {:ok, 2} end)
      iex> NimbleOwnership.get_owned(server, owner)
      %{my_key1: 1, my_key2: 2}
      iex> NimbleOwnership.get_owned(server, self(), :default)
      :default

  """
  @spec get_owned(server(), pid(), default, timeout()) :: %{key() => metadata()} | default
        when default: term()
  def get_owned(ownership_server, owner_pid, default \\ nil, timeout \\ 5000)
      when is_pid(owner_pid) and is_timeout(timeout) do
    GenServer.call(ownership_server, {:get_owned, owner_pid, default}, timeout)
  end

  @doc """
  Sets the ownership server to *private mode*.

  See [the module documentation](#module-modes) for more information.
  """
  @spec set_mode_to_private(server()) :: :ok
  def set_mode_to_private(ownership_server) do
    GenServer.call(ownership_server, {:set_mode, :private})
  end

  @doc """
  Sets the ownership server to *shared mode* and sets `shared_owner` as the shared owner.

  See [the module documentation](#module-modes) for more information.
  """
  @spec set_mode_to_shared(server(), pid()) :: :ok
  def set_mode_to_shared(ownership_server, shared_owner) when is_pid(shared_owner) do
    GenServer.call(ownership_server, {:set_mode, {:shared, shared_owner}})
  end

  @doc """
  Sets the owner PID to manual cleanup mode.

  If `owner_pid` doesn't own any keys, this function still sets its cleanup mode to manual.
  This means you can call this before any calls to `get_and_update/4` and it will still
  work as expected.

  > #### Leaks {: .error}
  >
  > If you set an owner PID to manual cleanup mode and you don't call `cleanup_owner/2`
  > before the owner PID goes down, then you will have a leak. This is because the ownership
  > server will not clean up the allowances and owned keys associated with the owner PID
  > when said PID goes down.

  See the [*Cleanup* section](#module-cleanup) in the module documentation.
  """
  @doc since: "0.3.0"
  @spec set_owner_to_manual_cleanup(server(), pid()) :: :ok
  def set_owner_to_manual_cleanup(ownership_server, owner_pid) do
    GenServer.call(ownership_server, {:set_owner_to_manual_cleanup, owner_pid})
  end

  @doc """
  Manually cleans up allowances and owned keys associated with `owner_pid`.

  This is meant to be used in conjunction with `set_owner_to_manual_cleanup/2`.

  See the [*Cleanup* section](#module-cleanup) in the module documentation.
  """
  @doc since: "0.3.0"
  @spec cleanup_owner(server(), pid()) :: :ok
  def cleanup_owner(ownership_server, owner_pid) when is_pid(owner_pid) do
    GenServer.call(ownership_server, {:cleanup_owner, owner_pid})
  end

  ## State

  defstruct [
    # The mode can be either :private, or {:shared, shared_owner_pid}.
    mode: :private,

    # This is a map of %{owner_pid => %{key => metadata}}. Its purpose is to track the metadata
    # under each key that a owner owns.
    owners: %{},

    # This tracks what to do when each owner goes down. It's a map of
    # %{owner_pid => :auto | :manual}.
    owner_cleanup: %{},

    # This is a map of %{allowed_pid => %{key => owner_pid}}. Its purpose is to track the keys
    # that a PID is allowed to access, alongside which the owner of those keys is.
    allowances: %{},

    # This is used to track which PIDs we're monitoring, to avoid double-monitoring.
    monitored_pids: MapSet.new()
  ]

  ## Callbacks

  @impl true
  def init([]) do
    {:ok, %__MODULE__{}}
  end

  @impl true
  def handle_call(call, from, state)

  def handle_call(
        {:allow, _pid_with_access, _pid_to_allow, key},
        _from,
        %__MODULE__{mode: {:shared, _shared_owner}} = state
      ) do
    error = %Error{key: key, reason: :cant_allow_in_shared_mode}
    {:reply, {:error, error}, state}
  end

  def handle_call(
        {:allow, pid_with_access, pid_to_allow, key},
        _from,
        %__MODULE__{mode: :private} = state
      ) do
    if state.owners[pid_to_allow][key] do
      error = %Error{key: key, reason: :already_an_owner}
      throw({:reply, {:error, error}, state})
    end

    owner_pid =
      cond do
        owner_pid = state.allowances[pid_with_access][key] ->
          owner_pid

        _meta = state.owners[pid_with_access][key] ->
          pid_with_access

        true ->
          throw({:reply, {:error, %Error{key: key, reason: :not_allowed}}, state})
      end

    case state.allowances[pid_to_allow][key] do
      # There's already another owner PID that is allowing "pid_to_allow" to use "key".
      other_owner_pid when is_pid(other_owner_pid) and other_owner_pid != owner_pid ->
        error = %Error{key: key, reason: {:already_allowed, other_owner_pid}}
        {:reply, {:error, error}, state}

      # "pid_to_allow" is already allowed access to "key" through the same "owner_pid",
      # so this is a no-op.
      ^owner_pid ->
        {:reply, :ok, state}

      nil ->
        state =
          state
          |> maybe_monitor_pid(pid_with_access)
          |> put_in([Access.key!(:allowances), Access.key(pid_to_allow, %{}), key], owner_pid)

        {:reply, :ok, state}
    end
  end

  def handle_call({:get_and_update, owner_pid, key, fun}, _from, %__MODULE__{} = state) do
    case state.mode do
      {:shared, shared_owner_pid} when shared_owner_pid != owner_pid ->
        error = %Error{key: key, reason: {:not_shared_owner, shared_owner_pid}}
        throw({:reply, {:error, error}, state})

      _ ->
        :ok
    end

    state = resolve_lazy_calls_for_key(state, key)

    if other_owner = state.allowances[owner_pid][key] do
      throw({:reply, {:error, %Error{key: key, reason: {:already_allowed, other_owner}}}, state})
    end

    case fun.(_meta_or_nil = state.owners[owner_pid][key]) do
      {get_value, new_meta} ->
        state = put_in(state, [Access.key!(:owners), Access.key(owner_pid, %{}), key], new_meta)

        # We should also monitor the new owner, if it hasn't already been monitored. That
        # can happen if that owner is already the owner of another key. We ALWAYS monitor,
        # so if owner_pid is already an owner we're already monitoring it.
        state =
          if not Map.has_key?(state.owner_cleanup, owner_pid) do
            _ref = Process.monitor(owner_pid)
            put_in(state.owner_cleanup[owner_pid], :auto)
          else
            state
          end

        {:reply, {:ok, get_value}, state}

      other ->
        message = """
        invalid return value from callback function. Expected nil or a tuple of the form \
        {get_value, update_value} (see the function's @spec), instead got: #{inspect(other)}\
        """

        {:reply, {:__raise__, %ArgumentError{message: message}}, state}
    end
  end

  def handle_call(
        {:fetch_owner, _callers, _key},
        _from,
        %__MODULE__{mode: {:shared, shared_owner_pid}} = state
      ) do
    {:reply, {:shared_owner, shared_owner_pid}, state}
  end

  def handle_call({:fetch_owner, callers, key}, _from, %__MODULE__{mode: :private} = state) do
    {owner, state} =
      case fetch_owner_once(state, callers, key) do
        nil ->
          state = resolve_lazy_calls_for_key(state, key)
          {fetch_owner_once(state, callers, key), state}

        owner ->
          {owner, state}
      end

    if is_nil(owner) do
      {:reply, :error, state}
    else
      {:reply, {:ok, owner}, state}
    end
  end

  def handle_call({:get_owned, owner_pid, default}, _from, %__MODULE__{} = state) do
    {:reply, state.owners[owner_pid] || default, state}
  end

  def handle_call({:set_mode, {:shared, shared_owner_pid}}, _from, %__MODULE__{} = state) do
    state = maybe_monitor_pid(state, shared_owner_pid)
    state = %__MODULE__{state | mode: {:shared, shared_owner_pid}}
    {:reply, :ok, state}
  end

  def handle_call({:set_mode, :private}, _from, %__MODULE__{} = state) do
    {:reply, :ok, %__MODULE__{state | mode: :private}}
  end

  def handle_call({:set_owner_to_manual_cleanup, owner_pid}, _from, %__MODULE__{} = state) do
    {:reply, :ok, put_in(state.owner_cleanup[owner_pid], :manual)}
  end

  def handle_call({:cleanup_owner, pid}, _from, %__MODULE__{} = state) do
    {:reply, :ok, pop_owner_and_clean_up_allowances(state, pid)}
  end

  @impl true
  def handle_info(msg, state)

  # The global owner went down, so we go back to private mode.
  def handle_info({:DOWN, _, _, down_pid, _}, %__MODULE__{mode: {:shared, down_pid}} = state) do
    {:noreply, %__MODULE__{state | mode: :private}}
  end

  # An owner went down, so we need to clean up all of its allowances as well as all its keys.
  def handle_info({:DOWN, _ref, _, down_pid, _}, state)
      when is_map_key(state.owners, down_pid) do
    case state.owner_cleanup[down_pid] || :auto do
      :manual ->
        {:noreply, state}

      :auto ->
        state = pop_owner_and_clean_up_allowances(state, down_pid)
        {:noreply, state}
    end
  end

  # A PID that we were monitoring went down. Let's just clean up all its allowances.
  def handle_info({:DOWN, _, _, down_pid, _}, state) do
    {_keys_and_values, state} = pop_in(state.allowances[down_pid])
    state = update_in(state.monitored_pids, &MapSet.delete(&1, down_pid))
    {:noreply, state}
  end

  ## Helpers

  defp pop_owner_and_clean_up_allowances(state, target_pid) do
    {_, state} = pop_in(state.owners[target_pid])
    {_, state} = pop_in(state.owner_cleanup[target_pid])

    allowances =
      Enum.reduce(state.allowances, state.allowances, fn {pid, allowances}, acc ->
        new_allowances =
          for {key, owner_pid} <- allowances,
              owner_pid != target_pid,
              into: %{},
              do: {key, owner_pid}

        Map.put(acc, pid, new_allowances)
      end)

    %__MODULE__{state | allowances: allowances}
  end

  defp maybe_monitor_pid(state, pid) do
    if pid in state.monitored_pids do
      state
    else
      Process.monitor(pid)
      update_in(state.monitored_pids, &MapSet.put(&1, pid))
    end
  end

  defp fetch_owner_once(state, callers, key) do
    Enum.find_value(callers, fn caller ->
      case state do
        %{owners: %{^caller => %{^key => _meta}}} -> caller
        %{allowances: %{^caller => %{^key => owner_pid}}} -> owner_pid
        _ -> nil
      end
    end)
  end

  defp resolve_lazy_calls_for_key(state, key) do
    updated_allowances =
      Enum.reduce(state.allowances, state.allowances, fn
        {fun, value}, allowances when is_function(fun, 0) and is_map_key(value, key) ->
          result =
            fun.()
            |> List.wrap()
            |> Enum.group_by(&is_pid/1)

          allowances =
            result
            |> Map.get(true, [])
            |> Enum.reduce(allowances, fn pid, allowances ->
              Map.update(allowances, pid, value, &Map.merge(&1, value))
            end)

          if Map.has_key?(allowances, false), do: Map.delete(allowances, fun), else: allowances

        _, allowances ->
          allowances
      end)

    %{state | allowances: updated_allowances}
  end
end
