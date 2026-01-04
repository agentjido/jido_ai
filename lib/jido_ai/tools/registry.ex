defmodule Jido.AI.Tools.Registry do
  @moduledoc """
  Unified registry for managing both Jido.Actions and Jido.AI.Tools.Tool modules.

  This registry provides a single source of truth for tool lookup during LLM
  tool execution. When an LLM returns a tool call by name, the executor uses
  this registry to find the corresponding module and determine how to execute it.

  ## Design

  - **Unified storage**: Both Actions and Tools are stored in the same registry
  - **Type-aware**: Each entry is tagged with its type (`:action` or `:tool`)
  - **Agent-based**: Uses Elixir Agent for runtime state, auto-starts on first access
  - **Validated**: Modules are validated on registration to ensure they implement
    the correct behavior

  ## Usage

      # Register modules (auto-detects type)
      Registry.register(MyApp.Actions.Calculator)
      Registry.register(MyApp.Tools.Search)

      # Or register explicitly by type
      Registry.register_action(MyApp.Actions.Calculator)
      Registry.register_tool(MyApp.Tools.Search)

      # Lookup by name
      {:ok, {:action, MyApp.Actions.Calculator}} = Registry.get("calculator")
      {:ok, {:tool, MyApp.Tools.Search}} = Registry.get("search")

      # List all
      Registry.list_all()
      # => [{"calculator", :action, MyApp.Actions.Calculator}, ...]

      # Convert to ReqLLM tools
      tools = Registry.to_reqllm_tools()
      ReqLLM.stream_text(model, messages, tools: tools)

  ## Relationship to ToolAdapter

  `Jido.AI.ToolAdapter` handles conversion of Actions to ReqLLM.Tool format.
  This Registry uses ToolAdapter internally for that conversion but provides
  a unified interface for managing both Actions and Tools.

  See `notes/decisions/adr-001-tools-registry-design.md` for design rationale.
  """

  use Agent

  alias Jido.AI.ToolAdapter
  alias Jido.AI.Tools.Tool

  @registry_name __MODULE__
  @max_retries 3

  @type tool_type :: :action | :tool
  @type entry :: {String.t(), tool_type(), module()}

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
  Registers a module, auto-detecting whether it's an Action or Tool.

  Checks if the module implements `Jido.Action` behavior first, then
  `Jido.AI.Tools.Tool`. Returns an error if neither behavior is implemented.

  ## Examples

      :ok = Registry.register(MyApp.Actions.Calculator)
      :ok = Registry.register(MyApp.Tools.Search)
      {:error, :invalid_module} = Registry.register(SomeRandomModule)
  """
  @spec register(module()) :: :ok | {:error, :invalid_module}
  def register(module) when is_atom(module) do
    cond do
      action?(module) -> register_action(module)
      tool?(module) -> register_tool(module)
      true -> {:error, :invalid_module}
    end
  end

  @doc """
  Registers a Jido.Action module.

  Validates that the module implements the `Jido.Action` behavior before
  registering. The action is stored by its tool name (from `module.name()`).

  ## Examples

      :ok = Registry.register_action(MyApp.Actions.Calculator)
      {:error, :not_an_action} = Registry.register_action(NotAnAction)
  """
  @spec register_action(module()) :: :ok | {:error, :not_an_action}
  def register_action(module) when is_atom(module) do
    if action?(module) do
      name = module.name()
      safe_update(fn state -> Map.put(state, name, {:action, module}) end)
    else
      {:error, :not_an_action}
    end
  end

  @doc """
  Registers multiple Jido.Action modules.

  ## Examples

      :ok = Registry.register_actions([MyApp.Actions.Add, MyApp.Actions.Search])
  """
  @spec register_actions([module()]) :: :ok | {:error, term()}
  def register_actions(modules) when is_list(modules) do
    Enum.reduce_while(modules, :ok, fn module, :ok ->
      case register_action(module) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  @doc """
  Registers a Jido.AI.Tools.Tool module.

  Validates that the module implements the `Jido.AI.Tools.Tool` behavior before
  registering. The tool is stored by its name (from `module.name()`).

  ## Examples

      :ok = Registry.register_tool(MyApp.Tools.Calculator)
      {:error, :not_a_tool} = Registry.register_tool(NotATool)
  """
  @spec register_tool(module()) :: :ok | {:error, :not_a_tool}
  def register_tool(module) when is_atom(module) do
    if tool?(module) do
      name = module.name()
      safe_update(fn state -> Map.put(state, name, {:tool, module}) end)
    else
      {:error, :not_a_tool}
    end
  end

  @doc """
  Registers multiple Jido.AI.Tools.Tool modules.

  ## Examples

      :ok = Registry.register_tools([MyApp.Tools.Search, MyApp.Tools.Weather])
  """
  @spec register_tools([module()]) :: :ok | {:error, term()}
  def register_tools(modules) when is_list(modules) do
    Enum.reduce_while(modules, :ok, fn module, :ok ->
      case register_tool(module) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  # ============================================================================
  # Lookup
  # ============================================================================

  @doc """
  Looks up a registered module by its tool name.

  Returns `{:ok, {type, module}}` if found, where type is `:action` or `:tool`.
  Returns `{:error, :not_found}` if not registered.

  ## Examples

      {:ok, {:action, MyApp.Actions.Calculator}} = Registry.get("calculator")
      {:ok, {:tool, MyApp.Tools.Search}} = Registry.get("search")
      {:error, :not_found} = Registry.get("unknown")
  """
  @spec get(String.t()) :: {:ok, {tool_type(), module()}} | {:error, :not_found}
  def get(name) when is_binary(name) do
    case safe_get(fn state -> Map.get(state, name) end) do
      nil -> {:error, :not_found}
      {type, module} -> {:ok, {type, module}}
    end
  end

  @doc """
  Looks up a registered module by name, raising if not found.

  ## Examples

      {:action, MyApp.Actions.Calculator} = Registry.get!("calculator")
      Registry.get!("unknown")  # raises KeyError
  """
  @spec get!(String.t()) :: {tool_type(), module()}
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
  Lists all registered modules.

  Returns a list of `{name, type, module}` tuples.

  ## Examples

      Registry.list_all()
      # => [{"calculator", :action, MyApp.Actions.Calculator},
      #     {"search", :tool, MyApp.Tools.Search}]
  """
  @spec list_all() :: [entry()]
  def list_all do
    safe_get(fn state ->
      state
      |> Enum.map(fn {name, {type, module}} -> {name, type, module} end)
      |> Enum.sort_by(&elem(&1, 0))
    end)
  end

  @doc """
  Lists all registered Action modules.

  Returns a list of `{name, module}` tuples for actions only.

  ## Examples

      Registry.list_actions()
      # => [{"calculator", MyApp.Actions.Calculator}]
  """
  @spec list_actions() :: [{String.t(), module()}]
  def list_actions do
    safe_get(fn state ->
      state
      |> Enum.filter(fn {_name, {type, _module}} -> type == :action end)
      |> Enum.map(fn {name, {_type, module}} -> {name, module} end)
      |> Enum.sort_by(&elem(&1, 0))
    end)
  end

  @doc """
  Lists all registered Tool modules.

  Returns a list of `{name, module}` tuples for tools only.

  ## Examples

      Registry.list_tools()
      # => [{"search", MyApp.Tools.Search}]
  """
  @spec list_tools() :: [{String.t(), module()}]
  def list_tools do
    safe_get(fn state ->
      state
      |> Enum.filter(fn {_name, {type, _module}} -> type == :tool end)
      |> Enum.map(fn {name, {_type, module}} -> {name, module} end)
      |> Enum.sort_by(&elem(&1, 0))
    end)
  end

  # ============================================================================
  # ReqLLM Conversion
  # ============================================================================

  @doc """
  Converts all registered modules to ReqLLM.Tool structs.

  Uses `ToolAdapter.from_action/1` for Actions and `Tool.to_reqllm_tool/1`
  for Tools. Returns a combined list suitable for passing to ReqLLM.

  ## Examples

      tools = Registry.to_reqllm_tools()
      ReqLLM.stream_text(model, messages, tools: tools)
  """
  @spec to_reqllm_tools() :: [ReqLLM.Tool.t()]
  def to_reqllm_tools do
    safe_get(fn state ->
      Enum.map(state, &convert_to_reqllm_tool/1)
    end)
  end

  defp convert_to_reqllm_tool({_name, {:action, module}}), do: ToolAdapter.from_action(module)
  defp convert_to_reqllm_tool({_name, {:tool, module}}), do: Tool.to_reqllm_tool(module)

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
    safe_update(fn state -> Map.delete(state, name) end)
  end

  # ============================================================================
  # Private Helpers - Agent Operations with Retry
  # ============================================================================

  # Wraps Agent.get with retry logic to handle race conditions
  # where the agent might not be available between ensure_started and the call
  defp safe_get(fun, retries \\ @max_retries)

  defp safe_get(fun, retries) when retries > 0 do
    ensure_started()

    try do
      Agent.get(@registry_name, fun)
    catch
      :exit, {:noproc, _} ->
        safe_get(fun, retries - 1)
    end
  end

  defp safe_get(fun, 0) do
    # Last attempt - let it fail if it fails
    ensure_started()
    Agent.get(@registry_name, fun)
  end

  # Wraps Agent.update with retry logic
  defp safe_update(fun, retries \\ @max_retries)

  defp safe_update(fun, retries) when retries > 0 do
    ensure_started()

    try do
      Agent.update(@registry_name, fun)
    catch
      :exit, {:noproc, _} ->
        safe_update(fun, retries - 1)
    end
  end

  defp safe_update(fun, 0) do
    # Last attempt - let it fail if it fails
    ensure_started()
    Agent.update(@registry_name, fun)
  end

  # ============================================================================
  # Private Helpers - Module Introspection
  # ============================================================================

  # Check if a module implements the Jido.Action behavior
  # We check for Jido.Action in behaviours first, then fall back to function check
  # for Actions that may not explicitly declare the behavior
  defp action?(module) do
    behaviours = module_behaviours(module)

    Jido.Action in behaviours or
      (has_action_functions?(module) and Jido.AI.Tools.Tool not in behaviours)
  end

  defp has_action_functions?(module) do
    function_exported?(module, :name, 0) and
      function_exported?(module, :description, 0) and
      function_exported?(module, :schema, 0) and
      function_exported?(module, :run, 2)
  end

  # Check if a module implements the Jido.AI.Tools.Tool behavior
  defp tool?(module) do
    behaviours = module_behaviours(module)
    Jido.AI.Tools.Tool in behaviours
  end

  defp module_behaviours(module) do
    module.module_info(:attributes)
    |> Keyword.get_values(:behaviour)
    |> List.flatten()
  rescue
    _ -> []
  end
end
