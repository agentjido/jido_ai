defmodule Jido.AI.Actions.Planning.RunCapability do
  @moduledoc "Runs a declared Planning capability and returns a complete Agent state."
  use Jido.Action, name: "planning_run_capability", schema: Zoi.map()

  def run(params, %{agent_state: _} = context) do
    case Jido.AI.Capability.prepared(context, Jido.AI.Plugins.Planning) do
      %{action: action} = binding -> Jido.AI.Capability.run(action, params, context, binding)
      _ -> {:error, :planning_capability_not_bound}
    end
  end

  def run(_, _), do: {:error, :planning_capability_not_bound}
end
