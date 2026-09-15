defmodule Jido.AI.Session.Publish do
  @moduledoc false
  use Jido.Action, name: "ai_session_publish", schema: Zoi.object(%{batch_id: Zoi.string()})

  def run(params, context) do
    with {:ok, context} <- Jido.AI.Session.Plugin.context(context),
         do: execute(params, context)
  end

  defp execute(%{batch_id: id}, context) do
    with %{id: ^id, owner: owner, ticket: ticket} <- context[:jido_ai_delivery_grant],
         {:ok, signals} <- Jido.AI.Session.Delivery.consume(owner, id, ticket) do
      directives = Enum.map(signals, &%Jido.Agent.Directive.Emit{signal: &1})
      {:ok, context.agent_state, directives ++ [%Jido.AI.Session.DeliveryReceipt{batch_id: id, ticket: ticket}]}
    else
      _ -> {:error, :invalid_delivery_grant}
    end
  end
end
