defmodule JidoAITest.Authoring.Agents.Cases do
  @moduledoc false
  alias Jido.AI.Test.MockLLM
  alias JidoAITest.Authoring.Agents.Fixtures

  def variants, do: [:simple, :tool, :structured, :session, :multi, :policy, :cot]

  def spec(id) do
    profiles = profiles(id)
    module = Module.concat(Fixtures, id |> Atom.to_string() |> Macro.camelize())
    schema = schema(id)

    %{
      id: id,
      module: module,
      profiles: profiles,
      attrs: %{
        module: module,
        vsn: 1,
        name: "authoring_ai_#{id}",
        schema: schema,
        metadata: %{"case" => Atom.to_string(id)},
        plugins: plugins(id),
        routes: Enum.map(profiles, &{"case.#{&1.id}", Jido.AI.Authoring.ai(&1.id)})
      },
      initial: initial(id),
      invalid_state: %{case_id: 42},
      override: %{case_id: "override"},
      steps: steps(id)
    }
  end

  def schema(:structured),
    do: Zoi.object(%{reply: Zoi.map() |> Zoi.default(%{}), case_id: Zoi.string() |> Zoi.default("case-17")})

  def schema(:session),
    do:
      Zoi.object(%{
        reply: Zoi.string() |> Zoi.default(""),
        case_id: Zoi.string() |> Zoi.default("case-17"),
        messages: Zoi.list(Zoi.map()) |> Zoi.default([])
      })

  def schema(:multi),
    do:
      Zoi.object(%{
        reply: Zoi.string() |> Zoi.default(""),
        review: Zoi.string() |> Zoi.default(""),
        case_id: Zoi.string() |> Zoi.default("case-17")
      })

  def schema(_),
    do: Zoi.object(%{reply: Zoi.string() |> Zoi.default(""), case_id: Zoi.string() |> Zoi.default("case-17")})

  def output_schema, do: Zoi.object(%{answer: Zoi.string()})

  defp base do
    %{
      id: :assistant,
      models: %{default: %{model: MockLLM.model()}},
      instructions: "Use the case facts.",
      controls: %{timeout: 5_000},
      result: %{into: :reply}
    }
  end

  def profiles(:tool) do
    [
      Map.put(base(), :tools, [
        %{
          name: "double",
          description: "Double an integer",
          target: Fixtures.Double,
          timeout: 5_000,
          forward_context: :public
        }
      ])
    ]
  end

  def profiles(:structured), do: [Map.put(base(), :result, %{into: :reply, schema: output_schema()})]

  def profiles(:session),
    do: [
      Map.merge(base(), %{
        requests: %{mode: :session, streaming: true, max_requests: 3},
        memory: %{history: :messages}
      })
    ]

  def profiles(:multi),
    do: [
      base(),
      %{base() | id: :reviewer, models: %{default: %{model: MockLLM.model("gpt-4o")}}, result: %{into: :review}}
    ]

  def profiles(:cot), do: [Map.put(base(), :reasoning, %{method: :chain_of_thought})]
  def profiles(_), do: [base()]

  defp plugins(:policy),
    do: [
      {Jido.AI.Plugins.Policy, [mode: :enforce]},
      {Jido.AI.Plugins.ModelRouting, [routes: %{"case.assistant" => MockLLM.model("gpt-4o")}]}
    ]

  defp plugins(_), do: []

  defp initial(id) do
    state = %{reply: "", case_id: "case-17", jido_ai_config: %{}}

    case id do
      :structured ->
        %{state | reply: %{}}

      :session ->
        Map.merge(state, %{messages: [], requests: %{}, jido_ai_contexts: %{}})

      :multi ->
        Map.put(state, :review, "")

      :policy ->
        Map.merge(state, %{
          policy: %{mode: :enforce, max_delta_chars: 4000, block_on_validation_error: true},
          model_routing: %{
            routes: %{
              "case.assistant" => MockLLM.model("gpt-4o"),
              "chat.message" => :capable,
              "chat.simple" => :fast,
              "chat.complete" => :fast,
              "chat.embed" => :embedding,
              "chat.generate_object" => :thinking,
              "reasoning.*.run" => :reasoning
            }
          }
        })

      _ ->
        state
    end
  end

  defp steps(:tool),
    do: [
      %{
        profile: :assistant,
        query: "Double three",
        result: "Six",
        field: :reply,
        model: "gpt-4o-mini",
        replies: [
          {:tools, [%{id: "double-1", name: "double", arguments: %{value: 3}}]},
          {:text, "Six"}
        ]
      }
    ]

  defp steps(:structured),
    do: [
      %{
        profile: :assistant,
        query: "Give the answer",
        result: %{answer: "Ready"},
        field: :reply,
        model: "gpt-4o-mini",
        replies: [{:object, %{answer: "Ready"}}]
      }
    ]

  defp steps(:multi),
    do: [
      text_step(:assistant, :reply, "First", "gpt-4o-mini"),
      text_step(:reviewer, :review, "Reviewed", "gpt-4o")
    ]

  defp steps(:session),
    do: [
      text_step(:assistant, :reply, "First", "gpt-4o-mini"),
      text_step(:assistant, :reply, "Second", "gpt-4o-mini")
    ]

  defp steps(:policy), do: [text_step(:assistant, :reply, "Ready", "gpt-4o")]
  defp steps(_), do: [text_step(:assistant, :reply, "Ready", "gpt-4o-mini")]

  defp text_step(profile, field, text, model),
    do: %{
      profile: profile,
      query: "Help #{text}",
      result: text,
      field: field,
      model: model,
      replies: [{:text, text}]
    }
end
