defmodule JidoAI.Examples.Session.Agent do
  @moduledoc "A request session can run while ordinary domain commands commit."
  use Jido.AI.Agent, name: "ai_session_example"

  agent do
    schema Zoi.object(%{
             reply: Zoi.string() |> Zoi.default(""),
             case_id: Zoi.string() |> Zoi.default("open")
           })

    plugin JidoAI.Examples.Support.CommitCounter

    ai :assistant do
      instructions "Use tools when required."

      models do
        model :answer, JidoAI.Examples.MockLLM.model()
      end

      reasoning :react do
        model :answer
      end

      requests do
        mode :session
        streaming true
        on_busy :reject
        max_requests 2
      end

      controls do
        timeout 10_000
      end

      observability do
        store_content true
      end

      tools do
        action JidoAI.Examples.Support.Multiply, as: :multiply
      end

      result nil, into: :reply
    end
  end

  routes do
    signal_source "/examples/ai/session"
    route "ai.ask", ai(:assistant)

    route "case.close", JidoAI.Examples.Support.CloseCase do
      define :close, args: [:reason]
    end
  end
end
