defmodule Jido.AI.Actions.Quota.RunCapability do
  @moduledoc "Runs a declared Quota Action and returns the complete Agent state."
  use Jido.Action, name: "quota_run_capability", schema: Zoi.map()

  def run(
        params,
        %{jido_ai_quota_capability: %{action: action} = binding, agent_state: _} = context
      ),
      do: Jido.AI.Capability.run(action, params, context, binding)

  def run(_, _), do: {:error, :quota_capability_not_bound}
end
