defmodule JidoAI.Examples.GoT.Check do
  @behaviour Jido.AI.Control
  def check(result, context) do
    send(context.observer, {:got_checked, result})
    if context[:reject], do: {:error, context.reject}, else: :ok
  end
end

defmodule JidoAI.Examples.GoT.Agent do
  use Jido.Agent, name: "graph_search", extensions: [Jido.AI.DSL]

  agent do
    schema Zoi.object(%{reply: Zoi.any() |> Zoi.default(nil)})

    ai :assistant do
      models do
        model(:answer, JidoAI.Examples.MockLLM.model())
      end

      reasoning :graph_of_thoughts do
        model(:answer)
      end

      controls do
        output(JidoAI.Examples.GoT.Check)
      end

      requests do
        mode(:session)
        streaming(true)
      end

      result(nil, into: :reply)
    end
  end

  routes do
    route "ai.got.query", ai(:assistant)
  end
end

defmodule JidoAI.Examples.GoT do
  alias JidoAI.Examples.GoT.Agent

  def source do
    {_, config} = Enum.find(Agent.agent().plugins, &(elem(&1, 0) == Jido.AI.Runtime.Plugin))
    Map.from_struct(config[:profiles].assistant)
  end

  def base do
    %{
      name: Agent.agent().name,
      module: Agent,
      schema: Agent.domain_schema(),
      routes: [{"ai.got.query", Jido.AI.Authoring.ai(:assistant)}]
    }
  end

  def definition(changes \\ %{}),
    do: Jido.AI.Authoring.lower(base(), [Map.merge(source(), changes)])

  def options(value),
    do: %{
      reasoning: %{source().reasoning | options: Map.merge(source().reasoning.options, value)}
    }

  def script do
    for text <- ["First analysis", "Refined analysis", "Combined conclusion"],
        do: %{reply: {:text, text}}
  end
end
