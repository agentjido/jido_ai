defmodule Jido.AI.Actions.RecordToolResults do
  @moduledoc """
  Adds ordered Parallel tool results to portable history and returns to the model.
  """

  use Jido.Action,
    name: "jido_ai_record_tool_results",
    description: "Record tool results and continue the Agent graph",
    schema: Zoi.map(),
    output_schema: Zoi.map()

  @impl Jido.Action
  def run(params, _context) do
    messages =
      Enum.map(params.results, fn result ->
        %{
          role: :tool,
          name: result.name,
          tool_call_id: result.id,
          output: result.output
        }
      end)

    next_input = %{
      allowed_tools: params.allowed_tools,
      history: params.history ++ messages,
      input: params.input,
      iteration: params.iteration,
      max_iterations: params.max_iterations,
      max_tool_calls: params.max_tool_calls,
      tool_call_count: params.tool_call_count + length(params.results)
    }

    {:ok,
     %{
       kind: :continue,
       input: next_input
     }}
  end
end
