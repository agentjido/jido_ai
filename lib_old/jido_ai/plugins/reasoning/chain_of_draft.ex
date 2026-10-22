defmodule Jido.AI.Plugins.Reasoning.ChainOfDraft do
  @moduledoc """
  Binds a fixed reasoning method for core Agent composition.

  Configure with `[profile: profile]`, using a resolved session Profile for this
  method. Declare the route with `RunCapability`. The Agent schema must contain
  `profile.result.into` and accept the callable result envelope. Core owns the
  Plugin state; the Profile stays in Plugin configuration.
  """
  use Jido.AI.ReasoningCapability,
    strategy: :cod,
    name: "reasoning_chain_of_draft",
    description: "Runs Chain-of-Draft reasoning as a plugin capability"
end
