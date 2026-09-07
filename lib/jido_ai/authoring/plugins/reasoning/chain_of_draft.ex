defmodule Jido.AI.Plugins.Reasoning.ChainOfDraft do
  @moduledoc """
  Supplies defaults for isolated Chain-of-Draft requests on `reasoning.cod.run`.

  Declare this Plugin with keyword options `default_model`, `timeout`, `options`
  and `into` (default `:result`). Declare the route separately with
  `Jido.AI.Actions.Reasoning.RunCapability`, or use `signal_routes/1` in an Agent
  source map. The Agent schema must contain the result field.

  Core owns the `:reasoning_cod` state key. Caller strategy input cannot
  change this capability's method. Execution uses the common AI Profile and Flow.
  """
  use Jido.AI.ReasoningCapability,
    strategy: :cod,
    name: "reasoning_chain_of_draft",
    description: "Runs Chain-of-Draft reasoning as a plugin capability"
end
