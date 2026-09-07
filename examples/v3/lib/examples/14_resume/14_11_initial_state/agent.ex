defmodule JidoAI.Examples.InitialState.Echo do
  use Jido.Action,
    name: "import_echo",
    description: "Report any new tool execution",
    schema: Zoi.object(%{value: Zoi.integer()})

  def run(%{value: value}, context) do
    send(context.observer, {:import_tool_ran, value})
    {:ok, %{value: value}}
  end
end

for {module, stream} <- [
      {JidoAI.Examples.InitialState.Buffered, false},
      {JidoAI.Examples.InitialState.Streamed, true}
    ] do
  defmodule module do
    use Jido.Agent, name: "initial_state", extensions: [Jido.AI.DSL]
    @stream stream

    agent do
      schema(
        Zoi.object(%{
          reply: Zoi.string() |> Zoi.default(""),
          count: Zoi.integer(),
          thread: Zoi.map() |> Zoi.default(%{}),
          messages: Zoi.list(Zoi.map())
        })
      )

      ai :assistant do
        instructions("Configured")

        models do
          model(:answer, JidoAI.Examples.MockLLM.model())
        end

        tools do
          action(JidoAI.Examples.InitialState.Echo, as: :import_echo, forward_context: [:observer])
        end

        reasoning :react do
          model(:answer)
        end

        requests do
          mode(:session)
          streaming(@stream)
        end

        memory do
          history(:messages)
        end

        result(nil, into: :reply)
      end
    end

    routes do
      route("ai.react.query", ai(:assistant))
    end
  end
end

defmodule JidoAI.Examples.InitialState.PublicBuffered do
  use Jido.AI.Agent,
    name: "initial_public_buffered",
    tools: [JidoAI.Examples.InitialState.Echo],
    system_prompt: "Configured",
    streaming: false
end

defmodule JidoAI.Examples.InitialState.PublicStreamed do
  use Jido.AI.Agent,
    name: "initial_public_streamed",
    tools: [JidoAI.Examples.InitialState.Echo],
    system_prompt: "Configured",
    streaming: true
end

defmodule JidoAI.Examples.InitialState.Profiles do
  use Jido.Agent, name: "initial_profiles", extensions: [Jido.AI.DSL]

  agent do
    schema(
      Zoi.object(%{
        reply: Zoi.string() |> Zoi.default(""),
        primary_messages: Zoi.list(Zoi.map()) |> Zoi.default([]),
        review_messages: Zoi.list(Zoi.map()) |> Zoi.default([])
      })
    )

    ai :primary do
      instructions("Primary prompt")

      models do
        model(:answer, JidoAI.Examples.MockLLM.model())
      end

      reasoning :react do
        model(:answer)
      end

      requests do
        mode(:session)
      end

      memory do
        history(:primary_messages)
      end

      result(nil, into: :reply)
    end

    ai :review do
      instructions("Review prompt")

      models do
        model(:answer, JidoAI.Examples.MockLLM.model())
      end

      reasoning :react do
        model(:answer)
      end

      requests do
        mode(:session)
      end

      memory do
        history(:review_messages)
      end

      result(nil, into: :reply)
    end
  end

  routes do
    route("primary.ask", ai(:primary))
    route("review.ask", ai(:review))
  end
end
