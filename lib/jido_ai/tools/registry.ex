defmodule Jido.AI.Tools.Registry do
  @moduledoc """
  Registry for managing Jido.Action modules as AI tools.

  This registry provides a single source of truth for action lookup during LLM
  tool execution. When an LLM returns a tool call by name, the executor uses
  this registry to find the corresponding Action module.

  ## Design

  - **Actions only**: All entries are Jido.Action modules
  - **Agent-based**: Uses Elixir Agent for runtime state, auto-starts on first access
  - **Validated**: Modules are validated on registration to ensure they implement
    the Action behavior

  ## Usage

      # Register actions
      Registry.register(MyApp.Actions.Calculator)
      Registry.register_action(MyApp.Actions.Search)
      Registry.register_actions([MyApp.Actions.Add, MyApp.Actions.Multiply])

      # Lookup by name
      {:ok, MyApp.Actions.Calculator} = Registry.get("calculator")

      # List all
      Registry.list_all()
      # => [{"calculator", MyApp.Actions.Calculator}, ...]

      # Convert to ReqLLM tools
      tools = Registry.to_reqllm_tools()
      ReqLLM.stream_text(model, messages, tools: tools)

  ## Relationship to ToolAdapter

  `Jido.AI.ToolAdapter` handles conversion of Actions to ReqLLM.Tool format.
  This Registry uses ToolAdapter internally for that conversion.

  ## Telemetry

  The registry emits telemetry events for monitoring:

  - `[:jido, :ai, :registry, :register]` - Module registered
    - Metadata: `%{name: String.t(), module: module()}`
  - `[:jido, :ai, :registry, :unregister]` - Module unregistered
    - Metadata: `%{name: String.t()}`

  See `notes/decisions/adr-001-tools-registry-design.md` for design rationale.
  """

  use Agent

  alias Jido.AI.ToolAdapter

  require Logger

  @registry_name __MODULE__
  @max_retries 3

  @type entry :: {String.t(), module()}

  # ============================================================================
  # Registry Lifecycle
  # ============================================================================

  @doc """
  Starts the registry agent.

  This is called automatically when needed. You typically don't need to call
  this directly.
  """
  @spec start_link(keyword()) :: Agent.on_start()
  def start_link(_opts \\ []) do
    Agent.start_link(fn -> %{} end, name: @registry_name)
  end

  @doc """
  Ensures the registry is started, starting it if necessary.

  Returns `:ok` if the registry is available, `{:error, reason}` otherwise.
  """
  @spec ensure_started() :: :ok | {:error, term()}
  def ensure_started do
    case Process.whereis(@registry_name) do
      nil ->
        case start_link() do
          {:ok, _pid} -> :ok
          {:error, {:already_started, _pid}} -> :ok
          {:error, reason} -> {:error, reason}
        end

      _pid ->
        :ok
    end
  end

  # ============================================================================
  # Registration
  # ============================================================================

  @doc """
  Registers a Jido.Action module.

  Validates that the module implements the `Jido.Action` behavior before
  registering. The action is stored by its tool name (from `module.name()`).

  ## Examples

      :ok = Registry.register(MyApp.Actions.Calculator)
      {:error, :not_an_action} = Registry.register(NotAnAction)
  """
  @spec register(module()) :: :ok | {:error, :not_an_action}
  def register(module) when is_atom(module) do
    if action?(module) do
      name = module.name()
      emit_telemetry(:register, %{name: name, module: module})
      safe_update(fn state -> Map.put(state, name, module) end)
    else
      {:error, :not_an_action}
    end
  end

  @doc """
  Registers a Jido.Action module.

  Alias for `register/1` for backwards compatibility.

  ## Examples

      :ok = Registry.register_action(MyApp.Actions.Calculator)
      {:error, :not_an_action} = Registry.register_action(NotAnAction)
  """
  @spec register_action(module()) :: :ok | {:error, :not_an_action}
  def register_action(module) when is_atom(module) do
    register(module)
  end

  @doc """
  Registers multiple Jido.Action modules.

  ## Examples

      :ok = Registry.register_actions([MyApp.Actions.Add, MyApp.Actions.Search])
  """
  @spec register_actions([module()]) :: :ok | {:error, term()}
  def register_actions(modules) when is_list(modules) do
    Enum.reduce_while(modules, :ok, fn module, :ok ->
      case register(module) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  # ============================================================================
  # Lookup
  # ============================================================================

  @doc """
  Looks up a registered Action module by its tool name.

  Returns `{:ok, module}` if found, `{:error, :not_found}` if not registered.

  ## Examples

      {:ok, MyApp.Actions.Calculator} = Registry.get("calculator")
      {:error, :not_found} = Registry.get("unknown")
  """
  @spec get(String.t()) :: {:ok, module()} | {:error, :not_found}
  def get(name) when is_binary(name) do
    case safe_get(fn state -> Map.get(state, name) end) do
      nil -> {:error, :not_found}
      module -> {:ok, module}
    end
  end

  @doc """
  Looks up a registered Action module by name, raising if not found.

  ## Examples

      MyApp.Actions.Calculator = Registry.get!("calculator")
      Registry.get!("unknown")  # raises KeyError
  """
  @spec get!(String.t()) :: module()
  def get!(name) when is_binary(name) do
    case get(name) do
      {:ok, result} -> result
      {:error, :not_found} -> raise KeyError, key: name, term: __MODULE__
    end
  end

  # ============================================================================
  # Listing
  # ============================================================================

  @doc """
  Lists all registered Action modules.

  Returns a list of `{name, module}` tuples.

  ## Examples

      Registry.list_all()
      # => [{"calculator", MyApp.Actions.Calculator},
      #     {"search", MyApp.Actions.Search}]
  """
  @spec list_all() :: [entry()]
  def list_all do
    safe_get(fn state ->
      state
      |> Enum.map(fn {name, module} -> {name, module} end)
      |> Enum.sort_by(&elem(&1, 0))
    end)
  end

  @doc """
  Lists all registered Action modules.

  Alias for `list_all/0` for backwards compatibility.

  ## Examples

      Registry.list_actions()
      # => [{"calculator", MyApp.Actions.Calculator}]
  """
  @spec list_actions() :: [entry()]
  def list_actions do
    list_all()
  end

  # ============================================================================
  # ReqLLM Conversion
  # ============================================================================

  @doc """
  Converts all registered Action modules to ReqLLM.Tool structs.

  Uses `ToolAdapter.from_action/1` for conversion. Returns a list suitable
  for passing to ReqLLM.

  ## Examples

      tools = Registry.to_reqllm_tools()
      ReqLLM.stream_text(model, messages, tools: tools)
  """
  @spec to_reqllm_tools() :: [ReqLLM.Tool.t()]
  def to_reqllm_tools do
    safe_get(fn state ->
      Enum.map(state, fn {_name, module} -> ToolAdapter.from_action(module) end)
    end)
  end

  # ============================================================================
  # Utility Functions
  # ============================================================================

  @doc """
  Clears all registered modules from the registry.

  Useful for testing or resetting state.

  ## Examples

      :ok = Registry.clear()
  """
  @spec clear() :: :ok
  def clear do
    safe_update(fn _state -> %{} end)
  end

  @doc """
  Unregisters a module by its tool name.

  Returns `:ok` whether or not the name was registered.

  ## Examples

      :ok = Registry.unregister("calculator")
  """
  @spec unregister(String.t()) :: :ok
  def unregister(name) when is_binary(name) do
    emit_telemetry(:unregister, %{name: name})
    safe_update(fn state -> Map.delete(state, name) end)
  end

  # ============================================================================
  # Private Helpers - Telemetry
  # ============================================================================

  @doc false
  @spec emit_telemetry(:register | :unregister, map()) :: :ok
  defp emit_telemetry(operation, metadata) do
    :telemetry.execute(
      [:jido, :ai, :registry, operation],
      %{system_time: System.system_time()},
      metadata
    )
  end

  # ============================================================================
  # Private Helpers - Agent Operations with Retry
  # ============================================================================

  @doc false
  defp safe_get(fun, retries \\ @max_retries)

  @doc false
  defp safe_get(fun, retries) when retries > 0 do
    ensure_started()

    try do
      Agent.get(@registry_name, fun)
    catch
      :exit, {:noproc, _} ->
        attempt = @max_retries - retries + 1

        Logger.warning(
          "Registry agent not available, retrying",
          attempt: attempt,
          max_retries: @max_retries,
          operation: :get
        )

        safe_get(fun, retries - 1)
    end
  end

  @doc false
  defp safe_get(fun, 0) do
    ensure_started()
    Agent.get(@registry_name, fun)
  end

  @doc false
  defp safe_update(fun, retries \\ @max_retries)

  @doc false
  defp safe_update(fun, retries) when retries > 0 do
    ensure_started()

    try do
      Agent.update(@registry_name, fun)
    catch
      :exit, {:noproc, _} ->
        attempt = @max_retries - retries + 1

        Logger.warning(
          "Registry agent not available, retrying",
          attempt: attempt,
          max_retries: @max_retries,
          operation: :update
        )

        safe_update(fun, retries - 1)
    end
  end

  @doc false
  defp safe_update(fun, 0) do
    ensure_started()
    Agent.update(@registry_name, fun)
  end

  # ============================================================================
  # Private Helpers - Module Introspection
  # ============================================================================

  @doc false
  defp action?(module) do
    behaviours = module_behaviours(module)

    Jido.Action in behaviours or has_action_functions?(module)
  end

  @doc false
  defp has_action_functions?(module) do
    function_exported?(module, :name, 0) and
      function_exported?(module, :description, 0) and
      function_exported?(module, :schema, 0) and
      function_exported?(module, :run, 2)
  end

  @doc false
  defp module_behaviours(module) do
    module.module_info(:attributes)
    |> Keyword.get_values(:behaviour)
    |> List.flatten()
  rescue
    _ -> []
  end
end
