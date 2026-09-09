defmodule JidoAI.Examples.ContextOperations.Agent do
  use Jido.AI.Agent,
    name: "context_operations",
    model: %{
      id: "gpt-4o-mini",
      provider: :openai,
      provider_model_id: "gpt-4o-mini",
      extra: %{wire: %{protocol: "openai_chat"}}
    },
    tools: [JidoAI.Examples.RequestInspection.Hold],
    system_prompt: "Base prompt",
    streaming: false
end

defmodule JidoAI.Examples.ContextOperations.CaptureRefs do
  def transform_request(request, state, _config, context) do
    send(context.observer, {
      :model_message_refs,
      state.request_id,
      request.messages,
      Jido.AI.Context.to_messages(state.context)
    })

    {:ok, %{}}
  end
end

for {module, streaming?} <- [
      {JidoAI.Examples.ContextOperations.RefsBuffered, false},
      {JidoAI.Examples.ContextOperations.RefsStream, true}
    ] do
  defmodule module do
    use Jido.Agent, name: "context_refs", extensions: [Jido.AI.DSL]
    @streaming streaming?

    agent do
      schema Zoi.object(%{
               reply: Zoi.string() |> Zoi.default(""),
               messages: Zoi.list(Zoi.map()) |> Zoi.default([])
             })

      ai :assistant do
        models do
          model(:answer, JidoAI.Examples.MockLLM.model())
        end

        reasoning :react do
          model(:answer)
        end

        requests do
          mode(:session)
          streaming(@streaming)
          steering(true)
        end

        memory do
          history(:messages)
        end

        tools do
          action JidoAI.Examples.RequestInspection.Hold,
            as: :inspect_hold,
            forward_context: [:observer],
            timeout: 8_000
        end

        result(nil, into: :reply)
      end
    end

    routes do
      route "refs.ask", ai(:assistant)
    end
  end
end

defmodule JidoAI.Examples.ContextOperations.Profiles do
  use Jido.Agent, name: "context_profiles", extensions: [Jido.AI.DSL]

  agent do
    schema Zoi.object(%{
             reply: Zoi.any() |> Zoi.default(nil),
             review_reply: Zoi.any() |> Zoi.default(nil),
             messages: Zoi.list(Zoi.map()) |> Zoi.default([]),
             review_messages: Zoi.list(Zoi.map()) |> Zoi.default([])
           })

    ai :assistant do
      instructions("Assistant prompt")

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
        history(:messages)
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

      result(nil, into: :review_reply)
    end
  end

  routes do
    route "assistant.ask", ai(:assistant)
    route "review.ask", ai(:review)
  end
end
