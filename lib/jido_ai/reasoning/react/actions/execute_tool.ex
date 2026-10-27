defmodule Jido.AI.Reasoning.ReAct.Actions.ExecuteTool do
  @moduledoc "Executes one resolved tool and returns a timed observation envelope."

  alias Jido.AI.{Toolset, ToolSource}

  use Jido.Action,
    id: "jido.ai/reasoning/react/actions/execute-tool",
    vsn: 1,
    name: "jido_ai_react_execute_tool",
    description: "Execute one static or dynamic tool through the Agent graph",
    schema: Zoi.object(%{call: Zoi.map(), tools: Zoi.list(Zoi.any())}),
    output_schema: Zoi.map()

  @impl Jido.Action
  def run(%{call: call, tools: tools}, context) do
    started_at_ms = System.system_time(:millisecond)
    started_at = System.monotonic_time(:millisecond)

    {resolved, outcome, effects} = resolve_and_execute(tools, call, context)
    completed_at_ms = System.system_time(:millisecond)

    observation = %{
      version: 1,
      call: resolved_call(resolved, call),
      tool: resolved_tool(resolved, call),
      outcome: outcome,
      started_at_ms: started_at_ms,
      completed_at_ms: completed_at_ms,
      duration_ms: max(System.monotonic_time(:millisecond) - started_at, 0),
      effects_count: length(effects)
    }

    if effects == [], do: {:ok, observation}, else: {:ok, observation, effects}
  end

  defp resolve_and_execute(tools, call, context) do
    case Toolset.resolve_call(tools, call) do
      {:ok, resolved} ->
        {outcome, effects} = execute(resolved, context)
        {resolved, outcome, effects}

      {:error, reason} ->
        {nil, %{status: :error, error: portable_error(reason)}, []}
    end
  end

  defp execute(%{executor: {:action, action}, params: params}, context) do
    action
    |> Jido.Exec.run(params, context)
    |> normalize_result()
  end

  defp execute(%{executor: {:source, source}, id: id, name: name, params: params}, context) do
    source
    |> ToolSource.run(%{id: id, name: name, arguments: params}, context)
    |> normalize_result()
  end

  defp resolved_call(%{} = resolved, _call),
    do: Map.take(resolved, [:id, :name, :arguments])

  defp resolved_call(_resolved, call), do: Map.take(call, [:id, :name, :arguments])

  defp resolved_tool(%{tool: tool}, _call), do: tool
  defp resolved_tool(_resolved, call), do: %{kind: :unknown, name: Map.get(call, :name)}

  defp normalize_result({:ok, value}), do: {%{status: :ok, value: value}, []}

  defp normalize_result({:ok, value, effects}) when is_list(effects) do
    if List.improper?(effects),
      do: {%{status: :error, error: portable_error(:invalid_tool_effects)}, []},
      else: {%{status: :ok, value: value}, effects}
  end

  defp normalize_result({:error, error}),
    do: {%{status: :error, error: portable_error(error)}, []}

  defp normalize_result(other),
    do: {%{status: :error, error: portable_error({:invalid_tool_result, other})}, []}

  defp portable_error(error) do
    error
    |> Jido.Action.Error.to_map()
    |> Map.take([:type, :message, :retryable?])
  end
end
