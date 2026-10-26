defmodule Jido.AI.Reasoning.ReAct.Actions.RequestToolReview do
  @moduledoc "Publishes one review request before the durable Flow wait."

  alias Jido.AI.Thread.Projection

  use Jido.Action,
    id: "jido.ai/reasoning/react/actions/request-tool-review",
    vsn: 1,
    name: "jido_ai_react_request_tool_review",
    description: "Request approval for one tool group",
    schema: Zoi.map(),
    output_schema: Zoi.map()

  @impl Jido.Action
  def run(%{turn: turn}, context) do
    at = System.system_time(:millisecond)
    session = Jido.Session.decode!(turn.session)

    data = %{
      session_id: session.id,
      thread_id: session.thread.id,
      request_id: turn.request_id,
      run_id: turn.run_id,
      timestamp_ms: at,
      tool_calls: turn.model_outcome.tool_calls
    }

    _result = dispatch_review_signal(context, data)

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

  defp dispatch_review_signal(context, data) do
    case Map.get(context, :jido_ai_dispatch) do
      nil ->
        :ok

      dispatch ->
        with {:ok, signal} <-
               Jido.Agent.build_signal(context, "jido.ai.review.requested", data) do
          Jido.Signal.Dispatch.dispatch(signal, dispatch)
        end
    end
  end
end
