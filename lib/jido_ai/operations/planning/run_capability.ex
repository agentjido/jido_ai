defmodule Jido.AI.Actions.Planning.RunCapability do
  @moduledoc "Runs a declared Planning capability and returns a complete Agent state."
  use Jido.Action, name: "planning_run_capability", schema: Zoi.map()

  def run(
        params,
        %{jido_ai_planning_capability: %{action: action} = binding, agent_state: _} = context
      ),
      do: Jido.AI.Capability.run(action, params, context, binding)

  def run(_, _), do: {:error, :planning_capability_not_bound}
end
