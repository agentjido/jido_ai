defmodule JidoAI.Examples.RoutingPolicy do
  alias Jido.AI.Plugins.{Chat, ModelRouting, Policy}

  def definition(opts \\ []) do
    plugins = [
      {ModelRouting, Keyword.get(opts, :routing, [])},
      {Policy, Keyword.get(opts, :policy, [])},
      {Chat, []},
      {Jido.AI.Plugins.Reasoning.ChainOfThought,
       [
         profile:
           Jido.AI.Profile.new!(%{
             id: :assistant,
             model: JidoAI.Examples.MockLLM.model(),
             reasoning: :chain_of_thought,
             controls: %{timeout: 5_000},
             requests: %{mode: :session},
             result: %{into: :result}
           })
       ]}
    ]

    plugins = if opts[:reverse], do: Enum.reverse(plugins), else: plugins

    Jido.Agent.new(%{
      name: "routing_policy",
      schema: schema(),
      plugins: plugins,
      routes:
        Chat.signal_routes([]) ++
          Jido.AI.Plugins.Reasoning.ChainOfThought.signal_routes([]) ++ observation_routes()
    })
  end

  def native(mode, opts \\ []) do
    Jido.AI.Authoring.lower(
      %{
        name: "native_policy",
        schema: schema(),
        plugins: [
          {ModelRouting, Keyword.get(opts, :routing, [])},
          {Policy, Keyword.get(opts, :policy, [])}
        ],
        routes: [{"case.review", Jido.AI.Authoring.ai(:assistant)} | observation_routes()]
      },
      [
        %{
          id: :assistant,
          models: %{answer: %{model: JidoAI.Examples.MockLLM.model()}},
          reasoning: %{method: :react, model: :answer},
          result: %{into: :result},
          requests: %{mode: mode},
          controls: %{timeout: 5_000}
        }
      ]
    )
  end

  def signal(type, data), do: Jido.Signal.new!(type, data, source: "/examples/routing-policy")

  def schema,
    do:
      Zoi.object(%{
        result: Zoi.any() |> Zoi.default(nil),
        observed: Zoi.any() |> Zoi.default(nil),
        case_id: Zoi.string() |> Zoi.default("case-17")
      })

  def observation_routes,
    do:
      Enum.map(
        [
          "ai.llm.delta",
          "ai.llm.response",
          "ai.tool.result",
          "ai.request.error",
          "case.note",
          "reasoning.cot.worker.run"
        ],
        &{&1, __MODULE__.Capture}
      )
end
