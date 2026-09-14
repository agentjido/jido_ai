defmodule Jido.AI.Actions.Retrieval.RunCapability do
  @moduledoc "Runs a declared retrieval Action and returns the complete Agent state."
  use Jido.Action, name: "retrieval_run_capability", schema: Zoi.map()

  def run(params, %{agent_state: _} = context) do
    case Jido.AI.Capability.prepared(context, Jido.AI.Plugins.Retrieval) do
      %{capability: %{action: action} = binding} ->
        Jido.AI.Capability.run(action, params, context, binding)

      _ ->
        {:error, :retrieval_capability_not_bound}
    end
  end

  def run(_, _), do: {:error, :retrieval_capability_not_bound}
end
