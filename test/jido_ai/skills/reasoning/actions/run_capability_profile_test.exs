defmodule Jido.AI.Actions.Reasoning.RunCapabilityProfileTest do
  use Jido.AI.Test.CallableReasoningCase, async: false
  alias Jido.AI.Plugins.{ModelRouting, Quota, Retrieval}
  alias Jido.AI.Plugins.Reasoning.{ChainOfThought, ChainOfDraft}
  alias Jido.AI.Quota.Store, as: QuotaStore
  alias Jido.AI.Retrieval.Store, as: RetrievalStore
  alias Jido.AgentServer, as: Server

  test "two capabilities compose with retrieval, routing, quota, and independent domain results", %{jido: jido} do
    start_supervised!({QuotaStore, []})
    start_supervised!({RetrievalStore, []})
    %{id: "fact"} = RetrievalStore.upsert("callable", %{id: "fact", text: "Tokyo weather is clear"})
    mock = start_supervised!({MockLLM, script: script(:cot) ++ script(:cod)})
    cot = callable_profile(:chain_of_thought)
    cod = callable_profile(:chain_of_draft, %{id: :draft, result: %{into: :draft}})

    agent =
      definition(cot, [
        {ChainOfDraft, [profile: cod]},
        {Retrieval, [namespace: "callable"]},
        {ModelRouting, [routes: %{"reasoning.*.run" => MockLLM.model()}]},
        {Quota, [scope: "callable", max_requests: 2]}
      ])

    server = start_supervised!({Server, agent: agent, jido: jido})
    options = MockLLM.options(mock)
    context = %{jido: jido, ai: %{review: %{options: options}, draft: %{options: options}}}
    assert {:ok, first} = Server.call(server, signal("cot"), context: context, timeout: 8_000)
    assert first.state.answer.output == "Four"
    assert first.state.answer.strategy == :cot
    assert first.state.draft == "Previous draft"
    assert first.state.case_id == "case-17"
    assert {:ok, second} = Server.call(server, signal("cod"), context: context, timeout: 8_000)
    assert second.state.answer == first.state.answer
    assert second.state.draft.output == "Four"
    assert second.state.draft.strategy == :cod
    assert second.state.reasoning_cot == %{}
    assert second.state.reasoning_cod == %{}
    status = QuotaStore.status("callable", %{max_requests: 2}, 60_000)
    assert status.usage.requests == 2
    assert status.usage.total_tokens == 30
    assert {:error, _} = Server.call(server, signal("cot"), context: context, timeout: 8_000)
    assert Server.agent(server).state == second.state
    assert %{remaining: [], unexpected: [], requests: requests} = MockLLM.report(mock)
    assert length(requests) == 2

    for request <- requests do
      assert request.body["model"] == "gpt-4o-mini"
      assert inspect(request.body["messages"]) =~ "Tokyo weather is clear"
      assert inspect(request.body["messages"]) =~ "Relevant memory"
    end
  end

  test "provider failure preserves domain and Plugin state", %{jido: jido} do
    mock = start_supervised!({MockLLM, script: [%{reply: {:error, 503, "Private provider detail"}}]})
    profile = callable_profile(:chain_of_thought)
    agent = definition(profile)
    server = start_supervised!({Server, agent: agent, jido: jido})
    before = Server.agent(server).state

    assert {:error, error} =
             Server.call(server, signal("cot"),
               context: %{jido: jido, ai: %{review: %{options: MockLLM.options(mock)}}},
               timeout: 8_000
             )

    assert Server.agent(server).state == before
    refute inspect(error) =~ "Private provider detail"
    assert %{remaining: [], unexpected: []} = MockLLM.report(mock)
  end

  test "routing validates the selected model before provider work" do
    agent =
      definition(callable_profile(:chain_of_thought), [{ModelRouting, [routes: %{"reasoning.cot.run" => false}]}])
      |> Jido.Agent.instantiate!()

    assert {:error, error} = Jido.Agent.cmd(agent, signal("cot"))
    assert inspect(error) =~ "models"
    assert agent.state.answer == "Previous answer"
  end

  test "result must select a domain field" do
    profile = callable_profile(:chain_of_thought, %{result: %{into: :reasoning_cot}})
    agent = definition(profile) |> Jido.Agent.instantiate!()
    assert {:error, _} = Jido.Agent.cmd(agent, signal("cot"))
    assert agent.state.reasoning_cot == %{}
  end

  test "the domain schema rejects an incompatible result envelope", %{jido: jido} do
    mock = start_supervised!({MockLLM, script: script(:cot)})
    profile = callable_profile(:chain_of_thought)

    agent =
      Jido.Agent.new!(%{
        name: "typed_callable_host",
        schema: Zoi.object(%{answer: Zoi.string() |> Zoi.default("Previous answer")}),
        plugins: [{ChainOfThought, [profile: profile]}],
        routes: ChainOfThought.signal_routes([])
      })
      |> Jido.Agent.instantiate!()

    assert {:error, _} =
             Jido.Agent.cmd(agent, signal("cot"),
               context: %{
                 jido: jido,
                 ai: %{review: %{options: MockLLM.options(mock)}}
               }
             )

    assert agent.state.answer == "Previous answer"
    assert %{remaining: [], unexpected: []} = MockLLM.report(mock)
    assert Jido.list_agents(jido) == []
  end

  defp signal(method), do: Jido.Signal.new!("reasoning.#{method}.run", %{"prompt" => "Tokyo weather"}, source: "/test")

  defp definition(profile, plugins \\ []) do
    Jido.Agent.new!(%{
      name: "callable_composition",
      schema:
        Zoi.object(%{
          answer: Zoi.any() |> Zoi.default("Previous answer"),
          draft: Zoi.any() |> Zoi.default("Previous draft"),
          case_id: Zoi.string() |> Zoi.default("case-17")
        }),
      plugins: [{ChainOfThought, [profile: profile]} | plugins],
      routes: ChainOfThought.signal_routes([]) ++ ChainOfDraft.signal_routes([])
    })
  end
end
