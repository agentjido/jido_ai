defmodule JidoAI.Examples.Adaptive.Check do
  @behaviour Jido.AI.Control
  def check(result, context) do
    send(context.observer, {:adaptive_checked, result})
    if context[:reject], do: {:error, context.reject}, else: :ok
  end
end

defmodule JidoAI.Examples.Adaptive.Agent do
  use Jido.Agent, name: "adaptive_reasoning", extensions: [Jido.AI.DSL]

  agent do
    schema Zoi.object(%{
             reply: Zoi.any() |> Zoi.default(nil),
             case_id: Zoi.string() |> Zoi.default("open")
           })

    ai :assistant do
      models do
        model(:answer, JidoAI.Examples.MockLLM.model())
      end

      reasoning :adaptive do
        model(:answer)
        options(method_options: %{tot: %{branching_factor: 2, max_depth: 1}})
      end

      tools do
        action JidoAI.Examples.ToT.Work, as: :tree_work, forward_context: [:observer]
      end

      controls do
        max_iterations(20)
        max_model_calls(20)
        output(JidoAI.Examples.Adaptive.Check)
      end

      requests do
        mode(:session)
        streaming(true)
      end

      result(nil, into: :reply)
    end
  end

  routes do
    route "ai.adaptive.query", ai(:assistant)
    route "case.close", JidoAI.Examples.AIRuntime.Close
  end
end

defmodule JidoAI.Examples.Adaptive do
  alias JidoAI.Examples.Adaptive.Agent

  def source do
    {_, config} = Enum.find(Agent.agent().plugins, &(elem(&1, 0) == Jido.AI.Runtime.Plugin))
    Map.from_struct(config[:profiles].assistant)
  end

  def base do
    %{
      name: Agent.agent().name,
      module: Agent,
      schema: Agent.domain_schema(),
      routes: [
        {"ai.adaptive.query", Jido.AI.Authoring.ai(:assistant)},
        {"case.close", JidoAI.Examples.AIRuntime.Close}
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
