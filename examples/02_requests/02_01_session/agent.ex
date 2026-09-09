defmodule JidoAI.Examples.Session.ObserveOwner do
  @moduledoc "Exposes the resource owner to the example's failure checks."
  @behaviour Jido.AI.Control
  def check(_, context) do
    {owner, id, _} = context.jido_ai_events
    send(context.observer, {:session_owner, owner, id})
    :ok
  end
end

defmodule JidoAI.Examples.Session.Agent do
  @moduledoc "A request session can run while ordinary domain commands commit."
  use Jido.Agent, name: "ai_session_example", extensions: [Jido.AI.DSL]

  agent do
    schema Zoi.object(%{
             reply: Zoi.string() |> Zoi.default(""),
             case_id: Zoi.string() |> Zoi.default("open")
           })

    plugin JidoAI.Examples.AIRuntime.Audit

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
        input(JidoAI.Examples.Session.ObserveOwner)
      end

      tools do
        action JidoAI.Examples.ToolFlow.Multiply, as: :multiply, forward_context: [:observer]

        action JidoAI.Examples.AIRuntime.WaitTool,
          as: :wait,
          forward_context: [:observer],
          timeout: 8_000
      end

      result(nil, into: :reply)
    end
  end

  routes do
    signal_source "/examples/ai/session"
    route "ai.ask", ai(:assistant)

    route "case.close", JidoAI.Examples.AIRuntime.Close do
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
