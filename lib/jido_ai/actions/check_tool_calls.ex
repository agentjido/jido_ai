defmodule Jido.AI.Actions.CheckToolCalls do
  @moduledoc "Applies limits and policy before a group of tool calls runs."

  use Jido.Action,
    name: "jido_ai_check_tool_calls",
    description: "Apply the Agent tool guard",
    schema: Zoi.map(),
    output_schema: Zoi.map()

  @impl Jido.Action
  def run(%{turn: turn}, _context) do
    case rejection_reason(turn) do
      nil when turn.review_tools -> {:ok, %{kind: :review, input: %{turn: turn}}}
      nil -> {:ok, %{kind: :continue, input: %{turn: turn}}}
      {guardrail, reason} -> {:ok, complete(turn, guardrail, reason)}
    end
  end

  defp rejection_reason(turn) do
    calls = turn.model_outcome.tool_calls
    names = Enum.map(calls, & &1.name)
    ids = Enum.map(calls, & &1.id)

    cond do
      calls == [] ->
        {:tool, "model requested a tool round without tool calls"}

      length(calls) > 4 ->
        {:tool, "one model response can contain at most 4 tool calls"}

      turn.tool_call_count + length(calls) > turn.max_tool_calls ->
        {:limits, "maximum tool calls reached"}

      Enum.any?(names, &(&1 not in turn.allowed_tools)) ->
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

  defp complete(turn, guardrail, reason) do
    %{
      kind: :complete,
      output: %{
        turn: turn,
        result: %{
          status: :blocked,
          output: "",
          model_calls: turn.model_calls,
          tool_rounds: turn.tool_rounds,
          tool_calls: turn.tool_call_count,
          tool_errors: turn.tool_error_count,
          retries: turn.retries,
          guardrail: guardrail,
          reason: reason
        }
      }
    }
  end
end
