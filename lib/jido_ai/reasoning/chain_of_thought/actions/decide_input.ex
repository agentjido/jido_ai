defmodule Jido.AI.Reasoning.ChainOfThought.Actions.DecideInput do
  @moduledoc "Starts the model graph or returns a blocked terminal outcome."

  use Jido.Action,
    id: "jido.ai/reasoning/chain-of-thought/actions/decide-input",
    vsn: 1,
    name: "jido_ai_chain_of_thought_decide_input",
    schema: Zoi.map(),
    output_schema: Zoi.map()

  @impl Jido.Action
  def run(%{turn: turn, guard: %{allowed: true}}, _context),
    do: {:ok, %{kind: :model, input: %{turn: turn}}}

  def run(
        %{turn: turn, guard: %{allowed: false, guardrail: guardrail, reason: reason}},
        _context
      ) do
    result = terminal(turn, :blocked, guardrail, reason)
    {:ok, %{kind: :complete, output: %{turn: turn, result: result}}}
  end

  defp terminal(turn, status, guardrail, reason) do
    %{
      status: status,
      output: "",
      model_calls: turn.model_calls,
      tool_rounds: 0,
      tool_calls: 0,
      tool_errors: 0,
      retries: turn.retries,
      guardrail: guardrail,
      reason: reason,
      reasoning: %{
        method: :chain_of_thought,
        steps: [],
        steps_count: 0,
        conclusion: nil,
        raw_response: ""
      }
    }
  end
end
