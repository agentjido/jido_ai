defmodule JidoAI.Examples.StandaloneAuthoring.Add do
  use Jido.Action,
    name: "add",
    description: "Add two case values",
    schema: Zoi.object(%{a: Zoi.integer(), b: Zoi.integer()})

  def run(%{a: a, b: b}, context) do
    if context[:observer], do: send(context.observer, {:standalone_add, self(), a, b})
    {:ok, %{sum: a + b}}
  end
end

defmodule JidoAI.Examples.StandaloneAuthoring.Change do
  use Jido.Action,
    name: "change",
    description: "Change a case count",
    schema: Zoi.object(%{count: Zoi.integer()})

  def run(%{count: count}, context) do
    {:ok, %{count: count}, [Jido.AI.Effects.state(%{context.agent_state | count: count})]}
  end
end

defmodule JidoAI.Examples.StandaloneAuthoring.Transform do
  def transform_request(request, _state, _config, context) do
    send(context.observer, {:standalone_count, context.state.count})
    {:ok, %{tools: request.tools}}
  end
end

defmodule JidoAI.Examples.StandaloneAuthoring.Repair do
  def fix(_output, _raw, _reason, context) do
    send(context.observer, :standalone_repair)
    {:ok, %{answer: "Repaired"}}
  end
end

defmodule JidoAI.Examples.StandaloneAuthoring.Agent do
  @moduledoc "A standalone Config lowers to a normal Agent definition."

  def build(config, limits \\ %{timeout: 5_000, max_tool_calls: 32}) do
    Jido.AI.Reasoning.ReAct.Authoring.lower(config, limits, %{
      name: "standalone_config_example",
      schema:
        Zoi.object(%{
          result: Zoi.any() |> Zoi.default(nil),
          count: Zoi.integer() |> Zoi.default(0),
          messages: Zoi.list(Zoi.map()) |> Zoi.default([])
        })
    })
  end
end
