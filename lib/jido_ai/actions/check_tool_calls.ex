defmodule Jido.AI.Actions.CheckToolCalls do
  @moduledoc """
  Applies allow-list, argument, group, and request limits to tool calls.
  """

  use Jido.Action,
    name: "jido_ai_check_tool_calls",
    description: "Apply the Agent tool guardrail",
    schema: Zoi.map(),
    output_schema: Zoi.map()

  @impl Jido.Action
  def run(params, _context) do
    case rejection_reason(params) do
      nil -> {:ok, continue(params)}
      {guardrail, reason} -> {:ok, complete(params, guardrail, reason)}
    end
  end

  defp rejection_reason(params) do
    calls = params.tool_calls
    names = Enum.map(calls, & &1.name)
    ids = Enum.map(calls, & &1.id)

    cond do
      calls == [] ->
        {:tool, "model requested a tool round without tool calls"}

      length(calls) > 4 ->
        {:tool, "one model response can contain at most 4 tool calls"}

      params.tool_call_count + length(calls) > params.max_tool_calls ->
        {:limits, "maximum tool calls reached"}

      Enum.any?(names, &(&1 not in params.allowed_tools)) ->
        {:tool, "model requested a tool that is not allowed"}

      length(ids) != length(Enum.uniq(ids)) ->
        {:tool, "tool call IDs must be unique"}

      true ->
        validation_error(calls)
    end
  end

  defp validation_error(calls) do
    Enum.find_value(calls, fn call ->
      case Jido.AI.ToolRegistry.validate_call(call) do
        :ok -> nil
        {:error, reason} -> {:tool, inspect(reason)}
      end
    end)
  end

  defp continue(params) do
    input =
      Map.take(params, [
        :allowed_tools,
        :history,
        :input,
        :iteration,
        :max_iterations,
        :max_tool_calls,
        :tool_call_count,
        :tool_calls
      ])

    %{
      kind: :continue,
      input: input
    }
  end

  defp complete(params, guardrail, reason) do
    %{
      kind: :complete,
      result: %{
        status: :blocked,
        output: "",
        iterations: params.iteration,
        tool_calls: params.tool_call_count,
        guardrail: guardrail,
        reason: reason
      }
    }
  end
end
