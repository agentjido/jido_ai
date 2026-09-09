defmodule JidoAI.Examples.ContextViews.Replace do
  use Jido.Action, name: "replace_case_history"

  def run(%{entries: entries}, context) do
    agent = Jido.AI.update_context_entries(context.jido_ai_agent, entries)
    {:ok, agent.state}
  end
end

defmodule JidoAI.Examples.ContextViews.Agent do
  use Jido.AI.Agent,
    name: "context_views",
    tools: [],
    model: :context_example,
    system_prompt: "Review the case.",
    streaming: false,
    signal_routes: [{"case.history", JidoAI.Examples.ContextViews.Replace}]
end

defmodule JidoAI.Examples.ContextViews.Stateless do
  use Jido.Agent, name: "context_without_history", extensions: [Jido.AI.DSL]

  agent do
    schema Zoi.object(%{reply: Zoi.any() |> Zoi.default(nil)})

    ai :assistant do
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
    route "case.ask", ai(:assistant)
  end
end
