defmodule JidoAI.Examples.GoTTest do
  use JidoAI.Examples.Case
  alias Jido.AI.{Authoring, Request, Session}
  alias Jido.AI.Reasoning.GraphOfThoughts.Machine
  alias JidoAI.Examples.GoT

  defp start(jido, changes \\ %{}) do
    assert {:ok, definition} = GoT.definition(changes)
    start_agent(jido, Jido.Agent.instantiate!(definition))
  end

  defp request(server, context, query \\ "Combine the analysis"),
    do:
      Request.create_and_send(server, query,
        signal_type: "ai.got.query",
        source: "/examples/got",
        context: context,
        stream_to: self()
      )

  defp record(server, handle), do: Server.agent(server).state.requests[handle.id]
  defp graph(server, handle), do: record(server, handle).meta.reasoning.graph

  defp events(handle),
    do: handle |> Request.Stream.events(stream_event_timeout_ms: 1_000) |> Enum.to_list()

  test "generation and synthesis use three real model calls and retain the graph", %{jido: jido} do
    {mock, context} = mock(GoT.script())
    server = start(jido)
    assert {:ok, handle} = request(server, context)
    assert {:ok, "Combined conclusion"} = Request.await(handle)
    machine = Machine.from_map(graph(server, handle))
    assert machine.status == "completed" and machine.termination_reason == :success
    assert map_size(machine.nodes) == 4
    assert Enum.frequencies_by(machine.edges, & &1.type) == %{generates: 2, aggregates: 1}
    assert Machine.find_best_leaf(machine).content == "Combined conclusion"
    assert record(server, handle).meta.usage.total_tokens == 45
    assert record(server, handle).meta.model_calls == 3
    assert record(server, handle).method == :graph_of_thoughts
    assert Server.agent(server).state.reply == "Combined conclusion"
    [first, second, aggregate] = MockLLM.report(mock).requests
    assert hd(first.body["messages"])["content"] == Machine.default_generation_prompt()
    assert List.last(second.body["messages"])["content"] =~ "First analysis"
    assert hd(aggregate.body["messages"])["content"] == Machine.default_aggregation_prompt()
    assert List.last(aggregate.body["messages"])["content"] =~ "Refined analysis"
    assert first.body["max_tokens"] == 1024 and first.body["temperature"] == 0.2
    assert_script_done(mock)
  end

  test "non-streaming requests retain native instructions and declared model options", %{
    jido: jido
  } do
    {mock, context} = mock(GoT.script())

    server =
      start(jido, %{
        instructions: "Use the supplied facts",
        requests: %{mode: :session, streaming: false},
        models: %{
          answer: %{model: MockLLM.model(), generation: [temperature: 0.4, max_tokens: 75]}
        }
      })

    assert {:ok, handle} = request(server, context)
    assert {:ok, "Combined conclusion"} = Request.await(handle)

    assert hd(hd(MockLLM.report(mock).requests).body["messages"])["content"] ==
             "Use the supplied facts"

    for wire <- MockLLM.report(mock).requests do
      refute wire.body["stream"]
      assert wire.body["temperature"] == 0.4 and wire.body["max_tokens"] == 75
    end

    assert_script_done(mock)
  end

  defp connect(body) do
    text = List.last(body["messages"])["content"]
    nodes = Regex.scan(~r/(got_node_[^:\s]+): ([^\n]*)/, text)
    [_, root, _] = Enum.find(nodes, &(Enum.at(&1, 2) == "Combine the analysis"))
    [_, second, _] = Enum.find(nodes, &(Enum.at(&1, 2) == "Refined analysis"))

    {:text,
     "CONNECTION: [#{root}] -> [#{second}] : shared premise\n" <>
       "CONNECTION: [missing] -> [#{second}] : invalid node"}
  end

  test "connections use actual node IDs and later generation keeps each ancestor once", %{
    jido: jido
  } do
    {mock, context} =
      mock(
        Enum.take(GoT.script(), 2) ++
          [
            %{reply: {:from_request, &connect/1}},
            %{reply: {:text, "Third analysis"}},
            %{reply: {:text, "Fourth analysis"}},
            %{reply: {:text, "Connected conclusion"}}
          ]
      )

    server =
      start(
        jido,
        GoT.options(%{
          min_nodes_for_aggregation: 5,
          max_depth: 6,
          generation_prompt: "Generate exactly",
          connection_prompt: "Connect exactly",
          aggregation_prompt: "Combine exactly"
        })
      )

    assert {:ok, handle} = request(server, context)
    assert {:ok, "Connected conclusion"} = Request.await(handle)
    machine = Machine.from_map(graph(server, handle))

    assert Enum.frequencies_by(machine.edges, & &1.type) == %{
             generates: 4,
             connects: 1,
             aggregates: 1
           }

    assert Enum.all?(
             machine.edges,
             &(Map.has_key?(machine.nodes, &1.from) and Map.has_key?(machine.nodes, &1.to))
           )

    assert record(server, handle).meta.usage.total_tokens == 90

    assert events(handle)
           |> Enum.filter(&(&1.kind == :llm_completed))
           |> Enum.map(& &1.data.reasoning_phase) ==
             [:generation, :generation, :connection, :generation, :generation, :aggregation]

    wires = MockLLM.report(mock).requests

    assert Enum.map(wires, &hd(&1.body["messages"])["content"]) ==
             [
               "Generate exactly",
               "Generate exactly",
               "Connect exactly",
               "Generate exactly",
               "Generate exactly",
               "Combine exactly"
             ]

    previous =
      Enum.at(wires, 3).body["messages"]
      |> List.last()
      |> Map.fetch!("content")
      |> String.split("Previous reasoning:\n")
      |> List.last()
      |> String.split("Current thought to expand:")
      |> hd()

    assert length(Regex.scan(~r/Combine the analysis/, previous)) == 1
    assert length(Regex.scan(~r/First analysis/, previous)) == 1
    fourth = Enum.find(Machine.get_nodes(machine), &(&1.content == "Fourth analysis"))
    ancestors = Machine.get_ancestors(machine, fourth.id)
    assert length(ancestors) == 4 and length(Enum.uniq(ancestors)) == 4
    assert_script_done(mock)
  end

  test "retained traversal handles a diamond disconnected node and cycle without duplicates" do
    machine =
      Enum.reduce(~w(a b c d x), Machine.new(), fn id, graph ->
        Machine.add_node(graph, %{id: id, content: id, score: nil, depth: 0, metadata: %{}})
      end)

    machine =
      Enum.reduce([{"a", "b"}, {"a", "c"}, {"b", "d"}, {"c", "d"}], machine, fn {a, b}, graph ->
        Machine.add_edge(graph, a, b, :generates)
      end)

    assert Enum.sort(Machine.get_ancestors(machine, "d")) == ~w(a b c)
    assert Enum.sort(Machine.get_descendants(machine, "a")) == ~w(b c d)
    assert Machine.get_ancestors(machine, "a") == []
    assert Machine.get_descendants(machine, "d") == []
    assert Machine.get_ancestors(machine, "x") == []
    refute Machine.has_cycle?(machine)
    cycle = Machine.add_edge(machine, "d", "a", :connects)
    assert Machine.has_cycle?(cycle)
    assert Enum.sort(Machine.get_ancestors(cycle, "d")) == ~w(a b c d)
    assert Enum.sort(Machine.get_descendants(cycle, "a")) == ~w(a b c d)
    assert Machine.from_map(Machine.to_map(cycle)) == cycle
  end

  test "retained Machine adds missing per-call totals and merges nested usage" do
    machine = Machine.new()
    {machine, _} = Machine.update(machine, {:start, "Count", "call"})

    machine =
      Enum.reduce([2, 3], machine, fn input, machine ->
        usage = %{
          input_tokens: input,
          output_tokens: 1,
          input_tokens_details: %{cached_tokens: 1}
        }

        {machine, _} =
          Machine.update(
            machine,
            {:llm_result, machine.current_call_id, {:ok, %{text: "Thought", usage: usage}}}
          )

        machine
      end)

    assert machine.usage == %{
             input_tokens: 5,
             output_tokens: 2,
             total_tokens: 7,
             input_tokens_details: %{cached_tokens: 2}
           }
  end

  for {mode, instruction} <- [synthesis: "synthesizing", voting: "vote", weighted: "weighted"] do
    test "#{mode} preserves method settings through native request execution", %{jido: jido} do
      {mock, context} = mock(GoT.script())
      server = start(jido, GoT.options(%{aggregation_strategy: unquote(mode)}))
      assert {:ok, handle} = request(server, context)
      assert {:ok, "Combined conclusion"} = Request.await(handle)
      assert graph(server, handle).aggregation_strategy == unquote(mode)

      [_, _, aggregate] = MockLLM.report(mock).requests
      assert hd(aggregate.body["messages"])["content"] =~ unquote(instruction)

      assert_script_done(mock)
    end
  end

  test "the retained Machine still emits its legacy lifecycle telemetry" do
    id = "got_machine_#{System.unique_integer([:positive])}"
    names = for phase <- [:start, :complete, :error], do: [:jido, :ai, :got, phase]
    :ok = :telemetry.attach_many(id, names, &JidoAI.Examples.Telemetry.handle/4, self())
    on_exit(fn -> :telemetry.detach(id) end)
    {machine, _} = Machine.update(Machine.new(max_depth: 1), {:start, "Complete", "legacy"})

    {completed, _} =
      Machine.update(
        machine,
        {:llm_result, "legacy", {:ok, %{text: "Done", usage: %{input_tokens: 2, output_tokens: 1}}}}
      )

    assert completed.result == "Done"
    assert_receive {:linear_telemetry, [:jido, :ai, :got, :start], _, %{prompt_length: 8}}

    assert_receive {:linear_telemetry, [:jido, :ai, :got, :complete], _,
                    %{usage: %{total_tokens: 3}, termination_reason: :max_depth}}

    {failed, _} = Machine.update(machine, {:error, :model_failed})
    assert failed.result == {:error, :model_failed}
    assert_receive {:linear_telemetry, [:jido, :ai, :got, :error], _, %{reason: :model_failed}}
  end

  for {setting, value, reason} <- [{:max_depth, 1, :max_depth}, {:max_nodes, 2, :max_nodes}] do
    test "#{setting} stops generation before another model call", %{jido: jido} do
      {mock, context} = mock([hd(GoT.script())])
      server = start(jido, GoT.options(%{unquote(setting) => unquote(value)}))
      assert {:ok, handle} = request(server, context)
      assert {:ok, "First analysis"} = Request.await(handle)
      assert graph(server, handle).termination_reason == unquote(reason)
      assert map_size(graph(server, handle).nodes) == 2
      assert_script_done(mock)
    end
  end

  test "a root-only node budget fails before a provider call", %{jido: jido} do
    {mock, context} = mock([])
    server = start(jido, GoT.options(%{max_nodes: 1}))
    assert {:ok, handle} = request(server, context)
    assert {:error, {:failed, :max_nodes, result}} = Request.await(handle)
    assert map_size(result.graph.nodes) == 1 and result.usage == %{}
    assert_script_done(mock)
  end

  test "invalid options tools steering typed results and rich queries fail before provider work",
       %{jido: jido} do
    {mock, context} = mock([])

    for value <- [
          %{max_nodes: 0},
          %{max_depth: -1},
          %{min_nodes_for_aggregation: "3"},
          %{aggregation_strategy: :unknown},
          %{generation_prompt: 1},
          %{other: true}
        ] do
      assert {:error, _} = GoT.definition(GoT.options(value))
    end

    for change <- [
          %{tools: [%{name: "tree_work", target: JidoAI.Examples.ToT.Work}]},
          %{requests: %{mode: :session, steering: true}},
          %{result: %{schema: Zoi.string(), into: :reply}}
        ] do
      assert {:error, _} = GoT.definition(change)
    end

    server = start(jido)
    assert {:ok, handle} = request(server, context, [ReqLLM.Message.ContentPart.text("Rich")])
    assert {:error, _} = Request.await(handle)
    assert Server.agent(server).state.reply == nil
    assert_script_done(mock)
  end

  test "a transformer cannot enable GoT tools and unsolicited tool work fails", %{jido: jido} do
    {mock, context} =
      mock([
        hd(GoT.script()),
        %{reply: {:tools, [%{id: "unexpected", name: "tree_work", arguments: %{n: 1}}]}}
      ])

    server =
      start(jido, %{
        reasoning: Map.put(GoT.source().reasoning, :request_transformer, JidoAI.Examples.ToT.Transform)
      })

    assert {:ok, handle} = request(server, context)

    assert {:error, {:failed, {:unexpected_tool_calls, :graph_of_thoughts}, result}} =
             Request.await(handle)

    assert map_size(result.graph.nodes) == 2 and result.usage.total_tokens == 30
    refute Enum.any?(events(handle), &(&1.kind == :tool_started))

    for wire <- MockLLM.report(mock).requests do
      refute Map.has_key?(wire.body, "tools")
      refute Map.has_key?(wire.body, "tool_choice")
    end

    assert_script_done(mock)
  end

  test "an empty limited aggregation fails with its graph and permits a later request", %{
    jido: jido
  } do
    {mock, context} =
      mock(Enum.take(GoT.script(), 2) ++ [%{reply: {:stream, [], "length"}}] ++ GoT.script())

    server = start(jido)
    assert {:ok, handle} = request(server, context)
    assert {:error, {:failed, {:incomplete_response, :length}, result}} = Request.await(handle)
    assert map_size(result.graph.nodes) == 3 and result.usage.total_tokens == 45
    assert result.diagnostics.cause == {:incomplete_response, :length}
    assert Server.agent(server).state.reply == nil
    assert List.last(events(handle)).kind == :request_failed
    assert {:ok, next} = request(server, context)
    assert {:ok, "Combined conclusion"} = Request.await(next)
    assert_script_done(mock)
  end

  test "output control failure retains the completed graph without a domain write", %{jido: jido} do
    {mock, context} = mock(GoT.script())
    server = start(jido)
    assert {:ok, handle} = request(server, Map.put(context, :reject, :unapproved))
    assert {:error, {:failed, :unapproved, result}} = Request.await(handle)
    assert result.result == "Combined conclusion" and map_size(result.graph.nodes) == 4
    assert result.usage.total_tokens == 45 and Server.agent(server).state.reply == nil
    assert_script_done(mock)
  end

  test "the common model-call budget stops before a new phase and retains prior work", %{
    jido: jido
  } do
    {mock, context} = mock(Enum.take(GoT.script(), 2))
    server = start(jido, %{controls: %{GoT.source().controls | max_model_calls: 2}})
    assert {:ok, handle} = request(server, context)
    assert {:error, {:failed, reason, result}} = Request.await(handle)
    assert inspect(reason) =~ "limit"
    assert map_size(result.graph.nodes) == 3 and result.usage.total_tokens == 30
    assert Server.agent(server).state.reply == nil
    assert_script_done(mock)
  end

  test "cancellation rejects busy input stops the transport and allows another graph", %{
    jido: jido
  } do
    {mock, context} = mock([%{reply: {:stream, [{:wait, :held_graph}], "stop"}}] ++ GoT.script())
    server = start(jido)
    assert {:ok, handle} = request(server, context)
    assert_receive {:mock_llm_waiting, ^mock, :held_graph, provider}, 2_000
    monitor = Process.monitor(provider)

    assert {:error, :busy} = request(server, context)

    assert :ok = Session.cancel(handle, reason: :changed_task)
    assert {:error, {:cancelled, :changed_task}} = Request.await(handle)
    assert_receive {:DOWN, ^monitor, :process, ^provider, _}, 2_000
    assert {:ok, next} = request(server, context)
    assert {:ok, "Combined conclusion"} = Request.await(next)
    assert_script_done(mock)
  end

  test "the total deadline closes active graph transport", %{jido: jido} do
    {mock, context} = mock([%{reply: {:stream, [{:wait, :graph_deadline}], "stop"}}])
    server = start(jido, %{controls: %{GoT.source().controls | timeout: 300}})
    assert {:ok, handle} = request(server, context)
    assert_receive {:mock_llm_waiting, ^mock, :graph_deadline, provider}, 2_000
    monitor = Process.monitor(provider)
    assert {:error, _} = Request.await(handle, timeout: 3_000)
    assert_receive {:DOWN, ^monitor, :process, ^provider, _}, 2_000
    assert record(server, handle).status == :failed and Server.agent(server).state.reply == nil
    assert_script_done(mock)
  end

  test "owner restart interrupts old graph work and permits a new request", %{jido: jido} do
    {mock, context} = mock([%{reply: {:stream, [{:wait, :lost_graph}], "stop"}}] ++ GoT.script())
    server = start(jido)
    assert {:ok, handle} = request(server, context)
    assert_receive {:mock_llm_waiting, ^mock, :lost_graph, provider}, 2_000
    monitor = Process.monitor(provider)
    Process.exit(Server.children(server)[{:plugin, Session.Plugin}].pid, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^provider, _}, 2_000
    assert {:error, :stream_interrupted} = Request.await(handle)
    assert {:ok, next} = request(server, context)
    assert {:ok, "Combined conclusion"} = Request.await(next)
    assert_script_done(mock)
  end

  test "phase events project to Signals and telemetry without duplicate Machine events", %{
    jido: jido
  } do
    id = "got_#{System.unique_integer([:positive])}"

    names = [
      [:jido, :ai, :llm, :complete],
      [:jido, :ai, :got, :start],
      [:jido, :ai, :got, :complete]
    ]

    :ok = :telemetry.attach_many(id, names, &JidoAI.Examples.Telemetry.handle/4, self())
    on_exit(fn -> :telemetry.detach(id) end)
    {mock, context} = mock(GoT.script())
    server = start(jido)
    assert {:ok, handle} = request(server, context)
    assert {:ok, _} = Request.await(handle)
    events = events(handle)
    completed = Enum.filter(events, &(&1.kind == :llm_completed))

    assert Enum.map(completed, & &1.data.reasoning_phase) == [
             :generation,
             :generation,
             :aggregation
           ]

    assert length(Enum.uniq_by(completed, & &1.llm_call_id)) == 3
    assert length(Enum.uniq_by(completed, & &1.data.phase_call_id)) == 3

    for event <- completed do
      assert {:ok, [signal, _]} = Jido.AI.Signal.from_event(event)
      assert signal.data.metadata.reasoning_phase == event.data.reasoning_phase
      call = event.llm_call_id

      assert_receive {:linear_telemetry, [:jido, :ai, :llm, :complete], _, %{llm_call_id: ^call, strategy: :got}},
                     2_000
    end

    refute_receive {:linear_telemetry, [:jido, :ai, :got, _], _, _}, 20
    assert List.last(events).kind == :request_completed
    assert_script_done(mock)
  end

  test "DSL data Builder source JSON direct Flow and ordinary turns use the same graph contract",
       %{jido: jido} do
    {mock, context} = mock(List.duplicate(GoT.script(), 6) |> List.flatten())
    source = GoT.source()
    assert {:ok, definition} = GoT.definition()
    assert definition == GoT.Agent.definition()
    attrs = definition |> Map.from_struct() |> Map.drop([:id, :state])
    assert {:ok, built} = attrs |> Jido.Agent.Builder.new() |> Jido.Agent.Builder.build()

    registry =
      source
      |> Map.put(:routes, [])
      |> atoms()
      |> Kernel.++(profile_atoms(source))
      |> Enum.uniq()
      |> Map.new(&{"atoms/#{&1}", {:atom, &1}})
      |> Map.put("models/answer", {:value, source.models.answer.model})

    assert {:ok, document} = Authoring.Codec.encode([source], registry)

    assert {:ok, decoded} =
             Authoring.Codec.decode(GoT.base(), Jason.decode!(Jason.encode!(document)), registry)

    assert decoded == built and built == definition

    for value <- [GoT.Agent.definition(), definition, built, decoded] do
      server = start_agent(jido, Jido.Agent.instantiate!(value))
      assert {:ok, handle} = request(server, context)
      assert {:ok, "Combined conclusion"} = Request.await(handle)
      assert map_size(graph(server, handle).nodes) == 4
    end

    assert {:ok, profile} = Jido.AI.Profile.new(source)
    assert {:ok, flow} = Authoring.reasoning_flow(profile)

    direct_context =
      Map.merge(context, %{agent_state: %{reply: nil}, jido_ai_profiles: %{assistant: profile}})

    assert {:ok, %{result: "Combined conclusion", meta: meta}} =
             Jido.Exec.run(flow, %{query: "Combine the analysis"}, direct_context)

    assert map_size(meta.reasoning.graph.nodes) == 4
    server = start(jido, %{requests: %{mode: :turn}})

    signal =
      Jido.Signal.new!("ai.got.query", %{query: "Combine the analysis"}, source: "/examples/got")

    assert {:ok, agent} = Server.call(server, signal, context: context, timeout: 5_000)
    assert agent.state.reply == "Combined conclusion"
    assert_script_done(mock)
  end

  defp atoms(value) when is_atom(value), do: [value]
  defp atoms(value) when is_list(value), do: Enum.flat_map(value, &atoms/1)
  defp atoms(value) when is_tuple(value), do: value |> Tuple.to_list() |> atoms()
  defp atoms(%_{}), do: []

  defp atoms(value) when is_map(value),
    do: Enum.flat_map(value, fn {k, v} -> atoms(k) ++ atoms(v) end)

  defp atoms(_), do: []
end
