defmodule JidoAI.Examples.MethodControls.Agent do
  use Jido.Agent, name: "selected_method_controls", extensions: [Jido.AI.DSL]

  agent do
    schema Zoi.object(%{reply: Zoi.any() |> Zoi.default(nil)})

    ai :assistant do
      models do
        model(:answer, JidoAI.Examples.MockLLM.model())
      end

      reasoning :adaptive do
        model(:answer)
        options(available_strategies: [:react, :trm])
      end

      controls do
        max_iterations :method_default
        max_model_calls(:method_default)
        max_tool_calls(:method_default)
      end

      tools do
        action JidoAI.Examples.ToT.Work, as: :tree_work, forward_context: [:observer]
      end

      requests do
        mode(:session)
        streaming(true)
      end

      result(nil, into: :reply)
    end
  end

  routes do
    route "work.query", ai(:assistant)
  end
end

defmodule JidoAI.Examples.MethodControls.Explicit do
  use Jido.AI.AdaptiveAgent,
    name: "explicit_method_controls",
    model: :example,
    tools: [JidoAI.Examples.ToT.Work],
    max_iterations: 12,
    max_tool_calls: 32
end

defmodule JidoAI.Examples.MethodControls do
  alias JidoAI.Examples.MethodControls.Agent

  def source do
    {_, config} = Enum.find(Agent.agent().plugins, &(elem(&1, 0) == Jido.AI.Runtime.Plugin))
    Map.from_struct(config[:profiles].assistant)
  end

  def base do
    %{
      name: Agent.agent().name,
      module: Agent,
      schema: Agent.domain_schema(),
      routes: [{"work.query", Jido.AI.Authoring.ai(:assistant)}]
    }
  end
end
