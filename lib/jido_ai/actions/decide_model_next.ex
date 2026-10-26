defmodule Jido.AI.Actions.DecideModelNext do
  @moduledoc """
  Routes a guarded model outcome to completion or a tool round.
  """

  use Jido.Action,
    name: "jido_ai_decide_model_next",
    description: "Choose the next graph after a model call",
    schema: Zoi.map(),
    output_schema: Zoi.map()

  @impl Jido.Action
  def run(%{output_allowed: false} = params, _context) do
    {:ok, complete(blocked(params, :output, params.output_reason))}
  end

  def run(%{kind: :tool_calls, iteration: iteration, max_iterations: maximum} = params, _context)
      when iteration >= maximum do
    {:ok, complete(blocked(params, :limits, "maximum model iterations reached"))}
  end

  def run(%{kind: :tool_calls} = params, _context) do
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

    {:ok,
     %{
       kind: :continue,
       input: input
     }}
  end

  def run(%{kind: :final_answer} = params, _context) do
    result = %{
      status: :completed,
      output: params.text,
      iterations: params.iteration,
      tool_calls: params.tool_call_count,
      guardrail: :none,
      reason: ""
    }

    {:ok, complete(result)}
  end

  defp blocked(params, guardrail, reason) do
    %{
      status: :blocked,
      output: "",
      iterations: params.iteration,
      tool_calls: params.tool_call_count,
      guardrail: guardrail,
      reason: reason
    }
  end

  defp complete(result) do
    %{kind: :complete, result: result}
  end
end
