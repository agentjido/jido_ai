defmodule JidoAI.Examples.StreamUsage.Echo do
  @moduledoc "A real tool used to separate usage from two model calls."
  use Jido.Action, name: "usage_echo", schema: Zoi.object(%{n: Zoi.integer()})

  def run(%{n: n}, context) do
    send(context.observer, {:usage_tool, n})
    {:ok, %{n: n}}
  end
end

for {module, capture?} <- [
      {JidoAI.Examples.StreamUsage.Agent, true},
      {JidoAI.Examples.StreamUsage.QuietAgent, false}
    ] do
  defmodule module do
    @moduledoc "A native Agent with explicit stream observation and shared model accounting."
    @capture capture?
    use Jido.Agent, name: "stream_usage_example", extensions: [Jido.AI.DSL]

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
          action(JidoAI.Examples.StreamUsage.Echo, as: :usage_echo, forward_context: [:observer])
        end

        requests do
          mode(:session)
          streaming(true)
        end

        observability do
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
