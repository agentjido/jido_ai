defmodule Jido.AI.Actions.Retrieval.RunCapability do
  @moduledoc "Runs a declared retrieval Action and returns the complete Agent state."
  use Jido.Action, name: "retrieval_run_capability", schema: Zoi.map()

  def run(
        params,
        %{jido_ai_retrieval_capability: %{action: action} = binding, agent_state: _} = context
      ),
      do: Jido.AI.Capability.run(action, params, context, binding)

  def run(_, _), do: {:error, :retrieval_capability_not_bound}
end
