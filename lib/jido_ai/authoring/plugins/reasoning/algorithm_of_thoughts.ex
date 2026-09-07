defmodule Jido.AI.Plugins.Reasoning.AlgorithmOfThoughts do
  @moduledoc """
  Supplies defaults for isolated Algorithm-of-Thoughts requests on `reasoning.aot.run`.

  Declare this Plugin with keyword options `default_model`, `timeout`, `options`
  and `into` (default `:result`). Declare the route separately with
  `Jido.AI.Actions.Reasoning.RunCapability`, or use `signal_routes/1` in an Agent
  source map. The Agent schema must contain the result field.

  Core owns the `:reasoning_aot` state key. Caller strategy input cannot
  change this capability's method. Execution uses the common AI Profile and Flow.
  """
  use Jido.AI.ReasoningCapability,
    strategy: :aot,
    name: "reasoning_algorithm_of_thoughts",
    description: "Runs Algorithm-of-Thoughts reasoning as a plugin capability"
end
