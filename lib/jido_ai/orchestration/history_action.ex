defmodule Jido.AI.Orchestration.HistoryAction do
  @moduledoc false
  use Jido.Action,
    name: "ai_session_history",
    schema: Zoi.object(%{request_id: Zoi.string(), batch_id: Zoi.string()})

  alias Jido.AI.Orchestration.Change

  def run(params, context) do
    with {:ok, context} <- Jido.AI.Orchestration.Plugin.context(context),
         do: execute(params, context)
  end

  defp execute(%{request_id: id, batch_id: batch_id}, context) do
    with %{status: :pending, run_id: run_id} = record <- context.agent_state.requests[id],
         %{run_id: ^run_id, entries: entries} = batch <- context[:jido_ai_history_batch] do
      profile = context.jido_ai_profiles[record.profile_id]
      candidate = Jido.AI.Orchestration.Transcript.append(context.agent_state, profile, entries)
      record = record |> Map.put(:inspection, batch.inspection) |> Map.put(:meta, batch.meta)
      record = Jido.AI.Orchestration.Inspection.fit(record, candidate, context)

      {:ok, candidate, [%Change{operation: :history, record: record, batch_id: batch_id}]}
    else
      _ -> {:error, :stale_history}
    end
  end
end
