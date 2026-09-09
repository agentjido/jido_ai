defmodule JidoAI.Examples.PluginStack.Agent do
  use Jido.AI.Agent,
    name: "stack_agent",
    model: :example,
    tools: [],
    streaming: false
end

defmodule JidoAI.Examples.PluginStack do
  def definition(opts \\ []) do
    [name: "stack_example", tools: [], model: JidoAI.Examples.MockLLM.model(), streaming: false]
    |> Keyword.merge(opts)
    |> Jido.AI.Agent.Options.lower!()
    |> Jido.Agent.new!()
  end

  def signal(type, data), do: Jido.Signal.new!(type, data, source: "/examples/plugin_stack")
end

defmodule JidoAI.Examples.PluginStack.Hold do
  use Jido.Action, name: "stack_hold", schema: Zoi.object(%{})

  def run(_, context) do
    send(context.observer, {:stack_tool_waiting, self()})

    receive do
      :release -> {:ok, %{status: "ready"}}
    end
  end
end

defmodule JidoAI.Examples.PluginStack.BudgetAgent do
  use Jido.AI.Agent,
    name: "budget_agent",
    model: :example,
    tools: [JidoAI.Examples.PluginStack.Hold],
    streaming: false,
    retrieval: %{namespace: "weather"},
    quota: [scope: "team", max_requests: 2]
end

defmodule JidoAI.Examples.PluginStack.CoT do
  use Jido.AI.CoTAgent,
    name: "stack_cot",
    model: :example,
    streaming: false,
    quota: %{scope: "cot"}
end

defmodule JidoAI.Examples.PluginStack.PortableAgent do
  use Jido.AI.Agent,
    name: "portable_stack",
    model: :example,
    tools: [],
    streaming: false,
    retrieval: true,
    quota: true
end

defmodule JidoAI.Examples.PluginStack.Marker do
  use Jido.Plugin

  def state_spec(opts),
    do: {:marker, Zoi.string() |> Zoi.default(Keyword.get(opts, :value, "kept"))}
end

defmodule JidoAI.Examples.PluginStack.SetCase do
  use Jido.Action, name: "set_case", schema: Zoi.object(%{status: Zoi.string()})
  def run(params, context), do: {:ok, %{context.agent_state | capability_result: params}}
end

defmodule JidoAI.Examples.PluginStack.AttributeRoutes do
  @case_routes [{"case.review", {JidoAI.Examples.PluginStack.SetCase, %{status: "reviewed"}}}]
  use Jido.AI.Agent,
    name: "attribute_routes",
    model: :example,
    tools: [],
    streaming: false,
    quota: true,
    signal_routes: @case_routes
end
