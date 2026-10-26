defmodule Jido.AI.Actions.CheckOutput do
  @moduledoc """
  Applies final-answer guardrails to one model outcome.
  """

  use Jido.Action,
    name: "jido_ai_check_output",
    description: "Apply the Agent output guardrail",
    schema:
      Zoi.object(%{
        kind: Zoi.enum([:final_answer, :tool_calls]),
        text: Zoi.string()
      }),
    output_schema:
      Zoi.object(%{
        allowed: Zoi.boolean(),
        reason: Zoi.string()
      })

  @impl Jido.Action
  def run(%{kind: :tool_calls}, _context), do: {:ok, %{allowed: true, reason: ""}}

  def run(%{kind: :final_answer, text: text}, _context) do
    cond do
      String.trim(text) == "" -> {:ok, %{allowed: false, reason: "model output is empty"}}
      String.length(text) > 4_000 -> {:ok, %{allowed: false, reason: "model output is too long"}}
      true -> {:ok, %{allowed: true, reason: ""}}
    end
  end
end
