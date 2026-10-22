defmodule JidoAI.Examples.ReasoningTool do
  alias JidoAI.Examples.ReasoningTool.Agent

  def source do
    Agent |> Jido.AI.Agent.profile(:assistant) |> Map.from_struct()
  end

  def base do
    %{
      name: Agent.definition().name,
      module: Agent,
      vsn: Agent.vsn(),
      schema: Agent.domain_schema(),
      routes: [{"case.review", Jido.AI.Authoring.ai(:assistant)}]
    }
  end
end
