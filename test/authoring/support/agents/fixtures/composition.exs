defmodule JidoAITest.Authoring.Agents.Fixtures.CounterFacet do
  use Jido.Agent.Plugin
  def state_spec(_), do: {:counter, Zoi.integer() |> Zoi.default(0)}
  def reduce(reduction, _), do: {:ok, reduction.plugin_state + 1}
end

defmodule JidoAITest.Authoring.Agents.Fixtures.CounterPlugin do
  use Jido.Plugin, agent: JidoAITest.Authoring.Agents.Fixtures.CounterFacet
end

defmodule JidoAITest.Authoring.Agents.Fixtures.MirrorFacet do
  use Jido.Agent.Plugin
  def state_spec(_), do: {:mirror, Zoi.integer() |> Zoi.default(0)}
  def reduce(reduction, _), do: {:ok, reduction.state.counter}
end

defmodule JidoAITest.Authoring.Agents.Fixtures.MirrorPlugin do
  use Jido.Plugin, agent: JidoAITest.Authoring.Agents.Fixtures.MirrorFacet
end

defmodule JidoAITest.Authoring.Agents.Fixtures.DenyTool do
  def check(_value, context) do
    if context[:observer], do: send(context.observer, :authoring_tool_denied)
    {:error, :authoring_denied}
  end
end

defmodule JidoAITest.Authoring.Agents.Fixtures.FailingTool do
  use Jido.Action, name: "failing_tool", schema: Zoi.object(%{})

  def run(_, context) do
    send(context.observer, :authoring_tool_failed)
    {:error, :deliberate_tool_failure}
  end
end
