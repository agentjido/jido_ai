defmodule Jido.AI.Plugins.Reasoning.GraphOfThoughts do
  @moduledoc """
  Binds a fixed reasoning method for core Agent composition.

  Configure with `[profile: profile]`, using a resolved session Profile for this
  method. Declare the route with `RunCapability`. The Agent schema must contain
  `profile.result.into` and accept the callable result envelope. Core owns the
  Plugin state; the Profile stays in Plugin configuration.
  """
  use Jido.AI.ReasoningCapability,
    strategy: :got,
    name: "reasoning_graph_of_thoughts",
    description: "Runs Graph-of-Thoughts reasoning as a plugin capability"
end
