defmodule Jido.AI.Actions.RequestToolReview do
  @moduledoc "Publishes one review request before the durable Flow wait."

  alias Jido.AI.{Runtime, Thread.Projection}

  use Jido.Action,
    name: "jido_ai_request_tool_review",
    description: "Request approval for one tool group",
    schema: Zoi.map(),
    output_schema: Zoi.map()

  @impl Jido.Action
  def run(%{turn: turn}, context) do
    at = Runtime.now_ms(context)
    session = Jido.Session.decode!(turn.session)

    data = %{
      session_id: session.id,
      thread_id: session.thread.id,
      request_id: turn.request_id,
      run_id: turn.run_id,
      timestamp_ms: at,
      tool_calls: turn.model_outcome.tool_calls
    }

    _result = Runtime.publish(context, "jido.ai.review.requested", data)

    next_session =
      Projection.observe(
        session,
        :ai_review,
        %{status: :requested, tool_calls: turn.model_outcome.tool_calls},
        %{request_id: turn.request_id, run_id: turn.run_id},
        at
      )

    {:ok, %{turn: %{turn | session: Jido.Session.encode(next_session)}}}
  end
end
