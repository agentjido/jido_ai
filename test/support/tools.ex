defmodule Jido.AITest.Tools.Add do
  use Jido.Action,
    id: "jido.ai/examples/tools/add",
    name: "add",
    description: "Add two numbers.",
    schema: Zoi.object(%{left: Zoi.number(), right: Zoi.number()}),
    output_schema: Zoi.object(%{value: Zoi.number()})

  @impl Jido.Action
  def run(%{left: left, right: right}, _context), do: {:ok, %{value: left + right}}
end

defmodule Jido.AITest.Tools.Multiply do
  use Jido.Action,
    id: "jido.ai/examples/tools/multiply",
    name: "multiply",
    description: "Multiply two numbers.",
    schema: Zoi.object(%{left: Zoi.number(), right: Zoi.number()}),
    output_schema: Zoi.object(%{value: Zoi.number()})

  @impl Jido.Action
  def run(%{left: left, right: right}, _context), do: {:ok, %{value: left * right}}
end

defmodule Jido.AITest.Tools.LargeOutput do
  use Jido.Action,
    id: "jido.ai/examples/tools/large-output",
    name: "large_output",
    description: "Return a large local value.",
    schema: Zoi.object(%{}),
    output_schema: Zoi.map()

  @impl Jido.Action
  def run(_params, _context), do: {:ok, %{content: String.duplicate("local-only-", 1_000)}}
end

defmodule Jido.AITest.SimpleAgent do
  use Jido.AI.Agent,
    id: "jido.ai/agents/simple",
    vsn: 3,
    name: "jido_ai_simple_agent",
    description: "Answer one request with guardrails and multiple tools"

  ai do
    reasoning Jido.AI.Reasoning.ReAct

    tools do
      action Jido.AITest.Tools.Add
      action Jido.AITest.Tools.Multiply
    end
  end
end

defmodule Jido.AITest.ConfiguredAgent do
  use Jido.AI.Agent,
    id: "jido.ai/agents/configured",
    vsn: 1,
    name: "jido_ai_configured_agent",
    description: "Use compile-time defaults for the canonical ReAct graph"

  ai do
    reasoning Jido.AI.Reasoning.ReAct do
      instructions "Answer as a careful support specialist."
      model "anthropic:claude-sonnet-4-5"
      fallback_models ["openai:gpt-5-mini"]

      limits do
        model_calls 6
        tool_rounds 3
        tool_calls 6
        retries 1
      end

      context do
        max_messages 32
        max_bytes 100_000
      end

      prompt_cache do
        enabled true
        ttl "5m"
      end
    end

    tools do
      action Jido.AITest.Tools.Add
      action Jido.AITest.Tools.Multiply
    end
  end
end

defmodule Jido.AITest.ChainOfThoughtAgent do
  use Jido.AI.Agent,
    id: "jido.ai/agents/chain-of-thought",
    vsn: 1,
    name: "jido_ai_chain_of_thought_agent",
    description: "Solve one request with a variable-length numbered reasoning chain"

  ai do
    reasoning Jido.AI.Reasoning.ChainOfThought
  end
end

defmodule Jido.AITest.LargeOutputAgent do
  use Jido.AI.Agent,
    id: "jido.ai/agents/large-output",
    vsn: 1,
    name: "jido_ai_large_output_agent",
    description: "Test bounded tool result projection"

  ai do
    reasoning Jido.AI.Reasoning.ReAct

    tools do
      action Jido.AITest.Tools.LargeOutput
    end
  end
end
