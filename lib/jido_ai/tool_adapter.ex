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

      # Use in LLM call
      ReqLLM.stream_text(model, messages, tools: tools)
  """

  @doc """
  Converts a list of Jido.Action modules into ReqLLM.Tool structs.

  The returned tools use a noop callback—they're purely for describing available
  actions to the LLM. Actual execution happens via `Jido.AI.Directive.ToolExec`.

  ## Arguments

    * `action_modules` - List of modules implementing the `Jido.Action` behaviour

  ## Returns

    A list of `ReqLLM.Tool` structs

  ## Example

      iex> tools = Jido.AI.ToolAdapter.from_actions([MyApp.Actions.Add, MyApp.Actions.Search])
      [%ReqLLM.Tool{name: "add", ...}, ...]

  """
  @spec from_actions([module()]) :: [ReqLLM.Tool.t()]
  def from_actions(action_modules) when is_list(action_modules) do
    Enum.map(action_modules, &from_action/1)
  end

  @doc """
  Converts a single Jido.Action module into a ReqLLM.Tool struct.

  ## Arguments

    * `action_module` - A module implementing the `Jido.Action` behaviour

  ## Returns

    A `ReqLLM.Tool` struct
  """
  @spec from_action(module()) :: ReqLLM.Tool.t()
  def from_action(action_module) when is_atom(action_module) do
    ReqLLM.Tool.new!(
      name: action_module.name(),
      description: action_module.description(),
      parameter_schema: build_json_schema(action_module.schema()),
      callback: &noop_callback/1
    )
  end

  defp build_json_schema(schema) do
    Jido.Action.Schema.to_json_schema(schema)
  end

  defp noop_callback(_args) do
    {:error, :not_executed_via_callback}
  end
end
