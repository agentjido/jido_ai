defmodule Jido.AI.Reasoning.Actions.GuardInput do
  @moduledoc "Checks one request before its reasoning graph starts."

  @blocked_fragments ["ignore previous instructions", "reveal your system prompt"]

  use Jido.Action,
    id: "jido.ai/reasoning/actions/guard-input",
    vsn: 1,
    name: "jido_ai_guard_input",
    description: "Check one request before model work starts",
    schema: Zoi.map(),
    output_schema: Zoi.map()

  @impl Jido.Action
  def run(%{turn: turn}, context) do
    cond do
      reason = rejection_reason(turn.input) ->
        {:ok, blocked(:input, reason)}

      Map.get(turn, :review_tools, false) and not Jido.Exec.supports?(context, :waits) ->
        {:ok, blocked(:review, "execution host does not support waits")}

      true ->
        {:ok, %{allowed: true, guardrail: :none, reason: ""}}
    end
  end

  defp rejection_reason(input) do
    normalized = String.downcase(input)

    cond do
      String.trim(input) == "" ->
        "input is empty"

      String.length(input) > 2_000 ->
        "input is longer than 2000 characters"

      Enum.any?(@blocked_fragments, &String.contains?(normalized, &1)) ->
        "input contains a blocked instruction pattern"

      true ->
        nil
    end
  end

  defp blocked(guardrail, reason),
    do: %{allowed: false, guardrail: guardrail, reason: reason}
end
