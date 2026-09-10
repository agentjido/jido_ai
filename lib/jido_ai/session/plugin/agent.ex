defmodule Jido.AI.Session.Plugin.Agent do
  @moduledoc false
  use Jido.Agent.Plugin

  alias Jido.AI.Session.{Change, Plugin}

  @impl Jido.Agent.Plugin
  def state_spec(_opts), do: {:requests, Jido.AI.Session.Record.records_schema()}

  @impl Jido.Agent.Plugin
  def directives(_opts), do: [Change, Jido.AI.Session.DeliveryReceipt]

  @impl Jido.Agent.Plugin
  def validate_directive(%Change{} = change, _opts) do
    with {:ok, change} <- Zoi.parse(Change.schema(), change),
         :ok <- Jido.Action.validate_static_data(change),
         do: {:ok, change}
  end

  def validate_directive(%Jido.AI.Session.DeliveryReceipt{} = receipt, _opts),
    do: Zoi.parse(Jido.AI.Session.DeliveryReceipt.schema(), receipt)

  @impl Jido.Agent.Plugin
  def update_state(records, directives, _opts), do: Plugin.reduce_records(records, directives)
end
