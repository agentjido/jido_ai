defmodule Jido.AI.Actions.FinalizeTurn do
  @moduledoc "Finalizes one graph request and returns the Agent commit envelope."

  alias Jido.AI.{Runtime, Thread.Projection}

  use Jido.Action,
    name: "jido_ai_finalize_turn",
    description: "Commit the terminal request Session",
    schema: Zoi.object(%{outcome: Zoi.object(%{turn: Zoi.any(), result: Zoi.map()})}),
    output_schema: Zoi.object(%{state: Zoi.map(), response: Zoi.map()})

  @impl Jido.Action
  def run(%{outcome: %{turn: turn, result: result}}, context) do
    completed_at = Runtime.now_ms(context)
    refs = %{request_id: turn.request_id, run_id: turn.run_id}

    payload = %{
      status: result.status,
      started_at_ms: turn.started_at_ms,
      completed_at_ms: completed_at,
      model_calls: turn.model_calls,
      tool_rounds: turn.tool_rounds,
      tool_calls: turn.tool_call_count,
      tool_errors: turn.tool_error_count,
      retries: turn.retries,
      usage: turn.usage
    }

    session =
      turn.session
      |> Jido.Session.decode!()
      |> Projection.observe(:ai_request_outcome, payload, refs, completed_at)

    state = Map.put(turn.agent_state, :session, session)

    response =
      Map.merge(result, %{
        request_id: turn.request_id,
        run_id: turn.run_id,
        session_id: session.id,
        thread_id: session.thread.id,
        thread_rev: session.thread.rev,
        usage: turn.usage,
        model_attempts: turn.model_attempts
      })

    {:ok, %{state: state, response: response}}
  end
end
