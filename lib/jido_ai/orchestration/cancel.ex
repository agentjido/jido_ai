defmodule Jido.AI.Orchestration.Cancel do
  @moduledoc false
  use Jido.Action,
    name: "ai_request_cancel",
    schema:
      Zoi.object(%{
        request_id: Zoi.string() |> Zoi.nullable() |> Zoi.default(nil),
        reason: Zoi.any() |> Zoi.default(nil)
      })

  alias Jido.AI.Orchestration.Change

  def run(params, context) do
    with {:ok, context} <- Jido.AI.Orchestration.Plugin.context(context),
         do: execute(params, context)
  end

  defp execute(%{request_id: id, reason: reason}, context) do
    id =
      id ||
        Enum.find_value(context.agent_state.requests, fn {id, r} ->
          if r.status == :pending, do: id
        end)

    case context.agent_state.requests[id] do
      %{status: :pending} = record ->
        record = %{
          record
          | status: :failed,
            completion_reserve: nil,
            error: if(is_nil(reason), do: :cancelled, else: {:cancelled, reason}),
            meta:
              Jido.AI.Orchestration.failed_metadata(
                Map.get(context, :jido_ai_request_metadata, %{}),
                if(is_nil(reason), do: :cancelled, else: {:cancelled, reason})
              ),
            completed_at: System.system_time(:millisecond)
        }

        record =
          Jido.AI.Orchestration.Inspection.complete(
            record,
            context[:jido_ai_request_inspection],
            context.agent_state,
            context
          )

        with {:ok, candidate, changes} <-
               Jido.AI.Thread.Control.finish(context.agent_state, record, context),
             do: {:ok, candidate, [%Change{operation: :finish, record: record} | changes]}

      nil ->
        {:error, :request_not_found}

      _ ->
        {:error, :request_already_finished}
    end
  end
end
