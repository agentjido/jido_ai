for {module, stream} <- [
      {JidoAI.Examples.InitialState.Buffered, false},
      {JidoAI.Examples.InitialState.Streamed, true}
    ] do
  defmodule module do
    use Jido.AI.Agent, name: "initial_state"
    @stream stream

    agent do
      schema(
        Zoi.object(%{
          reply: Zoi.string() |> Zoi.default(""),
          count: Zoi.integer(),
          thread: Zoi.map() |> Zoi.default(%{}),
          messages: Jido.Session.schema()
        })
      )

      ai :assistant do
        instructions("Configured")

        models do
          model(:answer, JidoAI.Examples.MockLLM.model())
        end

        tools do
          action(JidoAI.Examples.InitialState.Echo,
            as: :import_echo
          )
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

defmodule JidoAI.Examples.InitialState.Profiles do
  use Jido.AI.Agent, name: "initial_profiles"

  agent do
    schema(
      Zoi.object(%{
        reply: Zoi.string() |> Zoi.default(""),
        primary_messages: Jido.AI.Thread.Projection.schema(),
        review_messages: Jido.AI.Thread.Projection.schema()
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
