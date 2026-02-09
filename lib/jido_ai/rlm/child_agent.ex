defmodule Jido.AI.RLM.ChildAgent do
  @moduledoc """
  Lightweight child RLM agent for recursive sub-exploration.

  Used by parent RLM agents to delegate sub-queries into smaller context
  chunks. Configured with a cheap model and fewer iterations to keep
  recursive exploration fast and cost-effective.
  """

  use Jido.AI.RLMAgent,
    name: "rlm_child",
    description: "Child RLM agent for recursive sub-exploration",
    model: "anthropic:claude-haiku-4-5",
    recursive_model: "anthropic:claude-haiku-4-5",
    max_iterations: 8,
    extra_tools: []
end
