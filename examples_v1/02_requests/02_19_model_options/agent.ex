defmodule JidoAI.Examples.ModelOptions.Agent do
  @moduledoc "A native Agent uses one reasoning Flow across different provider formats."
  use Jido.AI.Agent, name: "provider_switch"

  agent do
    schema(Zoi.object(%{reply: Zoi.string() |> Zoi.default("")}))

    ai :assistant do
      models do
        model(:answer, JidoAI.Examples.MockLLM.model())
      end

      reasoning :react do
        model(:answer)
        request_transformer(JidoAI.Examples.ModelOptions.Switch)
      end

      observability do
        store_content true
      end

      tools do
        action(JidoAI.Examples.ModelOptions.SwitchProbe, as: :switch_probe)
      end

      result(nil, into: :reply)
    end
  end

  routes do
    route("ai.ask", ai(:assistant))
  end
end
