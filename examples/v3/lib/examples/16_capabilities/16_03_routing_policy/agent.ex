defmodule JidoAI.Examples.RoutingPolicy.Capture do
  use Jido.Action, name: "routing_policy_capture", schema: Zoi.map()

  def run(params, context),
    do: {:ok, %{context.agent_state | observed: %{type: context.signal.type, data: params}}}
end

defmodule JidoAI.Examples.RoutingPolicy.Agent do
  use Jido.Agent, name: "routing_policy_dsl", extensions: [Jido.AI.DSL]

  agent do
    schema Zoi.object(%{
             result: Zoi.any() |> Zoi.default(nil),
             observed: Zoi.any() |> Zoi.default(nil),
             case_id: Zoi.string() |> Zoi.default("case-17")
           })

    plugin Jido.AI.Plugins.ModelRouting, config: [routes: %{"case.review" => :capable}]
    plugin Jido.AI.Plugins.Policy

    ai :assistant do
      models do
        model(:answer, JidoAI.Examples.MockLLM.model())
      end

      reasoning(:react, model: :answer)

      controls do
        timeout(5_000)
      end

      result(nil, into: :result)
    end
  end

  routes do
    route "case.review", ai(:assistant)
    route "case.note", JidoAI.Examples.RoutingPolicy.Capture
  end
end

defmodule JidoAI.Examples.RoutingPolicy do
  alias Jido.AI.Plugins.{Chat, ModelRouting, Policy}

  def definition(opts \\ []) do
    plugins = [
      {ModelRouting, Keyword.get(opts, :routing, [])},
      {Policy, Keyword.get(opts, :policy, [])},
      {Chat, []},
      {Jido.AI.Plugins.Reasoning.ChainOfThought, [timeout: 5_000]}
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
