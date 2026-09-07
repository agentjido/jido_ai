defmodule JidoAI.Examples.Quota.Observe do
  use Jido.Action, name: "quota_observe", schema: Zoi.map()
  def run(_, context), do: {:ok, context.agent_state}
end

defmodule JidoAI.Examples.Quota.Echo do
  use Jido.Action, name: "quota_echo", schema: Zoi.object(%{text: Zoi.string()})
  def run(params, _), do: {:ok, params}
end

defmodule JidoAI.Examples.Quota.Reject do
  @behaviour Jido.AI.Control
  def check(_, _), do: Jido.AI.Profile.error("output", "Rejected after model usage")
end

defmodule JidoAI.Examples.Quota.ReasoningFlow do
  use Jido.Flow, name: "quota_reasoning", schema: Zoi.object(%{prompt: Zoi.string()})

  flow do
    step "reason",
      action: Jido.AI.Actions.Reasoning.RunStrategy,
      params: %{strategy: :cot, prompt: input(:prompt)}

    output result("reason")
  end
end

defmodule JidoAI.Examples.Quota do
  def definition(opts \\ []) do
    {mode, opts} = Keyword.pop(opts, :mode, :turn)
    {profile_opts, opts} = Keyword.pop(opts, :profile, %{})

    profile =
      Map.merge(
        %{
          id: :assistant,
          models: %{answer: %{model: JidoAI.Examples.MockLLM.model()}},
          reasoning: %{method: :react, model: :answer},
          controls: %{timeout: 5_000},
          result: %{into: :result},
          requests: %{mode: mode}
        },
        profile_opts
      )

    Jido.AI.Authoring.lower(
      %{
        name: "quota_example",
        schema:
          Zoi.object(%{
            result: Zoi.any() |> Zoi.default(nil),
            case_id: Zoi.string() |> Zoi.default("case-13")
          }),
        plugins: [
          {Jido.AI.Plugins.Quota, Keyword.merge([scope: "team"], opts)},
          {Jido.AI.Plugins.Chat, [default_model: JidoAI.Examples.MockLLM.model()]}
        ],
        routes:
          Jido.AI.Plugins.Quota.signal_routes([]) ++
            Jido.AI.Plugins.Chat.signal_routes([]) ++
            [
              {"case.review", Jido.AI.Authoring.ai(:assistant)},
              {"ai.usage", __MODULE__.Observe},
              {"case.note", __MODULE__.Observe}
            ]
      },
      [profile]
    )
  end

  def signal(type, data), do: Jido.Signal.new!(type, data, source: "/examples/quota")
end

defmodule JidoAI.Examples.Quota.Agent do
  use Jido.Agent, name: "quota_dsl", extensions: [Jido.AI.DSL]

  agent do
    schema Zoi.object(%{
             result: Zoi.any() |> Zoi.default(nil),
             case_id: Zoi.string() |> Zoi.default("case-13")
           })

    plugin Jido.AI.Plugins.Quota, config: [scope: "dsl", max_requests: 1]

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
    route "quota.status", Jido.AI.Actions.Quota.RunCapability
    route "quota.reset", Jido.AI.Actions.Quota.RunCapability
    route "case.review", ai(:assistant)
  end
end
