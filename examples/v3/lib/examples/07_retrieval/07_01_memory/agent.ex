defmodule JidoAI.Examples.Retrieval do
  alias Jido.AI.Plugins.{Chat, Retrieval}

  def definition(opts \\ []) do
    {mode, opts} = Keyword.pop(opts, :request_mode, :turn)

    Jido.AI.Authoring.lower(
      %{
        name: "memory_assistant",
        schema:
          Zoi.object(%{
            result: Zoi.any() |> Zoi.default(nil),
            case_id: Zoi.string() |> Zoi.default("case-7")
          }),
        plugins: [
          {Retrieval, Keyword.merge([namespace: "weather"], opts)},
          {Chat, [default_model: JidoAI.Examples.MockLLM.model()]}
        ],
        routes:
          Retrieval.signal_routes([]) ++
            Chat.signal_routes([]) ++
            [{"case.review", Jido.AI.Authoring.ai(:assistant)}]
      },
      [
        %{
          id: :assistant,
          models: %{answer: %{model: JidoAI.Examples.MockLLM.model()}},
          reasoning: %{method: :react, model: :answer},
          controls: %{timeout: 5_000},
          result: %{into: :result},
          requests: %{mode: mode}
        }
      ]
    )
  end

  def signal(type, data), do: Jido.Signal.new!(type, data, source: "/examples/retrieval")
end

defmodule JidoAI.Examples.Retrieval.Agent do
  use Jido.Agent, name: "memory_dsl", extensions: [Jido.AI.DSL]

  agent do
    schema Zoi.object(%{
             result: Zoi.any() |> Zoi.default(nil),
             case_id: Zoi.string() |> Zoi.default("case-7")
           })

    plugin Jido.AI.Plugins.Retrieval, config: [namespace: "weather"]

    ai :assistant do
      models do
        model(:answer, JidoAI.Examples.MockLLM.model())
      end

      reasoning(:react, model: :answer)

      tools do
        action Jido.AI.Actions.Retrieval.RecallMemory,
          as: :recall_memory,
          forward_context: [:state, :retrieval_store]
      end

      controls do
        timeout(5_000)
      end

      result(nil, into: :result)
    end
  end

  routes do
    route "retrieval.upsert", Jido.AI.Actions.Retrieval.RunCapability
    route "retrieval.recall", Jido.AI.Actions.Retrieval.RunCapability
    route "retrieval.clear", Jido.AI.Actions.Retrieval.RunCapability
    route "case.review", ai(:assistant)
  end
end
