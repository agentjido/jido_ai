defmodule Jido.AI.Orchestration.ControlAction do
  @moduledoc false
  use Jido.Action,
    name: "ai_session_control",
    schema:
      Zoi.object(%{
        control_id: Zoi.string(),
        kind: Zoi.enum([:steer, :inject]),
        content: Zoi.string(),
        expected_request_id: Zoi.string() |> Zoi.nullable() |> Zoi.default(nil),
        source: Zoi.string() |> Zoi.default("/ai/react"),
        extra_refs: Zoi.map() |> Zoi.default(%{})
      })

  def run(input, context) do
    with {:ok, context} <- Jido.AI.Orchestration.Plugin.context(context),
         :ok <- Jido.Action.validate_static_data(input),
         %{status: :queued, request_id: id} = result <-
           GenServer.call(context.jido_ai_session_runtime, {:control, input}) do
      record = Map.put(context.agent_state.requests[id], :last_control, result)
      {:ok, context.agent_state, [%Jido.AI.Orchestration.Change{operation: :control, record: record}]}
    else
      %{status: :rejected} = result ->
        {:error, Jido.Action.Error.validation_error("AI control rejected", %{control: result})}

      {:error, _} = error ->
        error
    end
  end
end
