defmodule JidoAI.Examples.Adaptive do
  alias JidoAI.Examples.Adaptive.Agent

  def source do
    Agent |> Jido.AI.Agent.profile(:assistant) |> Map.from_struct()
  end

  def base do
    %{
      name: Agent.definition().name,
      module: Agent,
      vsn: Agent.vsn(),
      schema: Agent.domain_schema(),
      routes: [
        {"ai.adaptive.query", Jido.AI.Authoring.ai(:assistant)},
        {"case.close", JidoAI.Examples.Support.CloseCase}
      ]
    }
  end

  def definition(changes \\ %{}),
    do: Jido.AI.Authoring.lower(base(), [Map.merge(source(), changes)])

  def options(value),
    do: %{
      reasoning: %{source().reasoning | options: Map.merge(source().reasoning.options, value)}
    }

  def script(:cod), do: [%{reply: {:text, "Short thought\nAnswer: Four"}}]
  def script(:cot), do: [%{reply: {:text, "Step 1: Add\nConclusion: Four"}}]
  def script(:react), do: [%{reply: {:text, "Four"}}]
  def script(:aot), do: [%{reply: {:text, JidoAI.Examples.AoT.puzzle()}}]
  def script(:tot), do: JidoAI.Examples.ToT.script()
  def script(:got), do: JidoAI.Examples.GoT.script()
  def script(:trm), do: JidoAI.Examples.TRM.script()
end
