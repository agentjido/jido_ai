defmodule Jido.AI.Orchestration.Publish do
  @moduledoc false
  use Jido.Action, name: "ai_request_publish", schema: Zoi.object(%{batch_id: Zoi.string()})

  def run(params, context) do
    with {:ok, context} <- Jido.AI.Orchestration.Plugin.context(context),
         do: execute(params, context)
  end

  defp execute(%{batch_id: id}, context) do
    with %{id: ^id, owner: owner, ticket: ticket} <- context[:jido_ai_delivery_grant],
         {:ok, signals} <- Jido.AI.Orchestration.Delivery.consume(owner, id, ticket) do
      directives = Enum.map(signals, &%Jido.Agent.Directive.Emit{signal: &1})
      {:ok, context.agent_state, directives ++ [%Jido.AI.Orchestration.DeliveryReceipt{batch_id: id, ticket: ticket}]}
    else
      _ -> {:error, :invalid_delivery_grant}
    end
  end
end
