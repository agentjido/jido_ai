defmodule JidoAI.Examples.TRM.Check do
  @behaviour Jido.AI.Control
  def check(result, context) do
    send(context.observer, {:trm_checked, result})
    if context[:reject], do: {:error, context.reject}, else: :ok
  end
end

defmodule JidoAI.Examples.TRM.Agent do
  use Jido.Agent, name: "recursive_reasoning", extensions: [Jido.AI.DSL]

  agent do
    schema(Zoi.object(%{reply: Zoi.any() |> Zoi.default(nil)}))

    ai :assistant do
      models do
        model(:answer, JidoAI.Examples.MockLLM.model())
      end

      reasoning :trm do
        model(:answer)
      end

      controls do
        max_iterations(15)
        max_model_calls(15)
        output(JidoAI.Examples.TRM.Check)
      end

      requests do
        mode(:session)
        streaming(true)
      end

      result(nil, into: :reply)
    end
  end

  routes do
    route("ai.trm.query", ai(:assistant))
  end
end

defmodule JidoAI.Examples.TRM do
  alias JidoAI.Examples.TRM.Agent

  def source do
    {_, config} = Enum.find(Agent.agent().plugins, &(elem(&1, 0) == Jido.AI.Runtime.Plugin))
    Map.from_struct(config[:profiles].assistant)
  end

  def base do
    %{
      name: Agent.agent().name,
      module: Agent,
      schema: Agent.domain_schema(),
      routes: [{"ai.trm.query", Jido.AI.Authoring.ai(:assistant)}]
    }
  end

  def definition(changes \\ %{}),
    do: Jido.AI.Authoring.lower(base(), [Map.merge(source(), changes)])

  def options(value),
    do: %{
      reasoning: %{source().reasoning | options: Map.merge(source().reasoning.options, value)}
    }

  def cycle(answer, score, improved) do
    for text <- [
          answer,
          "SCORE: #{score}\nISSUE: Missing detail\nSUGGESTION: Add detail",
          improved
        ],
        do: %{reply: {:text, text}}
  end

  def script, do: cycle("First answer", 0.95, "Unreviewed improvement")
end
