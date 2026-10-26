defmodule Jido.AI.Actions.CheckInput do
  @moduledoc "Applies the input guard before model work starts."

  @blocked_fragments ["ignore previous instructions", "reveal your system prompt"]

  use Jido.Action,
    name: "jido_ai_check_input",
    description: "Apply the Agent input guard",
    schema: Zoi.map(),
    output_schema: Zoi.map()

  @impl Jido.Action
  def run(%{turn: turn}, context) do
    cond do
      reason = rejection_reason(turn.input) ->
        {:ok, complete(turn, :input, reason)}

      Map.get(turn, :review_tools, false) and not Jido.Exec.supports?(context, :waits) ->
        {:ok, complete(turn, :review, "execution host does not support waits")}

      true ->
        {:ok, %{kind: :model, input: %{turn: turn}}}
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

  defp complete(turn, guardrail, reason) do
    %{
      kind: :complete,
      output: %{
        turn: turn,
        result: %{
          status: :blocked,
          output: "",
          model_calls: 0,
          tool_rounds: 0,
          tool_calls: 0,
          tool_errors: 0,
          retries: 0,
          guardrail: guardrail,
          reason: reason
        }
      }
    }
  end
end
