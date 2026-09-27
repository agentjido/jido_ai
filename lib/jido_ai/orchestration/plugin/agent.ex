defmodule Jido.AI.Orchestration.Plugin.Agent do
  @moduledoc false
  @behaviour Jido.Plugin

  alias Jido.AI.Orchestration.{Change, Plugin}

  @impl Jido.Plugin
  def state_spec(_opts), do: {:requests, Jido.AI.Request.Record.records_schema()}

  @impl Jido.Plugin
  def directives(_opts), do: [Change, Jido.AI.Orchestration.DeliveryReceipt]

  @impl Jido.Plugin
  def prepare(preparation, _opts),
    do:
      {:ok,
       %{
         configuration: Map.get(preparation.agent_state, Jido.AI.Configuration.key(), %{})
       }}

  @impl Jido.Plugin
  def reduce(reduction, opts) do
    directives =
      Enum.map(reduction.directives, fn
        %Change{record: record} = change ->
          profile = (opts[:profiles] || %{})[record.profile_id]
          policy = if profile, do: profile.observability, else: %{}
          %{change | record: Jido.AI.Observe.Content.project(record, policy, :storage)}

        other ->
          other
      end)

    Plugin.reduce_records(reduction.plugin_state, directives)
  end
end
