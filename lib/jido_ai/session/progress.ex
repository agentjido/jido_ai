defmodule Jido.AI.Session.Progress do
  @moduledoc false
  use Jido.Action,
    name: "ai_session_progress",
    schema:
      Zoi.object(%{
        request_id: Zoi.string(),
        run_id: Zoi.string(),
        ticket: Zoi.string()
      })

  alias Jido.AI.Session.Change

  def run(%{request_id: id, run_id: run_id}, context) do
    with %{status: :pending, run_id: ^run_id} = record <- context.agent_state.requests[id],
         %{request_id: ^id, run_id: ^run_id, adaptive: selection} <- context[:jido_ai_progress] do
      record = %{record | meta: Map.put(record.meta, :adaptive, selection)}
      candidate = Jido.AI.Agent.StateProjection.apply(context.agent_state, record, context)
      {:ok, candidate, [%Change{operation: :progress, record: record}]}
    else
      _ -> {:error, :invalid_progress}
    end
  end
end
