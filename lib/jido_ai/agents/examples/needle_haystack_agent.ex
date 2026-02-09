defmodule Jido.AI.Examples.NeedleHaystackAgent do
  @moduledoc """
  Example RLM agent that finds information hidden in massive text contexts.

  Demonstrates the RLM (Recursive Language Model) pattern for systematic
  context exploration using chunking, searching, and sub-LLM delegation.

  ## Usage

      {:ok, pid} = Jido.AgentServer.start(agent: Jido.AI.Examples.NeedleHaystackAgent)

      {:ok, result} = Jido.AI.Examples.NeedleHaystackAgent.explore_sync(pid,
        "Find the magic number hidden in this text",
        context: massive_text_binary,
        timeout: 300_000
      )
  """

  use Jido.AI.RLMAgent,
    name: "needle_haystack",
    description: "Finds information hidden in massive text contexts using RLM exploration",
    model: "anthropic:claude-haiku-4-5",
    recursive_model: "anthropic:claude-haiku-4-5",
    max_iterations: 15,
    extra_tools: []
end
