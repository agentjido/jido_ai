defmodule Jido.AI.Examples.OrpheusAgent do
  @moduledoc """
  RLM agent configured for the 10M-token Orpheus Dossier investigation demo.

  Uses Claude Sonnet as orchestrator with Haiku for sub-queries.
  Configured with max_depth: 1 to enable child agent spawning.
  """

  use Jido.AI.RLMAgent,
    name: "orpheus_investigator",
    description: "Investigates the Project ORPHEUS sabotage dossier using multi-layer recursive exploration",
    model: "anthropic:claude-sonnet-4-20250514",
    recursive_model: "anthropic:claude-haiku-4-5",
    max_iterations: 30,
    max_depth: 1,
    extra_tools: []
end
