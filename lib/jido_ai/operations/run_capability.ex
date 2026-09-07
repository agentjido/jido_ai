defmodule Jido.AI.Actions.Reasoning.RunCapability do
  @moduledoc """
  Runs a declared reasoning capability and returns a complete Agent state.

  Declare a reasoning Plugin and an explicit Signal route to this Action.
  The Plugin supplies the fixed method, owned defaults and result field.
  For a direct Action result, use `Jido.AI.Actions.Reasoning.RunStrategy`.
  """
  use Jido.Action, name: "reasoning_run_capability", schema: Zoi.map()

  def run(
        params,
        %{jido_ai_reasoning_capability: %{strategy: strategy} = binding, agent_state: _} = context
      ) do
    Jido.AI.Capability.run(
      Jido.AI.Actions.Reasoning.RunStrategy,
      Map.put(params, :strategy, strategy),
      context,
      binding
    )
  end

  def run(_, _), do: {:error, :reasoning_capability_not_bound}
end
