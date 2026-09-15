defmodule JidoAI.Examples.Session.Agent do
  @moduledoc "A request session can run while ordinary domain commands commit."
  # This lesson composes the core extension with explicit Request helpers.
  use Jido.Agent, name: "ai_session_example", extensions: [Jido.AI.DSL]

  agent do
    schema Zoi.object(%{
             reply: Zoi.string() |> Zoi.default(""),
             case_id: Zoi.string() |> Zoi.default("open")
           })

    plugin JidoAI.Examples.Support.CommitCounter

    ai :assistant do
      instructions("Use tools when required.")

      models do
        model(:answer, JidoAI.Examples.MockLLM.model())
      end

      reasoning :react do
        model(:answer)
      end

      requests do
        mode(:session)
        on_busy(:reject)
        max_requests(2)
      end

      controls do
        timeout(10_000)
      end

      tools do
        action JidoAI.Examples.Support.Multiply, as: :multiply
      end

      result(nil, into: :reply)
    end
  end

  routes do
    signal_source "/examples/ai/session"
    route "ai.ask", ai(:assistant)

    route "case.close", JidoAI.Examples.Support.CloseCase do
      define :close, args: [:reason]
    end
  end

  def ask(server, query, opts \\ []),
    do:
      Jido.AI.Request.create_and_send(
        server,
        query,
        Keyword.merge(opts, signal_type: "ai.ask", source: "/examples/ai/session")
      )

  def ask_stream(server, query, opts \\ []) do
    with {:ok, request} <- ask(server, query, Keyword.put(opts, :stream_to, self())),
         do: {:ok, request, Jido.AI.Request.Stream.events(request, opts)}
  end
end
