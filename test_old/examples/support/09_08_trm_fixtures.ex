defmodule JidoAI.Examples.TRM do
  alias JidoAI.Examples.TRM.Agent

  def source do
    Agent |> Jido.AI.Agent.profile(:assistant) |> Map.from_struct()
  end

  def base do
    %{
      name: Agent.definition().name,
      module: Agent,
      vsn: Agent.vsn(),
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
