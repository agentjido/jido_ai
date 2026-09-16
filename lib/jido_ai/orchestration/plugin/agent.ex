defmodule Jido.AI.Orchestration.Plugin.Agent do
  @moduledoc false
  use Jido.Agent.Plugin

  alias Jido.AI.Orchestration.{Change, Plugin}

  @impl Jido.Agent.Plugin
  def state_spec(_opts), do: {:requests, Jido.AI.Orchestration.Record.records_schema()}

  @impl Jido.Agent.Plugin
  def directives(_opts), do: [Change, Jido.AI.Orchestration.DeliveryReceipt]

  @impl Jido.Agent.Plugin
  def prepare(preparation, _opts),
    do:
      {:ok,
       %{
         configuration: Map.get(preparation.agent_state, Jido.AI.Configuration.key(), %{})
       }}

  @impl Jido.Agent.Plugin
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
