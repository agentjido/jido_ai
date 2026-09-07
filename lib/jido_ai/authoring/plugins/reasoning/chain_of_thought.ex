defmodule Jido.AI.Plugins.Reasoning.ChainOfThought do
  @moduledoc """
  Supplies defaults for isolated Chain-of-Thought requests on `reasoning.cot.run`.

  Declare this Plugin with keyword options `default_model`, `timeout`, `options`
  and `into` (default `:result`). Declare the route separately with
  `Jido.AI.Actions.Reasoning.RunCapability`, or use `signal_routes/1` in an Agent
  source map. The Agent schema must contain the result field.

  Core owns the `:reasoning_cot` state key. Caller strategy input cannot
  change this capability's method. Execution uses the common AI Profile and Flow.
  """
  use Jido.AI.ReasoningCapability,
    strategy: :cot,
    name: "reasoning_chain_of_thought",
    description: "Runs Chain-of-Thought reasoning as a plugin capability"
end
