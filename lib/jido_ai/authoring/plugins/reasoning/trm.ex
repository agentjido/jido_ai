defmodule Jido.AI.Plugins.Reasoning.TRM do
  @moduledoc """
  Supplies defaults for isolated TRM requests on `reasoning.trm.run`.

  Declare this Plugin with keyword options `default_model`, `timeout`, `options`
  and `into` (default `:result`). Declare the route separately with
  `Jido.AI.Actions.Reasoning.RunCapability`, or use `signal_routes/1` in an Agent
  source map. The Agent schema must contain the result field.

  Core owns the `:reasoning_trm` state key. Caller strategy input cannot
  change this capability's method. Execution uses the common AI Profile and Flow.
  """
  use Jido.AI.ReasoningCapability,
    strategy: :trm,
    name: "reasoning_trm",
    description: "Runs TRM reasoning as a plugin capability"
end
