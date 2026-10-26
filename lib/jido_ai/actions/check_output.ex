defmodule Jido.AI.Actions.CheckOutput do
  @moduledoc "Applies final-answer guards to one model outcome."

  use Jido.Action,
    name: "jido_ai_check_output",
    description: "Apply the Agent output guard",
    schema: Zoi.map(),
    output_schema: Zoi.map()

  @impl Jido.Action
  def run(%{outcome: %{status: :error}}, _context),
    do: {:ok, %{allowed: false, reason: "model request failed"}}

  def run(%{outcome: %{status: :budget, reason: reason}}, _context),
    do: {:ok, %{allowed: false, reason: reason}}

  def run(%{turn: turn, outcome: %{kind: :tool_calls} = outcome}, _context) do
    reason = finish_reason(outcome.finish_reason) || tool_call_reason(outcome.tool_calls, turn)
    {:ok, decision(reason)}
  end

  def run(%{outcome: %{kind: :final_answer, text: text} = outcome}, _context) do
    reason =
      finish_reason(outcome.finish_reason) ||
        cond do
          String.trim(text) == "" -> "model output is empty"
          String.length(text) > 4_000 -> "model output is too long"
          true -> nil
        end

    {:ok, decision(reason)}
  end

  defp tool_call_reason([], _turn), do: "model requested a tool round without tool calls"

  defp tool_call_reason(calls, turn) do
    ids = Enum.map(calls, & &1.id)

    cond do
      length(calls) > 4 ->
        "one model response can contain at most 4 tool calls"

      length(ids) != length(Enum.uniq(ids)) ->
        "tool call IDs must be unique"

      Enum.any?(calls, &(&1.name not in Jido.AI.Toolset.names(turn.tools))) ->
        "model requested a tool that is not allowed"

      true ->
        Enum.find_value(calls, fn call ->
          case Jido.AI.Toolset.validate_call(turn.tools, call) do
            :ok -> nil
            {:error, reason} -> "invalid tool call: #{inspect(reason)}"
          end
        end)
    end
  end

  defp finish_reason(reason) when reason in [nil, :stop, :tool_calls], do: nil
  defp finish_reason(:length), do: "model output stopped at its token limit"
  defp finish_reason(:content_filter), do: "model output was stopped by a content filter"
  defp finish_reason(:cancelled), do: "model output was cancelled"
  defp finish_reason(:incomplete), do: "model output was incomplete"
  defp finish_reason(:error), do: "model returned an error finish reason"
  defp finish_reason(_reason), do: "model returned an unknown finish reason"

  defp decision(nil), do: %{allowed: true, reason: ""}
  defp decision(reason), do: %{allowed: false, reason: reason}
end
