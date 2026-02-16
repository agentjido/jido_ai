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
    * `:strict` - Whether to enable strict mode on the tools. When not set,
      auto-detects based on each action's `strict?/0` callback (defaults to `false`).

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
    explicit_strict = Keyword.fetch(opts, :strict)

    tools =
      action_modules
      |> maybe_filter(filter_fn)
      |> Enum.map(fn module ->
        strict =
          case explicit_strict do
            {:ok, val} -> val
            :error -> infer_strict?(module)
          end

        from_action(module, prefix: prefix, strict: strict)
      end)

    # Check for duplicate tool names
    names = Enum.map(tools, & &1.name)
    duplicates = names -- Enum.uniq(names)

    if duplicates != [] do
      raise ArgumentError,
            "Duplicate tool names detected: #{inspect(Enum.uniq(duplicates))}. " <>
              "Each action must have a unique name."
    end

    tools
  end

  @doc """
  Converts a single Jido.Action module into a ReqLLM.Tool struct.

  ## Arguments

    * `action_module` - A module implementing the `Jido.Action` behaviour
    * `opts` - Optional keyword list of options

  ## Options

    * `:prefix` - String prefix to add to the tool name (e.g., `"myapp_"`)
    * `:strict` - Whether to enable strict mode on the tool. When not set,
      auto-detects based on the action's `strict?/0` callback (defaults to `false`).

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

    strict =
      Keyword.get_lazy(opts, :strict, fn -> infer_strict?(action_module) end)

    ReqLLM.Tool.new!(
      name: apply_prefix(action_module.name(), prefix),
      description: action_module.description(),
      parameter_schema: build_json_schema(action_module.schema()),
      callback: &noop_callback/1,
      strict: strict
    )
  end

  @doc """
  Normalizes tool input into an action lookup map (`%{name => module}`).

  Accepts any of the common tool container shapes used by actions/skills:

  - `nil` -> `%{}`
  - `%{"tool_name" => MyAction}` -> unchanged
  - `%{tool_name: MyAction}` -> `%{"tool_name" => MyAction}` when values are modules
  - `[MyAction, OtherAction]` -> `%{"my_action" => MyAction, "other_action" => OtherAction}`
  - `MyAction` -> `%{"my_action" => MyAction}`
  """
  @spec to_action_map(nil | map() | [module()] | module()) :: %{String.t() => module()}
  def to_action_map(nil), do: %{}

  def to_action_map(%{} = tools) do
    cond do
      Enum.all?(tools, fn {name, mod} -> is_binary(name) and is_atom(mod) end) ->
        tools

      true ->
        tools
        |> Map.values()
        |> to_action_map()
    end
  end

  def to_action_map(modules) when is_list(modules) do
    modules
    |> Enum.filter(&is_atom/1)
    |> Map.new(fn module -> {module.name(), module} end)
  end

  def to_action_map(module) when is_atom(module) do
    %{module.name() => module}
  end

  def to_action_map(_), do: %{}

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
  @spec lookup_action(String.t(), [module()], keyword()) :: {:ok, module()} | {:error, :not_found}
  def lookup_action(tool_name, action_modules, opts \\ [])

  def lookup_action(tool_name, action_modules, opts) when is_binary(tool_name) and is_list(action_modules) do
    prefix = Keyword.get(opts, :prefix)

    case Enum.find(action_modules, fn mod -> apply_prefix(mod.name(), prefix) == tool_name end) do
      nil -> {:error, :not_found}
      module -> {:ok, module}
    end
  end

  @doc """
  Validates that all modules in the list implement the Jido.Action behaviour.

  Returns `:ok` if all modules are valid, or `{:error, {:invalid_action, module, reason}}`
  for the first invalid module found.

  ## Example

      :ok = ToolAdapter.validate_actions([Calculator, Search])
      {:error, {:invalid_action, BadModule, :missing_name}} = ToolAdapter.validate_actions([BadModule])
  """
  @spec validate_actions([module()]) :: :ok | {:error, {:invalid_action, module(), atom()}}
  def validate_actions(action_modules) when is_list(action_modules) do
    Enum.reduce_while(action_modules, :ok, fn module, :ok ->
      case validate_action_module(module) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, {:invalid_action, module, reason}}}
      end
    end)
  end

  defp validate_action_module(module) do
    cond do
      not function_exported?(module, :name, 0) -> {:error, :missing_name}
      not function_exported?(module, :description, 0) -> {:error, :missing_description}
      not function_exported?(module, :schema, 0) -> {:error, :missing_schema}
      true -> :ok
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
    case ActionSchema.to_json_schema(schema, strict: true) do
      empty when empty == %{} ->
        %{"type" => "object", "properties" => %{}, "required" => [], "additionalProperties" => false}

      json_schema ->
        json_schema
    end
  end

  # Infers whether an action should use strict mode for LLM tool calling.
  #
  # Checks for a `strict?/0` callback on the action module, defaulting to false.
  # This callback is not part of the Jido.Action behaviour; it is detected via
  # `function_exported?/3` to keep this adapter decoupled from the action library.
  defp infer_strict?(module) do
    if function_exported?(module, :strict?, 0), do: module.strict?(), else: false
  end

  defp noop_callback(_args), do: {:ok, %{}}

  defp apply_prefix(name, nil), do: name
  defp apply_prefix(name, prefix) when is_binary(prefix), do: prefix <> name
end
