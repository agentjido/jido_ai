defmodule JidoAI.Examples.ToolFlow.Multiply do
  @moduledoc "Multiplies two integers."

  use Jido.Action,
    name: "multiply",
    description: "Multiply two integers",
    schema: Zoi.object(%{left: Zoi.integer(), right: Zoi.integer()})

  @impl Jido.Action
  def run(%{left: left, right: right}, context) do
    if counter = Map.get(context, :counter), do: Agent.update(counter, &(&1 + 1))
    {:ok, %{product: left * right}}
  end
end

defmodule JidoAI.Examples.ToolFlow.MultiplyFlow do
  @moduledoc "Runs the multiply Action through a Flow."

  use Jido.Flow,
    name: "multiply_flow",
    description: "Multiply two integers through a Flow",
    schema: Zoi.object(%{left: Zoi.integer(), right: Zoi.integer()})

  flow do
    step "multiply", action: JidoAI.Examples.ToolFlow.Multiply, params: input()
    output result("multiply")
  end
end

defmodule JidoAI.Examples.ToolFlow.Agent do
  @moduledoc "A response that can run a Jido Action or Flow as a tool."

  use Jido.AI.Agent, name: "tool_flow_example"

  ai do
    model :fast
    instructions "Use a calculation tool when it is useful."

    tools do
      action JidoAI.Examples.ToolFlow.Multiply, as: :multiply
      flow JidoAI.Examples.ToolFlow.MultiplyFlow, as: :multiply_flow
    end

    controls do
      timeout 5_000
      max_iterations 2
      max_model_calls 3
      max_tool_calls 4
    end
  end
end
