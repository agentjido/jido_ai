defmodule JidoAI.Examples.AuthoringFormatsTest do
  use JidoAI.Examples.Case, async: true
  alias JidoAI.Examples.AuthoringFormats
  alias Jido.Agent.{Builder, Codec}

  test "DSL, Builder, direct data and JSON have equal definitions and live results", %{jido: jido} do
    dsl = AuthoringFormats.Agent.agent()
    attrs = dsl |> Jido.Agent.to_map() |> Map.drop([:id, :state])
    direct = Jido.Agent.new!(attrs)

    built =
      Builder.new(module: dsl.module, name: dsl.name)
      |> Builder.schema(dsl.schema)
      |> Builder.route("ai.ask", AuthoringFormats.Flow)
      |> Builder.build!()

    {:ok, document, registry} = Codec.encode(dsl)
    {:ok, decoded} = document |> Jason.encode!() |> Jason.decode!() |> Codec.decode(registry)
    assert direct == dsl
    assert built == dsl
    assert decoded == dsl

    {mock, context} = mock(List.duplicate(%{reply: {:text, "Ready"}}, 5))
    initial = Jido.Agent.instantiate!(dsl, id: "pure")
    assert {:ok, candidate, []} = Jido.Agent.cmd(initial, signal(), context: context)

    for {definition, index} <- Enum.with_index([dsl, built, direct, decoded]) do
      agent = Jido.Agent.instantiate!(definition, id: "format-#{index}")
      server = start_agent(jido, agent)
      assert {:ok, committed} = ask(server, context)
      assert committed.state == candidate.state
      assert committed.state == %{answer: "Ready", case_id: "case-42", commits: 1}
      assert Server.snapshot(server) == %{agent: committed, state_version: 1}
    end

    assert_script_done(mock)
  end

  test "Flow forms compile to the same semantic identity and execute real model work" do
    alias Jido.Flow.Builder, as: FB
    dsl = AuthoringFormats.Flow.flow()

    {:ok, built} =
      FB.new(name: dsl.name, schema: dsl.schema)
      |> FB.step("model", JidoAI.Examples.Generate, %{query: FB.input(:query)})
      |> FB.step("candidate", JidoAI.Examples.Commit, FB.result("model"))
      |> FB.output(FB.result("candidate"))
      |> FB.build()

    direct =
      Jido.Flow.new!(
        name: dsl.name,
        schema: dsl.schema,
        components: [
          Jido.Flow.Step.new!(
            name: "model",
            action: JidoAI.Examples.Generate,
            params: %{query: Jido.Flow.Ref.input(:query)}
          ),
          Jido.Flow.Step.new!(
            name: "candidate",
            action: JidoAI.Examples.Commit,
            params: Jido.Flow.Ref.result("model")
          )
        ],
        output: Jido.Flow.Ref.result("candidate")
      )

    {:ok, registry} = Jido.Flow.Registry.from_flow(dsl)
    {:ok, document} = Jido.Flow.Codec.encode(dsl, registry)

    {:ok, decoded} =
      document |> Jason.encode!() |> Jason.decode!() |> Jido.Flow.Codec.decode(registry)

    {mock, context} = mock(List.duplicate(%{reply: {:text, "Ready"}}, 4))
    context = Map.put(context, :agent_state, AuthoringFormats.Agent.new!().state)

    for flow <- [dsl, built, direct, decoded] do
      assert flow == dsl
      assert Jido.Flow.semantic_identity(flow) == Jido.Flow.semantic_identity(dsl)

      assert {:ok, %{answer: "Ready", case_id: "case-42", commits: 1}} =
               Jido.Exec.run(flow, %{query: "Help"}, context, timeout: 5_000)
    end

    assert_script_done(mock)
  end
end
