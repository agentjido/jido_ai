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
  """

  alias Jido.Action.Schema, as: ActionSchema

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

    * `:prefix` - String prefix to add to the tool name (e.g., `"myapp_"`)

  ## Returns

    A `ReqLLM.Tool` struct

  ## Example

      tool = Jido.AI.ToolAdapter.from_action(MyApp.Actions.Calculator, prefix: "v2_")
      # => %ReqLLM.Tool{name: "v2_calculator", ...}
  """
  @spec from_action(module(), keyword()) :: ReqLLM.Tool.t()
  def from_action(action_module, opts \\ [])

  def from_action(action_module, opts) when is_atom(action_module) do
    prefix = Keyword.get(opts, :prefix)

    ReqLLM.Tool.new!(
      name: apply_prefix(action_module.name(), prefix),
      description: action_module.description(),
      parameter_schema: build_json_schema(action_module.schema()),
      callback: &noop_callback/1
    )
  end

  @doc """
  Looks up an action module by tool name from a list of action modules.

  Useful for finding which action module corresponds to a tool name returned
  by an LLM.

  ## Arguments

    * `tool_name` - The name of the tool to look up
    * `action_modules` - List of action modules to search

  ## Returns

    * `{:ok, module}` - If found
    * `{:error, :not_found}` - If no action module has that tool name

  ## Example

      {:ok, module} = ToolAdapter.lookup_action("calculator", [Calculator, Search])
      # => {:ok, Calculator}

      {:error, :not_found} = ToolAdapter.lookup_action("unknown", [Calculator])
      # => {:error, :not_found}
  """
  @spec lookup_action(String.t(), [module()]) :: {:ok, module()} | {:error, :not_found}
  def lookup_action(tool_name, action_modules) when is_binary(tool_name) and is_list(action_modules) do
    case Enum.find(action_modules, fn mod -> mod.name() == tool_name end) do
      nil -> {:error, :not_found}
      module -> {:ok, module}
    end
  end

  # ============================================================================
  # Private Functions - Schema and Filtering
  # ============================================================================

  defp maybe_filter(modules, nil), do: modules

  defp maybe_filter(modules, filter_fn) when is_function(filter_fn, 1) do
    Enum.filter(modules, filter_fn)
  end

  defp build_json_schema(schema) do
    case ActionSchema.to_json_schema(schema) do
      empty when empty == %{} ->
        %{"type" => "object", "properties" => %{}}

      json_schema ->
        json_schema
    end
  end

  defp noop_callback(_args), do: {:ok, %{}}

  defp apply_prefix(name, nil), do: name
  defp apply_prefix(name, prefix) when is_binary(prefix), do: prefix <> name
end
