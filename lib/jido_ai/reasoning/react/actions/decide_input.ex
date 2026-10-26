defmodule Jido.AI.Reasoning.ReAct.Actions.DecideInput do
  @moduledoc "Routes an accepted request into the ReAct loop or returns a blocked outcome."

  use Jido.Action,
    id: "jido.ai/reasoning/react/actions/decide-input",
    vsn: 1,
    name: "jido_ai_react_decide_input",
    description: "Route a guarded request into the ReAct loop",
    schema: Zoi.map(),
    output_schema: Zoi.map()

  @impl Jido.Action
  def run(%{turn: turn, guard: %{allowed: true}}, _context),
    do: {:ok, %{kind: :model, input: %{turn: turn}}}

  def run(
        %{turn: turn, guard: %{allowed: false, guardrail: guardrail, reason: reason}},
        _context
      ) do
    result = %{
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

    {:ok, %{kind: :complete, output: %{turn: turn, result: result}}}
  end
end
