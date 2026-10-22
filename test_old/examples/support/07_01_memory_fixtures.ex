defmodule JidoAI.Examples.Retrieval do
  alias Jido.AI.Plugins.{Chat, Retrieval}

  def definition(opts \\ []) do
    {_legacy_mode, opts} = Keyword.pop(opts, :request_mode, :turn)

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
          result: %{into: :result}
        }
      ]
    )
  end

  def signal(type, data), do: Jido.Signal.new!(type, data, source: "/examples/retrieval")
end
