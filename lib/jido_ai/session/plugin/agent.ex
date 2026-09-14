defmodule Jido.AI.Session.Plugin.Agent do
  @moduledoc false
  use Jido.Agent.Plugin

  alias Jido.AI.Session.{Change, Plugin}

  @impl Jido.Agent.Plugin
  def state_spec(_opts), do: {:requests, Jido.AI.Session.Record.records_schema()}

  @impl Jido.Agent.Plugin
  def directives(_opts), do: [Change, Jido.AI.Session.DeliveryReceipt]

  @impl Jido.Agent.Plugin
  def prepare(preparation, _opts),
    do:
      {:ok,
       %{
         configuration: Map.get(preparation.agent_state, Jido.AI.Configuration.key(), %{})
       }}

  @impl Jido.Agent.Plugin
  def reduce(reduction, _opts),
    do: Plugin.reduce_records(reduction.plugin_state, reduction.directives)
end
