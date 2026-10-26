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

defmodule Jido.AITest.SimpleAgent do
  use Jido.AI.Agent,
    id: "jido.ai/agents/simple",
    vsn: 3,
    name: "jido_ai_simple_agent",
    description: "Answer one request with guardrails and multiple tools"

  ai do
    reasoning Jido.AI.Strategy.ReAct

    tools do
      action Jido.AITest.Tools.Add
      action Jido.AITest.Tools.Multiply
    end
  end
end
