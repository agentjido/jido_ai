Code.require_file("../support/agents/corpus.exs", __DIR__)

defmodule JidoAITest.Authoring.Agents.InterfacesTest do
  use ExUnit.Case, async: false
  use Mimic
  @moduletag :authoring
  alias Jido.AI.Test.MockLLM
  alias Jido.AgentServer, as: Server
  alias JidoAITest.Authoring.Agents.Corpus

  setup do
    jido = :"ai_authoring_interfaces_#{System.unique_integer([:positive])}"
    start_supervised!({Jido, name: jido})
    {:ok, jido: jido}
  end

  test "generated route Signal helpers retain input, source, and fresh IDs" do
    spec = Corpus.load!(:simple)
    assert {:ok, first} = spec.module.submit_signal("Help")
    assert {:ok, second} = spec.module.submit_signal("Help")
    assert first.type == "case.assistant"
    assert first.data == %{query: "Help"}
    assert first.source == "/authoring/ai"
    refute first.id == second.id
  end

  test "generated core route helper runs the AI route with caller context", %{jido: jido} do
    {spec, server, mock, context} = start_case(jido, :simple, [{:text, "Ready"}])
    assert {:ok, agent} = spec.module.submit(server, "Help", context: context)
    assert agent.state === %{spec.initial | reply: "Ready"}
    assert_done(mock)
  end

  test "session ask_sync preserves caller context and waits for the result", %{jido: jido} do
    {spec, server, mock, context} = start_case(jido, :session, [{:text, "Ready"}])
    assert {:ok, "Ready"} = spec.module.ask_sync(server, "Help", context: context, timeout: 5_000)
    assert Server.agent(server).state.reply == "Ready"
    assert_done(mock)
  end

  test "session ask_stream yields a terminal stream and complete request record", %{jido: jido} do
    {spec, server, mock, context} = start_case(jido, :session, [{:text, "Streamed"}])

    assert {:ok, %{request: request, events: events}} =
             spec.module.ask_stream(server, "Help", context: context, timeout: 5_000)

    collected = Enum.to_list(events)
    assert hd(collected).kind == :request_started
    assert List.last(collected).kind == :request_completed
    assert Enum.all?(collected, &(&1.request_id == request.id))
    assert {:ok, "Streamed"} = spec.module.await(request, timeout: 5_000)
    assert Server.agent(server).state.requests[request.id].status == :completed
    assert_done(mock)
  end

  test "multiple profiles require explicit selection before model work", %{jido: jido} do
    {spec, server, mock, context} = start_case(jido, :multi, [])
    before = Server.snapshot(server)
    assert {:error, error} = spec.module.ask(server, "Help", context: context)
    assert Exception.message(error) =~ "Select one routed AI profile"
    assert {:error, _} = spec.module.ask(server, "Help", profile: :missing, context: context)
    assert Server.snapshot(server) === before
    assert_done(mock)
  end

  test "session rejects concurrent work without changing the admitted request", %{jido: jido} do
    {spec, server, mock, context} = start_case(jido, :session, [{:wait, :finish, {:text, "Done"}}])
    assert {:ok, request} = spec.module.ask(server, "First", context: context, request_id: "first")
    assert_receive {:mock_llm_waiting, ^mock, :finish, _}, 5_000
    first = Server.agent(server).state.requests["first"]
    assert first.status == :pending
    assert {:error, :busy} = spec.module.ask(server, "Second", context: context, request_id: "second")
    assert Server.agent(server).state.requests == %{"first" => first}
    assert :ok = MockLLM.release(mock, :finish)
    assert {:ok, "Done"} = spec.module.await(request, timeout: 5_000)
    assert_done(mock)
  end

  defp start_case(jido, variant, replies) do
    spec = Corpus.load!(variant)
    mock = start_supervised!({MockLLM, script: Enum.map(replies, &%{reply: &1}), observer: self()})
    context = %{ai: Map.new(spec.profiles, &{&1.id, %{options: MockLLM.options(mock)}})}
    {:ok, server} = Jido.start_agent(jido, Corpus.definition(spec, :module))
    {spec, server, mock, context}
  end

  test "inline instructions and tools survive Builder and Codec and execute", %{jido: jido} do
    JidoAITest.Authoring.Compiler.require_file!(Corpus.fixture("inline.exs"))
    module = JidoAITest.Authoring.Agents.Fixtures.Inline
    definition = apply(module, :definition, [])
    profile = apply(module, :ai_profile, [:assistant])
    assert {:ok, %{kind: :action}} = Jido.Executable.resolve(profile.instructions)
    assert [%{name: "echo", target: target}] = profile.tools
    assert {:ok, %{kind: :action}} = Jido.Executable.resolve(target)

    {:ok, doc, registry} = Jido.Agent.Codec.encode(definition)
    {:ok, decoded} = Jido.Agent.Codec.decode(Jason.decode!(Jason.encode!(doc)), registry)
    built = Jido.Agent.Builder.new(module) |> Jido.Agent.Builder.build!()
    assert decoded === definition
    assert built === definition

    script =
      List.duplicate(
        [
          %{reply: {:tools, [%{id: "echo-1", name: "echo", arguments: %{value: "hello"}}]}},
          %{reply: {:text, "Echoed"}}
        ],
        3
      )
      |> List.flatten()

    mock = start_supervised!({MockLLM, script: script})
    context = %{tenant: "ACME", ai: %{assistant: %{options: MockLLM.options(mock)}}}

    for agent <- [definition, built, decoded] do
      {:ok, server} = Jido.start_agent(jido, agent)
      signal = Jido.Signal.new!("case.inline", %{query: "Help"}, source: "/authoring")
      assert {:ok, result} = Server.call(server, signal, context: context, timeout: 10_000)
      assert result.state === %{reply: "Echoed", case_id: "case-17", jido_ai_config: %{}}
    end

    assert_done(mock)
    requests = MockLLM.report(mock).requests
    assert length(requests) == 6

    assert Enum.all?(requests, fn request ->
             Enum.any?(request.body["messages"], &(&1["role"] == "system" and &1["content"] == "Tenant ACME: Help"))
           end)

    assert Enum.count(requests, fn request ->
             Enum.any?(request.body["messages"], &(&1["role"] == "tool" and String.contains?(&1["content"], "hello")))
           end) == 3
  end

  test "unrouted profiles and disabled session streaming reject before provider work", %{jido: jido} do
    JidoAITest.Authoring.Compiler.require_file!(Corpus.fixture("helper_edges.exs"))
    module = JidoAITest.Authoring.Agents.Fixtures.HelperEdges
    mock = start_supervised!({MockLLM, script: []})
    {:ok, server} = Jido.start_agent(jido, module)
    before = Server.snapshot(server)
    context = %{ai: %{session: %{options: MockLLM.options(mock)}}}

    assert {:error, %Jido.AI.Error.Validation.Invalid{field: "profile"}} =
             apply(module, :ask, [server, "No", [profile: :unrouted]])

    assert {:error, %Jido.AI.Error.Validation.Invalid{field: "requests.streaming"}} =
             apply(module, :ask_stream, [server, "No", [profile: :session, context: context]])

    assert Server.snapshot(server) === before
    assert_done(mock)
  end

  test "multiple routes for one profile select the first declared route" do
    JidoAITest.Authoring.Compiler.require_file!(Corpus.fixture("helper_edges.exs"))
    module = JidoAITest.Authoring.Agents.Fixtures.HelperEdges
    # Selection itself has no I/O; compare the helper call boundary explicitly.
    Mimic.expect(Jido.AgentServer, :call, fn :route_probe, signal, _opts ->
      assert signal.type == "case.first"
      {:ok, %{state: %{reply: "First"}}}
    end)

    assert {:ok, "First"} = apply(module, :ask, [:route_probe, "Help", [profile: :assistant]])
  end

  test "invalid query through generated ask leaves state unchanged", %{jido: jido} do
    {spec, server, mock, context} = start_case(jido, :simple, [])
    before = Server.snapshot(server)
    assert {:error, _} = spec.module.ask(server, 42, context: context)
    assert Server.snapshot(server) === before
    assert_done(mock)
  end

  test "ask_stream preserves profile selection errors without starting model work", %{jido: jido} do
    {spec, server, mock, context} = start_case(jido, :multi, [])
    before = Server.snapshot(server)

    for opts <- [[context: context], [profile: :missing, context: context]] do
      assert {:error, expected} = spec.module.ask(server, "Help", opts)
      assert {:error, actual} = spec.module.ask_stream(server, "Help", opts)
      assert %Jido.AI.Error.Validation.Invalid{field: "profile"} = actual
      assert Exception.message(actual) == Exception.message(expected)
    end

    assert Server.snapshot(server) === before
    assert_done(mock)
  end

  test "ask_stream preserves busy admission errors and leaves the active request unchanged", %{jido: jido} do
    {spec, server, mock, context} = start_case(jido, :session, [{:wait, :stream_busy, {:text, "Done"}}])
    assert {:ok, request} = spec.module.ask(server, "First", context: context, request_id: "active-stream")
    assert_receive {:mock_llm_waiting, ^mock, :stream_busy, _}, 5_000
    before = Server.agent(server).state
    assert {:error, :busy} = spec.module.ask_stream(server, "Second", context: context, request_id: "refused-stream")
    assert Server.agent(server).state === before
    assert length(MockLLM.report(mock).requests) == 1
    assert :ok = MockLLM.release(mock, :stream_busy)
    assert {:ok, "Done"} = spec.module.await(request, timeout: 5_000)
    assert Map.keys(Server.agent(server).state.requests) == ["active-stream"]
    refute_received %{request_id: "refused-stream"}
    assert_done(mock)
  end

  defp assert_done(mock) do
    assert %{remaining: [], unexpected: [], waiting: []} = MockLLM.report(mock)
  end
end
