defmodule JidoAI.Examples.Admission.CoT do
  use Jido.AI.CoTAgent, name: "admission_cot", model: :example, streaming: false
end

defmodule JidoAI.Examples.Admission.CoD do
  use Jido.AI.CoDAgent, name: "admission_cod", model: :example, streaming: false
end

defmodule JidoAI.Examples.Admission.Agent do
  @moduledoc "Request events use the method declared by the selected route."
  use Jido.Agent, name: "admission_routes", extensions: [Jido.AI.DSL]

  agent do
    schema Zoi.object(%{reply: Zoi.string() |> Zoi.default("")})
    plugin Jido.AI.Plugins.Policy

    ai :review do
      models do
        model(:answer, JidoAI.Examples.MockLLM.model())
      end

      reasoning :chain_of_thought do
        model(:answer)
      end

      requests do
        mode(:session)
        streaming(false)
      end

      result(nil, into: :reply)
    end

    ai :answer do
      models do
        model(:answer, JidoAI.Examples.MockLLM.model())
      end

      reasoning :react do
        model(:answer)
      end

      requests do
        mode(:session)
        streaming(false)
      end

      result(nil, into: :reply)
    end
  end

  routes do
    route "case.review", ai(:review)
    route "ai.react.query", ai(:review)
    route "case.answer", ai(:answer)
  end
end
