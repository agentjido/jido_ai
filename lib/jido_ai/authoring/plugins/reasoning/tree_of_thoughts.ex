defmodule Jido.AI.Plugins.Reasoning.TreeOfThoughts do
  @moduledoc """
  Supplies defaults for isolated Tree-of-Thoughts requests on `reasoning.tot.run`.

  Declare this Plugin with keyword options `default_model`, `timeout`, `options`
  and `into` (default `:result`). Declare the route separately with
  `Jido.AI.Actions.Reasoning.RunCapability`, or use `signal_routes/1` in an Agent
  source map. The Agent schema must contain the result field.

  Core owns the `:reasoning_tot` state key. Caller strategy input cannot
  change this capability's method. Execution uses the common AI Profile and Flow.
  """
  use Jido.AI.ReasoningCapability,
    strategy: :tot,
    name: "reasoning_tree_of_thoughts",
    description: "Runs Tree-of-Thoughts reasoning as a plugin capability"
end
