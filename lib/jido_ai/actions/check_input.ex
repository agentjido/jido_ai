defmodule Jido.AI.Actions.CheckInput do
  @moduledoc """
  Applies the input guardrail before any model work starts.
  """

  @blocked_fragments ["ignore previous instructions", "reveal your system prompt"]

  use Jido.Action,
    name: "jido_ai_check_input",
    description: "Apply the Agent input guardrail",
    schema:
      Zoi.object(%{
        input: Zoi.string(),
        max_iterations: Zoi.integer(gte: 1, lte: 8),
        max_tool_calls: Zoi.integer(gte: 1, lte: 16)
      }),
    output_schema: Zoi.map()

  @impl Jido.Action
  def run(params, _context) do
    case rejection_reason(params.input) do
      nil -> {:ok, continue(params)}
      reason -> {:ok, complete(reason)}
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

  defp continue(params) do
    %{
      kind: :continue,
      input: %{
        input: params.input,
        history: [],
        iteration: 0,
        max_iterations: params.max_iterations,
        tool_call_count: 0,
        max_tool_calls: params.max_tool_calls,
        allowed_tools: Jido.AI.ToolRegistry.names()
      }
    }
  end

  defp complete(reason) do
    %{
      kind: :complete,
      result: blocked_result(:input, reason, 0, 0)
    }
  end

  defp blocked_result(guardrail, reason, iterations, tool_calls) do
    %{
      status: :blocked,
      output: "",
      iterations: iterations,
      tool_calls: tool_calls,
      guardrail: guardrail,
      reason: reason
    }
  end
end
