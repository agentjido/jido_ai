defmodule Jido.AI.Actions.FinalizeTurn do
  @moduledoc "Finalizes one graph request and returns the Agent commit envelope."

  alias Jido.AI.{Conversation, PromptCache, Runtime, Thread.Projection}

  use Jido.Action,
    name: "jido_ai_finalize_turn",
    description: "Commit the completed conversation Session",
    schema: Zoi.map(),
    output_schema: Zoi.map()

  @impl Jido.Action
  def run(%{outcome: %{turn: turn, result: result}}, context) do
    completed_at = Runtime.now_ms(context)
    refs = %{request_id: turn.request_id, run_id: turn.run_id}
    prompt_cache = PromptCache.summary(turn.prompt_cache_config, turn.prompt_cache_observations)

    payload = %{
      status: result.status,
      started_at_ms: turn.started_at_ms,
      completed_at_ms: completed_at,
      model_calls: turn.model_calls,
      tool_rounds: turn.tool_rounds,
      tool_calls: turn.tool_call_count,
      tool_errors: turn.tool_error_count,
      retries: turn.retries,
      usage: turn.usage,
      prompt_cache: prompt_cache
    }

    session =
      turn.session
      |> Conversation.decode!()
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
        prompt_cache: prompt_cache,
        model_attempts: turn.model_attempts
      })

    {:ok, %{state: state, response: response}}
  end
end
