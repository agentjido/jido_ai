unless Code.ensure_loaded?(JidoAI.Examples.Tools.Add) do
  Code.require_file("../support/arithmetic_tools.ex", __DIR__)
end

defmodule JidoAI.Examples.SimpleAgent do
  @moduledoc "A minimal graph-first AI Agent example."

  use Jido.AI.Agent,
    name: "jido_ai_simple_agent",
    description: "Answer one request with guardrails and multiple tools",
    id: "jido.ai/agents/simple",
    vsn: 3

  ai do
    reasoning Jido.AI.Reasoning.ReAct

    tools do
      action JidoAI.Examples.Tools.Add
      action JidoAI.Examples.Tools.Multiply
    end
  end
end
