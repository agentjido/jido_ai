defmodule Jido.AI.Reasoning.ReAct.Actions.RecordToolResults do
  @moduledoc "Appends ordered Parallel tool results to the Session."

  alias Jido.AI.{Thread.Projection, ToolResult}

  use Jido.Action,
    id: "jido.ai/reasoning/react/actions/record-tool-results",
    vsn: 1,
    name: "jido_ai_react_record_tool_results",
    description: "Record tool results and continue the Agent graph",
    schema: Zoi.map(),
    output_schema: Zoi.map()

  @impl Jido.Action
  def run(%{turn: turn, results: results}, _context) do
    refs = %{request_id: turn.request_id, run_id: turn.run_id}
    at = System.system_time(:millisecond)

    session_result =
      Enum.reduce_while(results, {:ok, Jido.Session.decode!(turn.session)}, fn result, {:ok, session} ->
        normalized = ToolResult.normalize(result.outcome, turn.max_tool_output_bytes)

        message = %{
          role: :tool,
          content: "",
          name: result.name,
          tool_call_id: result.id,
          output: normalized.model_content,
          metadata: Map.put(normalized.metadata, :status, normalized.status)
        }

        case Projection.append(session, message, refs, at) do
          {:ok, next} -> {:cont, {:ok, next}}
          error -> {:halt, error}
        end
      end)

    with {:ok, session} <- session_result do
      errors = Enum.count(results, &(tool_status(&1.outcome) == :error))

      next_turn = %{
        turn
        | session: Jido.Session.encode(session),
          model_attempt: 0,
          tool_rounds: turn.tool_rounds + 1,
          tool_call_count: turn.tool_call_count + length(results),
          tool_error_count: turn.tool_error_count + errors,
          model_outcome: nil,
          repair_instruction: nil
      }

      {:ok, %{turn: next_turn}}
    end
  end

  defp tool_status(%{status: status}) when status in [:ok, :error], do: status
  defp tool_status(_outcome), do: :error
end
