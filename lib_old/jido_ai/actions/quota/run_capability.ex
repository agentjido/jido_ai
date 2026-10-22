defmodule Jido.AI.Actions.Quota.RunCapability do
  @moduledoc "Runs a declared Quota Action and returns the complete Agent state."
  use Jido.Action, name: "quota_run_capability", schema: Zoi.map()

  def run(params, %{agent_state: _} = context) do
    case Jido.AI.Capability.prepared(context, Jido.AI.Plugins.Quota) do
      %{capability: %{action: action} = binding} ->
        Jido.AI.Capability.run(action, params, context, binding)

      _ ->
        {:error, :quota_capability_not_bound}
    end
  end

  def run(_, _), do: {:error, :quota_capability_not_bound}
end
