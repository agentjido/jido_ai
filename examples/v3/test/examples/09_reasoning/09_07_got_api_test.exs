defmodule JidoAI.Examples.GoTAPITest do
  use JidoAI.Examples.Case
  alias Jido.AI.Request
  alias Jido.AI.Reasoning.GraphOfThoughts, as: Method
  alias JidoAI.Examples.{GoT, GoTAPI}

  setup do
    saved = Application.fetch_env(:jido_ai, :model_aliases)
    Application.put_env(:jido_ai, :model_aliases, %{example: MockLLM.model()})

    on_exit(fn ->
      case saved do
        {:ok, value} -> Application.put_env(:jido_ai, :model_aliases, value)
        :error -> Application.delete_env(:jido_ai, :model_aliases)
      end
    end)

    :ok
  end

  defp profile(module) do
    {_, config} = Enum.find(module.agent().plugins, &(elem(&1, 0) == Jido.AI.Runtime.Plugin))
    config[:profiles].assistant
  end

  defp record(server, handle), do: Server.agent(server).state.requests[handle.id]

  test "public defaults and helper results use the shared graph runtime", %{jido: jido} do
    options = GoTAPI.Public.strategy_opts()
    assert options[:model] == :example and options[:max_nodes] == 20
    assert options[:max_depth] == 5 and options[:aggregation_strategy] == :synthesis
    assert GoTAPI.Public.description() == "GoT agent public_graph"
    assert profile(GoTAPI.Public).controls.max_iterations == 40
    assert profile(GoTAPI.Public).requests.steering == false
    assert profile(GoTAPI.Public).memory.history == nil
    {mock, context} = mock(GoT.script())
    assert {:ok, agent} = GoTAPI.Public.new()
    assert agent.state.last_prompt == "" and agent.state.last_result == ""
    server = start_agent(jido, agent)

    assert {:ok, "Combined conclusion"} =
             GoTAPI.Public.explore_sync(server, "Analyze", context: context)

    agent = Server.agent(server)
    assert agent.state.last_prompt == "Analyze" and agent.state.completed
    assert agent.state.last_result == "Combined conclusion"
    assert Method.method() == :graph_of_thoughts
    assert Method.get_result(agent) == "Combined conclusion"
    assert length(Method.get_nodes(agent)) == 4 and length(Method.get_edges(agent)) == 3
    assert Method.get_best_node(agent).content == "Combined conclusion"
    path = Method.get_solution_path(agent)
    nodes = Map.new(Method.get_nodes(agent), &{&1.id, &1})

    assert Enum.map(path, &nodes[&1].content) == [
             "Analyze",
             "First analysis",
             "Refined analysis",
             "Combined conclusion"
           ]

    assert_script_done(mock)
  end

  test "public request records retain separate graphs and reset pending convenience state", %{
    jido: jido
  } do
    {mock, context} =
      mock(
        GoT.script() ++
          [
            %{reply: {:wait, :next_graph, {:text, "Next thought"}}},
            %{reply: {:text, "Next refinement"}},
            %{reply: {:text, "Next conclusion"}}
          ]
      )

    server = start_agent(jido, GoTAPI.Public.new!())
    assert Method.get_result(Server.agent(server)) == nil
    assert Method.get_nodes(Server.agent(server)) == []
    assert {:ok, first} = GoTAPI.Public.explore(server, "First", context: context)
    assert {:ok, "Combined conclusion"} = GoTAPI.Public.await(first)
    first_nodes = Method.get_nodes(Server.agent(server), first.id)
    assert {:ok, next} = GoTAPI.Public.explore(server, "Next", context: context)
    assert_receive {:mock_llm_waiting, ^mock, :next_graph, _}, 2_000
    pending = Server.agent(server)
    assert pending.state.last_prompt == "Next" and pending.state.last_result == ""
    refute pending.state.completed
    assert Method.get_result(pending) == nil and Method.get_nodes(pending) == []
    assert Method.get_edges(pending) == [] and Method.get_solution_path(pending) == []
    assert Method.get_result(pending, first.id) == "Combined conclusion"
    assert Method.get_nodes(pending, first.id) == first_nodes
    assert :ok = MockLLM.release(mock, :next_graph)
    assert {:ok, "Next conclusion"} = GoTAPI.Public.await(next)
    assert record(server, next).meta.usage.total_tokens == 45
    assert Method.get_result(Server.agent(server)) == "Next conclusion"

    assert MapSet.disjoint?(
             MapSet.new(first_nodes, & &1.id),
             MapSet.new(Method.get_nodes(Server.agent(server)), & &1.id)
           )

    assert length(Enum.at(MockLLM.report(mock).requests, 3).body["messages"]) == 2
    assert_script_done(mock)
  end

  test "public failed graph inspection keeps the raw cause and printable error state", %{
    jido: jido
  } do
    {mock, context} = mock(Enum.take(GoT.script(), 2) ++ [%{reply: {:stream, [], "length"}}])
    server = start_agent(jido, GoTAPI.Public.new!())
    assert {:ok, handle} = GoTAPI.Public.explore(server, "Fail", context: context)

    assert {:error, {:failed, {:incomplete_response, :length}, result}} =
             GoTAPI.Public.await(handle)

    agent = Server.agent(server)
    assert Method.get_result(agent) == {:error, {:incomplete_response, :length}}
    assert length(Method.get_nodes(agent, handle.id)) == 3
    assert length(Method.get_edges(agent)) == 2
    assert Method.get_best_node(agent) == nil and Method.get_solution_path(agent) == []

    assert agent.state.completed and
             agent.state.last_result == "{:error, {:incomplete_response, :length}}"

    assert result.usage.total_tokens == 45
    assert record(server, handle).error == {:failed, {:incomplete_response, :length}, result}
    assert_script_done(mock)
  end

  test "old Strategy names remain loadable graph getters with no execution callbacks", %{
    jido: jido
  } do
    {mock, context} = mock(GoT.script())
    server = start_agent(jido, GoTAPI.Public.new!())
    assert {:ok, _} = GoTAPI.Public.explore_sync(server, "Inspect", context: context)
    agent = Server.agent(server)
    adapter = apply(Method, :strategy_module, [])
    assert Code.ensure_loaded?(adapter)

    for getter <- [:get_nodes, :get_edges, :get_result, :get_best_node, :get_solution_path] do
      assert apply(adapter, getter, [agent]) == apply(Method, getter, [agent])
    end

    for {name, arity} <- [
          init: 2,
          cmd: 3,
          snapshot: 2,
          action_spec: 1,
          signal_routes: 1,
          start_action: 0
        ] do
      refute function_exported?(adapter, name, arity)
    end

    assert Method.get_nodes(agent, "missing") == [] and Method.get_result(agent, "missing") == nil
    assert String.starts_with?(Method.generate_call_id(), "got_")
    assert Method.default_generation_prompt() == Method.Machine.default_generation_prompt()
    assert Method.default_connection_prompt() == Method.Machine.default_connection_prompt()
    assert Method.default_aggregation_prompt() == Method.Machine.default_aggregation_prompt()
    assert_script_done(mock)
  end

  test "custom public settings retain actual provider options and unscored result semantics", %{
    jido: jido
  } do
    {mock, context} = mock(Enum.take(GoT.script(), 2))
    server = start_agent(jido, GoTAPI.Custom.new!())
    assert GoTAPI.Custom.description() == "Custom graph search"
    options = GoTAPI.Custom.strategy_opts()
    assert options[:max_nodes] == 8 and options[:max_depth] == 2
    assert options[:aggregation_strategy] == :weighted
    assert options[:connection_prompt] == "Connect these facts"
    assert options[:aggregation_prompt] == "Summarize these facts"

    assert {:ok, "Refined analysis"} =
             GoTAPI.Custom.explore_sync(server, "Short", context: context)

    assert Method.get_best_node(Server.agent(server)) == nil
    assert Method.get_solution_path(Server.agent(server)) == []

    for wire <- MockLLM.report(mock).requests do
      assert hd(wire.body["messages"])["content"] == "Generate from these facts"
      assert wire.body["max_tokens"] == 90 and wire.body["temperature"] == 0.4
      refute wire.body["stream"]
    end

    assert_script_done(mock)
  end

  test "the public graph budget permits more than ten calls within the node limit", %{jido: jido} do
    script =
      Enum.flat_map(1..10, fn n ->
        [%{reply: {:text, "Thought #{n}"}}] ++
          if(rem(n, 2) == 0 and n < 10, do: [%{reply: {:text, "No new connections"}}], else: [])
      end)

    {mock, context} = mock(script)
    server = start_agent(jido, GoTAPI.Deep.new!())
    assert {:ok, handle} = GoTAPI.Deep.explore(server, "Deep", context: context)
    assert {:ok, "Thought 10"} = GoTAPI.Deep.await(handle)
    assert profile(GoTAPI.Deep).controls.max_iterations == 22
    assert record(server, handle).meta.model_calls == 14
    assert record(server, handle).meta.usage.total_tokens == 210
    assert length(Method.get_nodes(Server.agent(server))) == 11
    assert record(server, handle).meta.reasoning.graph.termination_reason == :max_nodes
    assert_script_done(mock)
  end

  test "public cancellation keeps its reason and completed call evidence before a fresh search",
       %{jido: jido} do
    {mock, context} =
      mock(
        [hd(GoT.script()), %{reply: {:stream, [{:wait, :cancel_graph}], "stop"}}] ++ GoT.script()
      )

    server = start_agent(jido, GoTAPI.Public.new!())
    assert {:ok, handle} = GoTAPI.Public.explore(server, "Cancel", context: context)
    assert_receive {:mock_llm_waiting, ^mock, :cancel_graph, provider}, 2_000
    monitor = Process.monitor(provider)
    assert {:error, :busy} = GoTAPI.Public.explore(server, "Busy", context: context)
    assert :ok = GoTAPI.Public.cancel(server, request_id: handle.id, reason: :changed_task)
    assert {:error, {:cancelled, :changed_task}} = GoTAPI.Public.await(handle)
    assert_receive {:DOWN, ^monitor, :process, ^provider, _}, 2_000
    assert record(server, handle).meta.usage.total_tokens == 15

    assert Method.get_result(Server.agent(server), handle.id) ==
             {:error, {:cancelled, :changed_task}}

    assert {:ok, "Combined conclusion"} =
             GoTAPI.Public.explore_sync(server, "Next", context: context)

    assert_script_done(mock)
  end

  test "busy rejection has the same request and stream result before and after a model call", %{
    jido: jido
  } do
    {mock, context} =
      mock([
        %{reply: {:wait, :before_model, {:text, "Thought"}}},
        %{reply: {:wait, :after_model, {:text, "Refinement"}}},
        %{reply: {:text, "Conclusion"}}
      ])

    server = start_agent(jido, GoTAPI.Public.new!())
    assert {:ok, handle} = GoTAPI.Public.explore(server, "Work", context: context)

    for tag <- [:before_model, :after_model] do
      assert_receive {:mock_llm_waiting, ^mock, ^tag, _}, 2_000
      id = "busy-#{tag}"

      assert {:error, :busy} =
               GoTAPI.Public.explore(server, "Busy",
                 context: context,
                 request_id: id,
                 stream_to: self()
               )

      assert_receive {:jido_ai_request_event,
                      %{request_id: ^id, kind: :request_failed, data: %{error: :busy}}}

      refute Map.has_key?(Server.agent(server).state.requests, id)
      assert :ok = MockLLM.release(mock, tag)
    end

    assert {:ok, "Conclusion"} = GoTAPI.Public.await(handle)
    assert_script_done(mock)
  end

  test "common Agent authoring can select GoT without a separate wrapper", %{jido: jido} do
    {mock, context} = mock([hd(GoT.script())])
    server = start_agent(jido, GoTAPI.Common.new!())
    assert {:ok, handle} = GoTAPI.Common.ask(server, "Simple", context: context)
    assert {:ok, "First analysis"} = GoTAPI.Common.await(handle)
    assert record(server, handle).method == Method.method()
    assert Method.get_result(Server.agent(server)) == "First analysis"
    assert_script_done(mock)
  end

  test "graph getters do not read actual results from another method", %{jido: jido} do
    {mock, context} = mock([%{reply: {:text, "answer: other"}}])
    server = start_agent(jido, JidoAI.Examples.AoT.Public.new!())
    assert {:ok, handle} = JidoAI.Examples.AoT.Public.explore(server, "Other", context: context)
    assert {:ok, _} = Request.await(handle)
    agent = Server.agent(server)
    assert Method.get_result(agent, handle.id) == nil and Method.get_result(agent) == nil
    assert Method.get_nodes(agent) == [] and Method.get_edges(agent) == []
    assert Method.get_best_node(agent) == nil and Method.get_solution_path(agent) == []
    assert_script_done(mock)
  end

  test "solution path inspection escapes a parent cycle and terminates when no path exists" do
    alias Method.Machine

    nodes =
      Map.new(~w(root a b best), fn id ->
        {id, %{id: id, content: id, score: nil, depth: 0, metadata: %{}}}
      end)

    graph = %{Machine.new() | root_id: "root", nodes: nodes}

    graph =
      Enum.reduce([{"root", "a"}, {"a", "b"}, {"b", "a"}, {"a", "best"}], graph, fn {a, b},
                                                                                    graph ->
        Machine.add_edge(graph, a, b, :connects)
      end)

    task = Task.async(fn -> Machine.trace_path(graph, "best") end)
    outcome = Task.yield(task, 100) || Task.shutdown(task, :brutal_kill)
    assert {:ok, ["root", "a", "best"]} = outcome
    disconnected = %{graph | edges: Enum.reject(graph.edges, &(&1.from == "root"))}
    assert Machine.trace_path(disconnected, "best") == []
  end
end
