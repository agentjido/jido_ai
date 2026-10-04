defmodule Jido.AI.Orchestration.Plugin.Agent do
  @moduledoc false
  alias Jido.AI.Orchestration.{Change, Plugin}

  def state_spec(_opts), do: {:requests, Jido.AI.Request.Record.records_schema()}

  def directives(_opts), do: [Change, Jido.AI.Orchestration.DeliveryReceipt]

  def prepare(preparation, _opts),
    do:
      {:ok,
       %{
         configuration: Map.get(preparation.agent_state, Jido.AI.Configuration.key(), %{})
       }}

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
