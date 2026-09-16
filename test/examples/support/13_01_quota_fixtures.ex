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

defmodule JidoAI.Examples.Quota do
  def definition(opts \\ []) do
    {_legacy_mode, opts} = Keyword.pop(opts, :mode, :turn)
    {profile_opts, opts} = Keyword.pop(opts, :profile, %{})

    profile =
      Map.merge(
        %{
          id: :assistant,
          models: %{answer: %{model: JidoAI.Examples.MockLLM.model()}},
          reasoning: %{method: :react, model: :answer},
          controls: %{timeout: 5_000},
          result: %{into: :result}
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
