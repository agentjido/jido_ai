defmodule Jido.AI.SimpleAgent do
  @moduledoc """
  A graph-first AI Agent that uses the default ReAct reasoning Flow.

  The Agent owns the Signal route and reply boundary. `Jido.AI.Strategy.ReAct`
  owns the complete AI control graph.
  """

  use Jido.AI.Agent,
    id: "jido.ai/agents/simple",
    vsn: 3,
    name: "jido_ai_simple_agent",
    description: "Answer one request with guardrails and multiple tools"

  ai do
    reasoning Jido.AI.Strategy.ReAct
  end
end
