defmodule JidoAI.Examples.StreamActivityTest do
  use JidoAI.Examples.Case
  alias Jido.AI.{Authoring, Request, Session}
  alias JidoAI.Examples.StreamActivity.{Agent, DefaultAgent, NativeAgent}

  setup do
    old = Application.fetch_env(:jido_ai, :model_aliases)
    Application.put_env(:jido_ai, :model_aliases, %{example: MockLLM.model()})

    on_exit(fn ->
      case old do
        {:ok, value} -> Application.put_env(:jido_ai, :model_aliases, value)
        :error -> Application.delete_env(:jido_ai, :model_aliases)
      end
    end)

    :ok
  end

  defp tool(id, n), do: %{id: id, name: "stream_probe", arguments: %{n: n}}
  defp counter(ctx), do: Map.put(ctx, :counter, start_supervised!({Elixir.Agent, fn -> %{} end}))
  defp tools_reply(calls), do: %{reply: {:tools, calls}}
  defp done, do: %{reply: {:text, "Done"}}

  defp events(request),
    do: request |> Request.Stream.events(stream_event_timeout_ms: 1_000) |> Enum.to_list()

  defp ordered(events, id) do
    assert Enum.all?(events, &(&1.request_id == id))
    assert Enum.map(events, & &1.seq) == Enum.to_list(1..length(events))
    assert Enum.count(events, &Request.Stream.terminal_kind?(&1.kind)) == 1

    Enum.reduce(events, MapSet.new(), fn event, active ->
      case event.kind do
        :tool_started ->
          MapSet.put(active, event.tool_call_id)

        :tool_completed ->
          MapSet.delete(active, event.tool_call_id)

        :keepalive ->
          assert MapSet.size(active) > 0
          assert event.data.source == :tool_execution
          active

        _ ->
          active
      end
    end)
  end

  @tag history_case: "HIST-07/keepalive-layers"
  test "public keepalives preserve runtime and enumerable idle limits during held tool work", %{
    jido: jido
  } do
    {mock, ctx} = mock([tools_reply([tool("held", 1)]), done()])
    server = start_agent(jido, Agent.new!())

    assert {:ok, %{request: request, events: stream}} =
             Agent.ask_stream(server, "Work", context: counter(ctx), stream_event_timeout_ms: 150)

    assert_receive {:activity_tool, 1, 1, worker}, 2_000
    monitor = Process.monitor(worker)
    started = System.monotonic_time(:millisecond)
    Process.send_after(worker, {:release, :ok}, 650)
    received = Enum.to_list(stream)
    assert System.monotonic_time(:millisecond) - started >= 600
    assert_receive {:DOWN, ^monitor, :process, ^worker, _}, 2_000
    assert Enum.count(received, &(&1.kind == :keepalive)) >= 8
    assert List.last(received).kind == :request_completed
    assert {:ok, "Done"} = Agent.await(request)
    assert [%{status: :ok}] = Server.agent(server).state.requests[request.id].meta.tool_results
    ordered(received, request.id)
    assert :ok = Jido.Action.validate_static_data(Server.agent(server).state)
    assert_script_done(mock)
  end

  test "explicit zero disables an enabled heartbeat for one request without consumer cancellation",
       %{jido: jido} do
    {mock, ctx} =
      mock([tools_reply([tool("off", 1)]), done(), tools_reply([tool("on", 2)]), done()])

    ctx = counter(ctx)
    server = start_agent(jido, Agent.new!())

    assert {:ok, %{request: first, events: stream}} =
             Agent.ask_stream(server, "Work",
               context: ctx,
               tool_heartbeat_ms: 0,
               stream_timeout_ms: 1_000,
               stream_event_timeout_ms: 100
             )

    assert_receive {:activity_tool, 1, 1, worker}, 2_000
    received = Enum.to_list(stream)
    refute Enum.any?(received, &(&1.kind == :keepalive or Request.Stream.terminal_kind?(&1.kind)))
    assert Server.agent(server).state.requests[first.id].status == :pending
    send(worker, {:release, :ok})
    assert {:ok, "Done"} = Agent.await(first)

    assert {:ok, next} =
             Agent.ask(server, "Next",
               context: Map.put(ctx, :release_after, 180),
               stream_to: self()
             )

    assert {:ok, "Done"} = Agent.await(next)
    assert Enum.any?(events(next), &(&1.kind == :keepalive))
    assert_script_done(mock)
  end

  test "invalid heartbeat overrides preserve defaults through ask and ask_sync", %{jido: jido} do
    {mock, ctx} =
      mock(Enum.flat_map(1..3, fn n -> [tools_reply([tool("option-#{n}", n)]), done()] end))

    ctx = counter(ctx) |> Map.put(:release_after, 180)
    server = start_agent(jido, Agent.new!())

    for {value, n} <- Enum.with_index([nil, -1, "bad"], 1) do
      id = "override-#{n}"

      assert {:ok, "Done"} =
               Agent.ask_sync(server, "Work",
                 context: ctx,
                 tool_heartbeat_ms: value,
                 stream_receive_timeout_ms: 300,
                 request_id: id,
                 stream_to: self()
               )

      request = Request.Handle.new(id, server, "Work")
      assert Enum.any?(events(request), &(&1.kind == :keepalive))
    end

    assert_script_done(mock)
  end

  test "the default emits no heartbeat and zero idle override derives its runtime limit", %{
    jido: jido
  } do
    {mock, ctx} = mock([tools_reply([tool("default", 1)]), done()])
    server = start_agent(jido, DefaultAgent.new!())

    assert {:ok, request} =
             DefaultAgent.ask(server, "Work",
               context: counter(ctx) |> Map.put(:release_after, 180),
               stream_to: self(),
               stream_timeout_ms: 0
             )

    assert {:ok, "Done"} = DefaultAgent.await(request)
    refute Enum.any?(events(request), &(&1.kind == :keepalive))
    assert_script_done(mock)
  end

  test "runtime idle timeout kills held tool work when heartbeat is disabled", %{jido: jido} do
    {mock, ctx} = mock([tools_reply([tool("idle", 1)])])
    server = start_agent(jido, Agent.new!())

    assert {:ok, request} =
             Agent.ask(server, "Work",
               context: counter(ctx),
               stream_to: self(),
               tool_heartbeat_ms: 0,
               stream_timeout_ms: 150
             )

    assert_receive {:activity_tool, 1, 1, worker}, 2_000
    monitor = Process.monitor(worker)
    assert {:error, :stream_timeout} = Agent.await(request)
    assert_receive {:DOWN, ^monitor, :process, ^worker, _}, 2_000
    received = events(request)
    assert List.last(received).kind == :request_failed
    assert List.last(received).data.error_type == :stream_timeout
    refute Enum.any?(received, &(&1.kind == :keepalive))
    ordered(received, request.id)
    assert_script_done(mock)
  end

  test "heartbeat cannot keep a silent provider alive outside tool execution", %{jido: jido} do
    {mock, ctx} = mock([%{reply: {:wait, :silent, {:text, "Too late"}}}])
    server = start_agent(jido, Agent.new!())
    assert {:ok, request} = Agent.ask(server, "Work", context: counter(ctx), stream_to: self())
    assert_receive {:mock_llm_waiting, ^mock, :silent, worker}, 2_000
    monitor = Process.monitor(worker)
    assert {:error, :stream_timeout} = Agent.await(request)
    assert_receive {:DOWN, ^monitor, :process, ^worker, _}, 2_000
    refute Enum.any?(events(request), &(&1.kind == :keepalive))
    eventually(fn -> MockLLM.report(mock).waiting == [] end)
    assert_script_done(mock)
  end

  test "provider tool-argument fragments reset runtime idle without public keepalives", %{
    jido: jido
  } do
    fragments = ["{\"n\":", " ", " ", " ", "1", "}"]

    deltas =
      Enum.flat_map(Enum.with_index(fragments), fn {fragment, n} ->
        call = %{index: 0, function: %{arguments: fragment}}

        call =
          if n == 0,
            do:
              Map.merge(call, %{
                id: "fragments",
                type: "function",
                function: %{name: "stream_probe", arguments: fragment}
              }),
            else: call

        [%{tool_calls: [call]}, {:wait, {:fragment, n}}]
      end)

    {mock, ctx} = mock([%{reply: {:stream, deltas, "tool_calls"}}, done()])
    server = start_agent(jido, Agent.new!())
    started = System.monotonic_time(:millisecond)
    assert {:ok, request} = Agent.ask(server, "Work", context: counter(ctx), stream_to: self())

    for n <- 0..5 do
      assert_receive {:mock_llm_waiting, ^mock, {:fragment, ^n}, _}, 2_000
      Process.sleep(120)
      assert :ok = MockLLM.release(mock, {:fragment, n})
    end

    assert_receive {:activity_tool, 1, 1, worker}, 2_000
    send(worker, {:release, :ok})
    assert {:ok, "Done"} = Agent.await(request)
    assert System.monotonic_time(:millisecond) - started >= 700
    received = events(request)
    before_tool = Enum.take_while(received, &(&1.kind != :tool_started))
    refute Enum.any?(before_tool, &(&1.kind == :keepalive))
    ordered(received, request.id)
    assert_script_done(mock)
  end

  test "cancellation removes timers and stops the real tool before a later request", %{jido: jido} do
    {mock, ctx} = mock([tools_reply([tool("cancel", 1)]), done()])
    server = start_agent(jido, Agent.new!())
    assert {:ok, request} = Agent.ask(server, "Work", context: counter(ctx), stream_to: self())
    assert_receive {:activity_tool, 1, 1, worker}, 2_000
    monitor = Process.monitor(worker)
    owner = runtime(server)
    activity = :sys.get_state(owner).jobs[request.id].activity
    assert :ok = Session.cancel(request)
    assert {:error, :cancelled} = Agent.await(request)
    assert_receive {:DOWN, ^monitor, :process, ^worker, _}, 2_000
    assert Process.read_timer(activity.idle.timer) == false
    assert Process.read_timer(activity.heartbeat.timer) == false
    received = events(request)
    ordered(received, request.id)
    assert {:ok, next} = Agent.ask(server, "Next", context: ctx, stream_to: self())
    assert {:ok, "Done"} = Agent.await(next)
    refute Enum.any?(events(next), &(&1.kind == :keepalive))
    id = request.id
    refute_receive {:jido_ai_request_event, %{request_id: ^id}}, 80
    assert_script_done(mock)
  end

  defp runtime(server), do: Server.children(server)[{:plugin, Session.Plugin}].pid

  defp source do
    {_, options} =
      Enum.find(NativeAgent.definition().plugins, &(elem(&1, 0) == Jido.AI.Runtime.Plugin))

    Map.from_struct(options[:profiles].assistant)
  end

  defp base,
    do: %{
      name: "native_stream_activity_example",
      module: NativeAgent,
      vsn: NativeAgent.vsn(),
      schema: NativeAgent.domain_schema(),
      routes: [{"ai.ask", Authoring.ai(:assistant)}]
    }

  defp native(jido, changes \\ %{}) do
    assert {:ok, definition} = Authoring.lower(base(), [Map.merge(source(), changes)])
    start_agent(jido, Jido.Agent.instantiate!(definition))
  end

  defp request(server, ctx),
    do:
      Request.create_and_send(server, "Work",
        signal_type: "ai.ask",
        source: "/examples/activity",
        context: ctx,
        stream_to: self()
      )

  test "idle aliases and invalid overrides retain the effective request setting", %{jido: jido} do
    options = [
      {[stream_timeout_ms: 0], 62_000},
      {[stream_receive_timeout_ms: 800], 800},
      {[stream_timeout_ms: 900, stream_receive_timeout_ms: 1], 900},
      {[stream_timeout_ms: -1], 300},
      {[stream_timeout_ms: "bad"], 300}
    ]

    {mock, ctx} =
      mock(Enum.flat_map(1..5, fn n -> [tools_reply([tool("idle-option-#{n}", n)]), done()] end))

    ctx = counter(ctx)
    server = start_agent(jido, Agent.new!())

    for {{opts, expected}, n} <- Enum.with_index(options, 1) do
      assert {:ok, request} =
               Agent.ask(server, "Work", Keyword.merge(opts, context: ctx, stream_to: self()))

      assert_receive {:activity_tool, ^n, 1, worker}, 2_000
      assert :sys.get_state(runtime(server)).jobs[request.id].activity.idle_ms == expected
      send(worker, {:release, :ok})
      assert {:ok, "Done"} = Agent.await(request)
      assert [%{status: :ok}] = Server.agent(server).state.requests[request.id].meta.tool_results
    end

    assert_script_done(mock)
  end

  @tag history_case: "HIST-07/keepalive-order"
  test "one emitter preserves sequence across parallel tools retries multiple rounds and injection",
       %{jido: jido} do
    {mock, ctx} =
      mock([
        tools_reply([tool("one", 1), tool("two", 2)]),
        tools_reply([tool("three", 3)]),
        done()
      ])

    ctx = counter(ctx) |> Map.merge(%{retry: true, release_after: 350})
    server = native(jido)
    assert {:ok, request} = request(server, ctx)
    assert_receive {:activity_tool, 1, 1, _}, 2_000

    assert {:ok, %{status: :queued}} =
             Session.inject(server, "Additional case facts", expected_request_id: request.id)

    assert {:ok, "Done"} = Request.await(request)
    received = events(request)
    ordered(received, request.id)
    assert Enum.count(received, &(&1.kind == :keepalive)) >= 10
    assert Enum.any?(received, &(&1.kind == :input_injected))
    assert Enum.count(received, &(&1.kind == :llm_started)) == 3
    results = Server.agent(server).state.requests[request.id].meta.tool_results
    assert length(results) == 3
    assert Enum.all?(results, &(&1.status == :ok and &1.attempts == 2))
    assert_script_done(mock)
  end

  for mode <- [:failure, :attempt_timeout] do
    test "#{mode} stops tool heartbeat before a later model idle timeout", %{jido: jido} do
      {mock, ctx} =
        mock([
          tools_reply([tool("failed", 1)]),
          %{reply: {:wait, :later_model, {:text, "Too late"}}}
        ])

      tools = Enum.map(source().tools, &Map.put(&1, :timeout, 180))
      server = native(jido, %{tools: tools})
      assert {:ok, request} = request(server, counter(ctx))
      assert_receive {:activity_tool, 1, 1, worker}, 2_000
      monitor = Process.monitor(worker)
      owner = runtime(server)
      activity = :sys.get_state(owner).jobs[request.id].activity
      if unquote(mode) == :failure, do: Process.send_after(worker, {:release, :error}, 80)
      assert_receive {:DOWN, ^monitor, :process, ^worker, _}, 2_000
      assert_receive {:mock_llm_waiting, ^mock, :later_model, provider}, 2_000
      provider_monitor = Process.monitor(provider)
      assert Process.read_timer(activity.heartbeat.timer) == false
      assert :sys.get_state(owner).jobs[request.id].activity.heartbeat == nil
      assert {:error, :stream_timeout} = Request.await(request)
      assert_receive {:DOWN, ^provider_monitor, :process, ^provider, _}, 2_000
      received = events(request)
      ordered(received, request.id)
      assert Enum.any?(received, &(&1.kind == :keepalive))
      later = Enum.drop_while(received, &(&1.kind != :tool_completed))
      refute Enum.any?(later, &(&1.kind == :keepalive))

      assert [%{status: :error, attempts: 1}] =
               Server.agent(server).state.requests[request.id].meta.tool_results

      eventually(fn -> MockLLM.report(mock).waiting == [] end)
      assert_script_done(mock)
    end
  end

  test "heartbeats do not extend the total request deadline", %{jido: jido} do
    {mock, ctx} = mock([tools_reply([tool("deadline", 1)])])
    server = native(jido, %{controls: Map.put(source().controls, :timeout, 500)})
    assert {:ok, request} = request(server, counter(ctx))
    assert_receive {:activity_tool, 1, 1, worker}, 2_000
    monitor = Process.monitor(worker)
    owner = runtime(server)
    activity = :sys.get_state(owner).jobs[request.id].activity
    assert {:error, reason} = Request.await(request)
    refute reason == :stream_timeout
    assert_receive {:DOWN, ^monitor, :process, ^worker, _}, 2_000
    assert Process.read_timer(activity.idle.timer) == false
    assert Process.read_timer(activity.heartbeat.timer) == false
    received = events(request)
    assert Enum.any?(received, &(&1.kind == :keepalive))
    ordered(received, request.id)
    assert_script_done(mock)
  end

  test "owner failure stops timers and tool work while recovery interrupts the stored request", %{
    jido: jido
  } do
    {mock, ctx} = mock([tools_reply([tool("crash", 1)]), done()])
    server = start_agent(jido, Agent.new!())
    assert {:ok, request} = Agent.ask(server, "Work", context: counter(ctx), stream_to: self())
    assert_receive {:activity_tool, 1, 1, worker}, 2_000
    tool_monitor = Process.monitor(worker)
    owner = runtime(server)
    owner_monitor = Process.monitor(owner)
    activity = :sys.get_state(owner).jobs[request.id].activity
    Process.exit(owner, :kill)
    assert_receive {:DOWN, ^owner_monitor, :process, ^owner, _}, 2_000
    assert_receive {:DOWN, ^tool_monitor, :process, ^worker, _}, 2_000
    assert Process.read_timer(activity.idle.timer) == false
    assert Process.read_timer(activity.heartbeat.timer) == false
    assert {:error, :stream_interrupted} = Agent.await(request)
    assert runtime(server) != owner
    # The old sink is transient. Recovery does not claim terminal-event replay.
    old_events = request |> Request.Stream.events(stream_event_timeout_ms: 80) |> Enum.to_list()
    refute Enum.any?(old_events, &Request.Stream.terminal_kind?(&1.kind))
    assert {:ok, next} = Agent.ask(server, "Next", context: ctx, stream_to: self())
    assert {:ok, "Done"} = Agent.await(next)
    refute Enum.any?(events(next), &(&1.kind == :keepalive))
    assert_script_done(mock)
  end

  test "DSL data Builder and source JSON execute the same idle and heartbeat policy", %{
    jido: jido
  } do
    source = source()
    assert source.requests.idle_timeout == 300
    assert source.requests.tool_heartbeat == 25
    assert {:ok, definition} = Authoring.lower(base(), [source])
    assert definition == NativeAgent.definition()
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
             Authoring.Codec.decode(base(), Jason.decode!(Jason.encode!(document)), registry)

    assert built == definition
    assert decoded == definition

    {mock, ctx} =
      mock(Enum.flat_map(1..4, fn n -> [tools_reply([tool("format-#{n}", n)]), done()] end))

    ctx = counter(ctx) |> Map.put(:release_after, 450)

    for definition <- [NativeAgent.definition(), definition, built, decoded] do
      server = start_agent(jido, Jido.Agent.instantiate!(definition))
      assert {:ok, request} = request(server, ctx)
      assert {:ok, "Done"} = Request.await(request)
      assert [%{status: :ok}] = Server.agent(server).state.requests[request.id].meta.tool_results
      received = events(request)
      assert Enum.count(received, &(&1.kind == :keepalive)) >= 5
      ordered(received, request.id)
    end

    assert_script_done(mock)
  end

  test "invalid intervals and one-Turn activity settings reject before activation" do
    for changes <- [
          %{idle_timeout: -1},
          %{tool_heartbeat: -1},
          %{idle_timeout: "300"},
          %{tool_heartbeat: 1.5},
          %{mode: :turn, steering: false}
        ] do
      assert {:error, %{field: "requests"}} =
               Authoring.lower(base(), [
                 Map.put(source(), :requests, Map.merge(source().requests, changes))
               ])
    end
  end

  defp atoms(%_{}), do: []
  defp atoms(map) when is_map(map), do: Enum.flat_map(map, fn {k, v} -> atoms(k) ++ atoms(v) end)
  defp atoms(list) when is_list(list), do: Enum.flat_map(list, &atoms/1)
  defp atoms(value) when is_tuple(value), do: value |> Tuple.to_list() |> atoms()
  defp atoms(atom) when is_atom(atom), do: [atom]
  defp atoms(_), do: []
  defp eventually(fun, attempts \\ 200)
  defp eventually(fun, 0), do: assert(fun.())

  defp eventually(fun, attempts) do
    if fun.(),
      do: :ok,
      else:
        (
          Process.sleep(10)
          eventually(fun, attempts - 1)
        )
  end
end
