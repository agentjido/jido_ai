defmodule Jido.AI.ToolRunner do
  @moduledoc """
  Executes tool calls for a `Jido.AI.Turn`.

  This module owns side effects (tool execution) while `Jido.AI.Turn` remains a
  data contract. It provides a shared execution path for actions, directives,
  and strategies that need to execute LLM-requested tools.
  """

  alias Jido.AI.{Executor, ToolAdapter, Turn}

  @type run_opts :: [
          timeout: pos_integer() | nil,
          tools: map() | [module()] | module() | nil
        ]

  @doc """
  Executes all tool calls in a turn and returns an updated turn with tool results.
  """
  @spec run_turn(Turn.t(), map(), run_opts()) :: {:ok, Turn.t()} | {:error, term()}
  def run_turn(%Turn{} = turn, context, opts \\ []) do
    if Turn.needs_tools?(turn) do
      with {:ok, tool_results} <- run_tool_calls(turn.tool_calls, context, opts) do
        {:ok, Turn.with_tool_results(turn, tool_results)}
      end
    else
      {:ok, turn}
    end
  end

  @doc """
  Executes a list of tool calls and returns normalized tool results.
  """
  @spec run_tool_calls([term()], map(), run_opts()) :: {:ok, [map()]}
  def run_tool_calls(tool_calls, context, opts \\ []) when is_list(tool_calls) do
    tools = resolve_tools(context, opts)
    timeout = normalize_timeout(Keyword.get(opts, :timeout))

    tool_results =
      Enum.map(tool_calls, fn tool_call ->
        run_single_tool(tool_call, context, tools, timeout)
      end)

    {:ok, tool_results}
  end

  defp run_single_tool(tool_call, context, tools, timeout) do
    call_id = normalize_string(get_field(tool_call, :id, ""))
    tool_name = normalize_string(get_field(tool_call, :name, ""))
    arguments = normalize_arguments(get_field(tool_call, :arguments, %{}))

    exec_opts =
      [tools: tools]
      |> maybe_add_timeout(timeout)

    raw_result =
      case tool_name do
        "" ->
          {:error, %{type: :validation, message: "Missing tool name"}}

        _ ->
          Executor.execute(tool_name, arguments, context, exec_opts)
      end

    %{
      id: call_id,
      name: tool_name,
      content: Turn.format_tool_result_content(raw_result),
      raw_result: raw_result
    }
  end

  defp resolve_tools(context, opts) do
    context = if is_map(context), do: context, else: %{}

    tools_input =
      Keyword.get(opts, :tools) ||
        get_field(context, :tools) ||
        get_in(context, [:tool_calling, :tools]) ||
        get_in(context, [:state, :tool_calling, :tools]) ||
        get_in(context, [:agent, :state, :tool_calling, :tools]) ||
        get_in(context, [:plugin_state, :tool_calling, :tools])

    ToolAdapter.to_action_map(tools_input)
  end

  defp normalize_timeout(timeout) when is_integer(timeout) and timeout > 0, do: timeout
  defp normalize_timeout(_), do: nil

  defp maybe_add_timeout(opts, nil), do: opts
  defp maybe_add_timeout(opts, timeout), do: Keyword.put(opts, :timeout, timeout)

  defp normalize_arguments(%{} = arguments), do: arguments
  defp normalize_arguments(_), do: %{}

  defp normalize_string(value) when is_binary(value), do: value
  defp normalize_string(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_string(_), do: ""

  defp get_field(map, key, default \\ nil)

  defp get_field(map, key, default) when is_map(map) do
    Map.get(map, key, Map.get(map, Atom.to_string(key), default))
  end

  defp get_field(_, _key, default), do: default
end
