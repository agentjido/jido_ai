defmodule JidoAI.Bench.ReAct.Echo do
  @moduledoc false

  use Jido.Action,
    id: "jido.ai/bench/tools/echo",
    vsn: 1,
    name: "echo",
    description: "Return one small portable result",
    schema: Zoi.object(%{}),
    output_schema: Zoi.object(%{text: Zoi.string()})

  @impl Jido.Action
  def run(_params, context) do
    if counter = Map.get(context, :bench_tool_counter) do
      :atomics.add_get(counter, 1, 1)
    end

    {:ok, %{text: "ok"}}
  end
end

defmodule JidoAI.Bench.ReAct.Agent do
  @moduledoc false

  use Jido.AI.Agent,
    name: "jido_ai_react_state_growth_bench",
    description: "Measure ReAct fact growth over many small tool rounds",
    id: "jido.ai/bench/agents/react-state-growth",
    vsn: 1

  ai do
    reasoning(JidoAI.Bench.ReAct.ExtendedReAct)

    tools do
      action(JidoAI.Bench.ReAct.Echo)
    end
  end
end
