defmodule Jido.AI.ToolAdapter do
  @moduledoc """
  Adapts Jido Actions into ReqLLM.Tool structs for LLM consumption.

  This module bridges Jido domain concepts (actions with schemas) to ReqLLM's
  tool representation.

  ## Design

  - **Schema-focused**: Tools use a noop callback; Jido owns execution via `Directive.ToolExec`
  - **Adapter pattern**: Converts `Jido.Action` behaviour → `ReqLLM.Tool` struct
  - **Single source of truth**: All action→tool conversion goes through this module

  ## Usage

      # Convert action modules to ReqLLM tools
      tools = Jido.AI.ToolAdapter.from_actions([
        MyApp.Actions.Calculator,
        MyApp.Actions.Search
      ])

      # With options
      tools = Jido.AI.ToolAdapter.from_actions(actions,
        prefix: "myapp_",
        filter: fn mod -> mod.category() == :search end
      )

      # Use in LLM call
      ReqLLM.stream_text(model, messages, tools: tools)

  ## Registry (DEPRECATED)

  The registry functions in this module are deprecated. Use `Jido.AI.Tools.Registry` instead:

      # Instead of:
      Jido.AI.ToolAdapter.register_action(MyAction)
      Jido.AI.ToolAdapter.get_action("name")

      # Use:
      Jido.AI.Tools.Registry.register_action(MyAction)
      Jido.AI.Tools.Registry.get("name")

  The `Jido.AI.Tools.Registry` module provides a unified registry for both
  Actions and simple Tools, with better integration with the Executor.
  """

  use Agent

  alias Jido.Action.Schema, as: ActionSchema

  require Logger

  @registry_name __MODULE__.Registry
  @max_retries 3

  # ============================================================================
  # Registry Management (DEPRECATED - use Jido.AI.Tools.Registry instead)
  # ============================================================================

  @doc """
  Starts the action registry agent.

  This is called automatically when needed. The registry stores action modules
  for runtime tool management.

  ## Deprecation Notice

  This function is deprecated. Use `Jido.AI.Tools.Registry` instead, which
  provides unified management for both Actions and Tools.
  """
  @deprecated "Use Jido.AI.Tools.Registry instead"
  @spec start_link(keyword()) :: Agent.on_start()
  def start_link(_opts \\ []) do
    Logger.warning("ToolAdapter.start_link/1 is deprecated. Use Jido.AI.Tools.Registry instead.")
    Agent.start_link(fn -> %{} end, name: @registry_name)
  end

  @doc """
  Ensures the registry is started, starting it if necessary.

  Returns `:ok` if the registry is available, `{:error, reason}` otherwise.

  ## Deprecation Notice

  This function is deprecated. Use `Jido.AI.Tools.Registry.ensure_started/0` instead.
  """
  @deprecated "Use Jido.AI.Tools.Registry.ensure_started/0 instead"
  @spec ensure_started() :: :ok | {:error, term()}
  def ensure_started do
    case Process.whereis(@registry_name) do
      nil ->
        case Agent.start_link(fn -> %{} end, name: @registry_name) do
          {:ok, _pid} -> :ok
          {:error, {:already_started, _pid}} -> :ok
          {:error, reason} -> {:error, reason}
        end

      _pid ->
        :ok
    end
  end

  @doc """
  Registers a single action module in the registry.

  The action is stored by its tool name (from `action_module.name()`).

  ## Deprecation Notice

  This function is deprecated. Use `Jido.AI.Tools.Registry.register_action/1` instead.

  ## Example

      :ok = Jido.AI.ToolAdapter.register_action(MyApp.Actions.Calculator)
  """
  @deprecated "Use Jido.AI.Tools.Registry.register_action/1 instead"
  @spec register_action(module()) :: :ok
  def register_action(action_module) when is_atom(action_module) do
    Logger.warning("ToolAdapter.register_action/1 is deprecated. Use Jido.AI.Tools.Registry.register_action/1 instead.")

    name = action_module.name()
    safe_update(fn state -> Map.put(state, name, action_module) end)
  end

  @doc """
  Registers multiple action modules in the registry.

  ## Deprecation Notice

  This function is deprecated. Use `Jido.AI.Tools.Registry.register_actions/1` instead.

  ## Example

      :ok = Jido.AI.ToolAdapter.register_actions([
        MyApp.Actions.Calculator,
        MyApp.Actions.Search
      ])
  """
  @deprecated "Use Jido.AI.Tools.Registry.register_actions/1 instead"
  @spec register_actions([module()]) :: :ok
  def register_actions(action_modules) when is_list(action_modules) do
    Logger.warning(
      "ToolAdapter.register_actions/1 is deprecated. Use Jido.AI.Tools.Registry.register_actions/1 instead."
    )

    Enum.each(action_modules, fn mod ->
      name = mod.name()
      safe_update(fn state -> Map.put(state, name, mod) end)
    end)
  end

  @doc """
  Unregisters an action module from the registry.

  ## Deprecation Notice

  This function is deprecated. Use `Jido.AI.Tools.Registry.unregister/1` instead.

  ## Example

      :ok = Jido.AI.ToolAdapter.unregister_action(MyApp.Actions.Calculator)
  """
  @deprecated "Use Jido.AI.Tools.Registry.unregister/1 instead"
  @spec unregister_action(module()) :: :ok
  def unregister_action(action_module) when is_atom(action_module) do
    Logger.warning("ToolAdapter.unregister_action/1 is deprecated. Use Jido.AI.Tools.Registry.unregister/1 instead.")

    name = action_module.name()
    safe_update(fn state -> Map.delete(state, name) end)
  end

  @doc """
  Lists all registered action modules.

  Returns a list of `{name, module}` tuples.

  ## Deprecation Notice

  This function is deprecated. Use `Jido.AI.Tools.Registry.list_actions/0` instead.

  ## Example

      actions = Jido.AI.ToolAdapter.list_actions()
      # => [{"calculator", MyApp.Actions.Calculator}, {"search", MyApp.Actions.Search}]
  """
  @deprecated "Use Jido.AI.Tools.Registry.list_actions/0 instead"
  @spec list_actions() :: [{String.t(), module()}]
  def list_actions do
    Logger.warning("ToolAdapter.list_actions/0 is deprecated. Use Jido.AI.Tools.Registry.list_actions/0 instead.")

    safe_get(fn state -> Map.to_list(state) end)
  end

  @doc """
  Gets an action module by its tool name.

  Returns `{:ok, module}` if found, `{:error, :not_found}` otherwise.

  ## Deprecation Notice

  This function is deprecated. Use `Jido.AI.Tools.Registry.get/1` instead.

  ## Example

      {:ok, module} = Jido.AI.ToolAdapter.get_action("calculator")
      {:error, :not_found} = Jido.AI.ToolAdapter.get_action("unknown")
  """
  @deprecated "Use Jido.AI.Tools.Registry.get/1 instead"
  @spec get_action(String.t()) :: {:ok, module()} | {:error, :not_found}
  def get_action(tool_name) when is_binary(tool_name) do
    Logger.warning("ToolAdapter.get_action/1 is deprecated. Use Jido.AI.Tools.Registry.get/1 instead.")

    case safe_get(fn state -> Map.get(state, tool_name) end) do
      nil -> {:error, :not_found}
      module -> {:ok, module}
    end
  end

  @doc """
  Clears all registered actions from the registry.

  ## Deprecation Notice

  This function is deprecated. Use `Jido.AI.Tools.Registry.clear/0` instead.

  ## Example

      :ok = Jido.AI.ToolAdapter.clear_registry()
  """
  @deprecated "Use Jido.AI.Tools.Registry.clear/0 instead"
  @spec clear_registry() :: :ok
  def clear_registry do
    Logger.warning("ToolAdapter.clear_registry/0 is deprecated. Use Jido.AI.Tools.Registry.clear/0 instead.")

    safe_update(fn _state -> %{} end)
  end

  @doc """
  Converts all registered actions to ReqLLM.Tool structs.

  Accepts the same options as `from_actions/2`.

  ## Deprecation Notice

  This function is deprecated. Use `Jido.AI.Tools.Registry.to_reqllm_tools/0` instead.

  ## Options

    * `:prefix` - String prefix to add to tool names
    * `:filter` - Function `(module -> boolean)` to filter actions

  ## Example

      tools = Jido.AI.ToolAdapter.to_tools()
      tools = Jido.AI.ToolAdapter.to_tools(prefix: "myapp_")
  """
  @deprecated "Use Jido.AI.Tools.Registry.to_reqllm_tools/0 instead"
  @spec to_tools(keyword()) :: [ReqLLM.Tool.t()]
  def to_tools(opts \\ []) do
    Logger.warning("ToolAdapter.to_tools/1 is deprecated. Use Jido.AI.Tools.Registry.to_reqllm_tools/0 instead.")

    modules =
      safe_get(fn state -> Map.to_list(state) end)
      |> Enum.map(fn {_name, module} -> module end)

    from_actions(modules, opts)
  end

  # ============================================================================
  # Action Conversion
  # ============================================================================

  @doc """
  Converts a list of Jido.Action modules into ReqLLM.Tool structs.

  The returned tools use a noop callback—they're purely for describing available
  actions to the LLM. Actual execution happens via `Jido.AI.Directive.ToolExec`.

  ## Arguments

    * `action_modules` - List of modules implementing the `Jido.Action` behaviour
    * `opts` - Optional keyword list of options

  ## Options

    * `:prefix` - String prefix to add to all tool names (e.g., `"myapp_"`)
    * `:filter` - Function `(module -> boolean)` to filter which actions to include

  ## Returns

    A list of `ReqLLM.Tool` structs

  ## Examples

      # Basic usage
      tools = Jido.AI.ToolAdapter.from_actions([MyApp.Actions.Add, MyApp.Actions.Search])

      # With prefix
      tools = Jido.AI.ToolAdapter.from_actions(actions, prefix: "calc_")
      # Tool names become "calc_add", "calc_search", etc.

      # With filter
      tools = Jido.AI.ToolAdapter.from_actions(actions,
        filter: fn mod -> mod.category() == :math end
      )
  """
  @spec from_actions([module()], keyword()) :: [ReqLLM.Tool.t()]
  def from_actions(action_modules, opts \\ [])

  def from_actions(action_modules, opts) when is_list(action_modules) do
    prefix = Keyword.get(opts, :prefix)
    filter_fn = Keyword.get(opts, :filter)

    action_modules
    |> maybe_filter(filter_fn)
    |> Enum.map(fn module -> from_action(module, prefix: prefix) end)
  end

  @doc """
  Converts a single Jido.Action module into a ReqLLM.Tool struct.

  ## Arguments

    * `action_module` - A module implementing the `Jido.Action` behaviour
    * `opts` - Optional keyword list of options

  ## Options

    * `:prefix` - String prefix to add to the tool name

  ## Returns

    A `ReqLLM.Tool` struct
  """
  @spec from_action(module(), keyword()) :: ReqLLM.Tool.t()
  def from_action(action_module, opts \\ [])

  def from_action(action_module, opts) when is_atom(action_module) do
    prefix = Keyword.get(opts, :prefix)
    base_name = action_module.name()
    name = if prefix, do: "#{prefix}#{base_name}", else: base_name

    ReqLLM.Tool.new!(
      name: name,
      description: action_module.description(),
      parameter_schema: build_json_schema(action_module.schema()),
      callback: &noop_callback/1
    )
  end

  @doc """
  Looks up an action module by tool name from a list of modules.

  This is useful when you have a list of action modules and need to find
  the one matching a tool call from the LLM.

  ## Arguments

    * `tool_name` - The name of the tool to look up
    * `action_modules` - List of action modules to search

  ## Returns

    * `{:ok, module}` if found
    * `{:error, :not_found}` if no module matches

  ## Example

      {:ok, module} = Jido.AI.ToolAdapter.lookup_action("calculator", [
        MyApp.Actions.Calculator,
        MyApp.Actions.Search
      ])
  """
  @spec lookup_action(String.t(), [module()]) :: {:ok, module()} | {:error, :not_found}
  def lookup_action(tool_name, action_modules) when is_binary(tool_name) and is_list(action_modules) do
    case Enum.find(action_modules, fn mod -> mod.name() == tool_name end) do
      nil -> {:error, :not_found}
      module -> {:ok, module}
    end
  end

  # ============================================================================
  # Private Functions - Agent Operations with Retry
  # ============================================================================

  # Wraps Agent.get with retry logic to handle race conditions
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
    ensure_started()
    Agent.update(@registry_name, fun)
  end

  # ============================================================================
  # Private Functions - Schema and Filtering
  # ============================================================================

  defp maybe_filter(modules, nil), do: modules

  defp maybe_filter(modules, filter_fn) when is_function(filter_fn, 1) do
    Enum.filter(modules, filter_fn)
  end

  defp build_json_schema(schema) do
    ActionSchema.to_json_schema(schema)
  end

  defp noop_callback(_args) do
    {:error, :not_executed_via_callback}
  end
end
