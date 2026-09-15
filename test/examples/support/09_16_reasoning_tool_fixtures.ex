defmodule JidoAI.Examples.ReasoningTool.Labels do
  use Jido.Action,
    name: "reasoning_labels",
    description: "Validate existing labels and open data",
    schema:
      Zoi.object(%{
        policy: Zoi.atom(description: "Existing policy label") |> Zoi.default(:reject),
        items: Zoi.list(Zoi.object(%{label: Zoi.atom(), note: Zoi.string()})),
        extras: Zoi.object(%{label: Zoi.atom()}, unrecognized_keys: :preserve)
      })

  def run(params, context) do
    send(context.observer, {:labels_received, params})
    {:ok, params}
  end
end

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

  def definition(changes \\ %{}),
    do: Jido.AI.Authoring.lower(base(), [Map.merge(source(), changes)])

  def call(args \\ %{}) do
    %{
      reply:
        {:tools,
         [
           %{
             id: "reason-1",
             name: "reason",
             arguments:
               Map.merge(
                 %{strategy: "cot", prompt: "Explain this answer", request_policy: "reject"},
                 args
               )
           }
         ]}
    }
  end
end
