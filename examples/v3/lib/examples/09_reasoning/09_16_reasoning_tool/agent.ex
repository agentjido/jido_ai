defmodule JidoAI.Examples.ReasoningTool.Agent do
  use Jido.Agent, name: "reasoning_tool", extensions: [Jido.AI.DSL]

  agent do
    schema Zoi.object(%{
             reply: Zoi.any() |> Zoi.default(nil),
             case_id: Zoi.string() |> Zoi.default("case-16")
           })

    ai :assistant do
      models do
        model(:answer, JidoAI.Examples.MockLLM.model())
      end

      reasoning :react do
        model(:answer)
      end

      tools do
        action Jido.AI.Actions.Reasoning.RunStrategy,
          as: :reason,
          forward_context: [:default_model, :model_options, :ai, :jido],
          timeout: 8_000
      end

      controls do
        timeout(10_000)
      end

      requests do
        mode(:session)
        streaming(false)
      end

      result(nil, into: :reply)
    end
  end

  routes do
    route "case.review", ai(:assistant)
  end
end

defmodule JidoAI.Examples.ReasoningTool.PublicAgent do
  use Jido.AI.Agent,
    name: "public_reasoning_tool",
    tools: [Jido.AI.Actions.Reasoning.RunStrategy],
    model: :fast,
    streaming: false,
    tool_timeout_ms: 8_000,
    max_iterations: 3
end

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
    {_, config} = Enum.find(Agent.agent().plugins, &(elem(&1, 0) == Jido.AI.Runtime.Plugin))
    Map.from_struct(config[:profiles].assistant)
  end

  def base do
    %{
      name: Agent.agent().name,
      module: Agent,
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
