defmodule JidoAI.Examples.AIExtensionTest do
  use ExUnit.Case, async: false
  import JidoAI.Examples.Case
  alias JidoAI.Examples.MockLLM
  @moduletag :integration
  @desired JidoAI.Examples.DesiredAssistant

  setup do
    name = :"ai_v3_pending_#{System.unique_integer([:positive])}"
    start_supervised!({Jido, name: name})
    {:ok, jido: name}
  end

  test "nested AI syntax lowers to an ordinary Agent and Flow", %{jido: jido} do
    Code.compile_file(Path.expand("../../../specs/01_06_ai_extension.exs", __DIR__))
    definition = apply(@desired, :agent, [])
    assert %Jido.Agent{id: nil, state: nil} = definition

    assert [
             %{path: "ai.ask", target: {target, %{profile_id: :assistant}}},
             %{path: "jido.ai.configure", target: Jido.AI.Configuration.Apply},
             %{
               path: "ai.react.register_tool",
               target: {Jido.AI.Configuration.Apply, %{operation: :register}}
             },
             %{
               path: "ai.react.unregister_tool",
               target: {Jido.AI.Configuration.Apply, %{operation: :unregister}}
             },
             %{
               path: "ai.react.set_tool_context",
               target: {Jido.AI.Configuration.Apply, %{operation: :tool_context}}
             },
             %{
               path: "ai.react.set_system_prompt",
               target: {Jido.AI.Configuration.Apply, %{operation: :prompt}}
             }
           ] = definition.routes

    assert {:ok, _} = Jido.Executable.resolve(target)
    assert {:ok, document, registry} = Jido.Agent.Codec.encode(definition)
    assert {:ok, ^definition} = Jido.Agent.Codec.decode(document, registry)
    {mock, context} = mock([%{reply: {:object, %{answer: "Ready"}}}])
    server = start_agent(jido, Jido.Agent.instantiate!(definition))

    assert {:ok, %{state: %{reply: %{answer: "Ready"}, case_id: "case-42"}}} =
             ask(server, context)

    assert_script_done(mock)
  end

  test "common AI lowering composes with core data, Builder and JSON", %{jido: jido} do
    base =
      Jido.Agent.new!(
        name: "data_ai_assistant",
        schema:
          Zoi.object(%{
            reply: Zoi.map() |> Zoi.default(%{}),
            case_id: Zoi.string() |> Zoi.default("case-42")
          })
      )

    profile = %{
      id: :assistant,
      instructions: "Give a short answer.",
      models: %{answer: MockLLM.model()},
      reasoning: %{method: :react, model: :answer},
      controls: %{max_iterations: 2, max_model_calls: 2, timeout: 5_000},
      result: %{schema: Zoi.object(%{answer: Zoi.string()}), into: :reply, max_repairs: 0},
      routes: ["ai.ask"]
    }

    assert {:ok, lowered} = apply(Jido.AI.Authoring, :lower, [base, [profile]])
    attrs = lowered |> Jido.Agent.to_map() |> Map.drop([:id, :state])
    built = Jido.Agent.Builder.new(attrs) |> Jido.Agent.Builder.build!()
    direct = Jido.Agent.new!(attrs)
    {:ok, document, registry} = Jido.Agent.Codec.encode(lowered)

    {:ok, decoded} =
      document |> Jason.encode!() |> Jason.decode!() |> Jido.Agent.Codec.decode(registry)

    {mock, context} = mock(List.duplicate(%{reply: {:object, %{answer: "Ready"}}}, 4))

    for {definition, index} <- Enum.with_index([lowered, built, direct, decoded]) do
      assert definition == lowered
      server = start_agent(jido, Jido.Agent.instantiate!(definition, id: "ai-form-#{index}"))
      assert {:ok, agent} = ask(server, context)
      assert agent.state.case_id == "case-42"
      assert agent.state.reply in [%{answer: "Ready"}, %{"answer" => "Ready"}]
    end

    assert_script_done(mock)
  end

  test "invalid AI profiles fail before model work" do
    {mock, _context} = mock([])
    base = Jido.Agent.new!(name: "invalid_ai_assistant", schema: JidoAI.Examples.Schema.state())

    assert {:error, error} =
             apply(Jido.AI.Authoring, :lower, [
               base,
               [%{id: :assistant, models: %{}, reasoning: %{method: :react, model: :missing}}]
             ])

    assert is_exception(error)
    assert MockLLM.report(mock).requests == []
    assert_script_done(mock)
  end

  test "rich model aliases resolve at the request boundary and text output uses the same operation",
       %{jido: jido} do
    previous = Application.get_env(:jido_ai, :model_aliases)

    on_exit(fn ->
      if is_nil(previous),
        do: Application.delete_env(:jido_ai, :model_aliases),
        else: Application.put_env(:jido_ai, :model_aliases, previous)
    end)

    base =
      Jido.Agent.new!(
        name: "alias_ai",
        schema: Zoi.object(%{reply: Zoi.string() |> Zoi.default("")})
      )

    profile = %{
      id: :assistant,
      models: %{answer: %{model: :v3_example, generation: [temperature: 0.1]}},
      reasoning: %{method: :react, model: :answer},
      result: %{into: :reply},
      routes: ["ai.ask"]
    }

    assert {:ok, definition} = Jido.AI.Authoring.lower(base, [profile])
    Application.put_env(:jido_ai, :model_aliases, %{v3_example: MockLLM.model()})
    {mock, context} = mock([%{reply: {:text, "Plain answer"}}])
    server = start_agent(jido, Jido.Agent.instantiate!(definition))
    assert {:ok, %{state: %{reply: "Plain answer"}}} = ask(server, context)
    assert [request] = MockLLM.report(mock).requests
    assert request.body["temperature"] == 0.1
    assert Enum.map(request.body["messages"], & &1["role"]) == ["user"]
    assert_script_done(mock)
  end
end
