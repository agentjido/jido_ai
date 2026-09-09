defmodule JidoAI.Examples.ReasoningCapabilities do
  @moduledoc "One domain Agent with explicit reasoning capability routes."

  def definition(plugins, opts \\ []) do
    Jido.Agent.new(%{
      name: "reasoning_capabilities",
      schema:
        Zoi.object(%{
          result: Zoi.any() |> Zoi.default(nil),
          review: Zoi.any() |> Zoi.default(nil),
          case_id: Zoi.string() |> Zoi.default("case-17")
        }),
      plugins: plugins,
      routes:
        Keyword.get_lazy(opts, :routes, fn ->
          Enum.flat_map(plugins, fn {module, config} -> module.signal_routes(config) end)
        end)
    })
  end
end

defmodule JidoAI.Examples.ReasoningCapabilities.SetCase do
  use Jido.Action, name: "capabilities_set_case", schema: Zoi.object(%{case_id: Zoi.string()})
  def run(%{case_id: id}, context), do: {:ok, %{context.agent_state | case_id: id}}
end

defmodule JidoAI.Examples.ReasoningCapabilities.Agent do
  use Jido.Agent, name: "reasoning_capabilities_dsl"

  agent do
    schema Zoi.object(%{
             result: Zoi.any() |> Zoi.default(nil),
             review: Zoi.any() |> Zoi.default(nil),
             case_id: Zoi.string() |> Zoi.default("case-17")
           })

    plugin Jido.AI.Plugins.Reasoning.ChainOfThought, config: [into: :result, timeout: 5_000]
    plugin Jido.AI.Plugins.Reasoning.ChainOfDraft, config: [into: :review, timeout: 5_000]
  end

  routes do
    route "reasoning.cot.run", Jido.AI.Actions.Reasoning.RunCapability
    route "reasoning.cod.run", Jido.AI.Actions.Reasoning.RunCapability
    route "case.set", JidoAI.Examples.ReasoningCapabilities.SetCase
  end
end

defmodule JidoAI.Examples.ReasoningCapabilities.MixedAgent do
  use Jido.Agent, name: "native_and_callable_reasoning", extensions: [Jido.AI.DSL]

  agent do
    schema Zoi.object(%{
             result: Zoi.any() |> Zoi.default(nil),
             review: Zoi.any() |> Zoi.default(nil),
             case_id: Zoi.string() |> Zoi.default("case-17")
           })

    plugin Jido.AI.Plugins.Reasoning.ChainOfThought, config: [into: :review, timeout: 5_000]

    ai :assistant do
      models do
        model(:answer, JidoAI.Examples.MockLLM.model())
      end

      reasoning(:react, model: :answer)

      controls do
        max_iterations 2
        max_model_calls(2)
        timeout(5_000)
      end

      result(nil, into: :result)
    end
  end

  routes do
    route "ai.ask", ai(:assistant)
    route "reasoning.cot.run", Jido.AI.Actions.Reasoning.RunCapability
  end
end
