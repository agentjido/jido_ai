for {module, capture?} <- [
      {JidoAI.Examples.StreamUsage.Agent, true},
      {JidoAI.Examples.StreamUsage.QuietAgent, false}
    ] do
  defmodule module do
    @moduledoc "A native Agent with explicit stream observation and shared model accounting."
    @capture capture?
    use Jido.AI.Agent, name: "stream_usage_example"

    agent do
      schema(Zoi.object(%{reply: Zoi.string() |> Zoi.default("")}))

      ai :assistant do
        models do
          model(:answer, JidoAI.Examples.MockLLM.model())
        end

        reasoning :react do
          model(:answer)
        end

        tools do
          action(JidoAI.Examples.StreamUsage.Echo, as: :usage_echo)
        end

        observability do
          store_content true
          emit_llm_deltas(@capture)
        end

        result(nil, into: :reply)
      end
    end

    routes do
      route("ai.ask", ai(:assistant))
    end
  end
end
