defmodule JidoAI.Examples.GoT do
  alias JidoAI.Examples.GoT.Agent

  def source do
    Agent |> Jido.AI.Agent.profile(:assistant) |> Map.from_struct()
  end

  def base do
    %{
      name: Agent.definition().name,
      module: Agent,
      vsn: Agent.vsn(),
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
