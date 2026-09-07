defmodule JidoAI.Examples.SignalDeliveryTest do
  use JidoAI.Examples.Case
  alias Jido.AI.{Authoring, Request, Session}
  alias Jido.AI.Session.Delivery
  alias JidoAI.Examples.SignalDelivery.{Agent, Count, PublicAgent}

  setup do
    for key <- [:signal_delivery, :delivery_probe, :model_aliases] do
      old = Application.fetch_env(:jido_ai, key)

      on_exit(fn ->
        case old do
          {:ok, value} -> Application.put_env(:jido_ai, key, value)
          :error -> Application.delete_env(:jido_ai, key)
        end
      end)
    end

    Application.put_env(:jido_ai, :signal_delivery, timeout: 1_500)
    Application.put_env(:jido_ai, :delivery_probe, %{observer: self()})
    Application.put_env(:jido_ai, :model_aliases, %{example: MockLLM.model()})
    :ok
  end

  defp source do
    {_, opts} = Enum.find(Agent.agent().plugins, &(elem(&1, 0) == Jido.AI.Runtime.Plugin))
    Map.from_struct(opts[:profiles].assistant)
  end

  defp base do
    %{
      name: "signal_delivery",
      module: Agent,
      schema: Agent.domain_schema(),
      plugins: [JidoAI.Examples.SignalDelivery.Probe],
      routes: [{"ai.ask", Authoring.ai(:assistant)}]
    }
  end

  defp start(jido, changes \\ %{}, opts \\ []) do
    assert {:ok, definition} = Authoring.lower(base(), [Map.merge(source(), changes)])

    assert {:ok, server} =
             Jido.start_agent(
               jido,
               Jido.Agent.instantiate!(definition),
               Keyword.merge([default_dispatch: {:pid, target: self()}], opts)
             )

    server
  end

  defp request(server, context, query \\ "Echo ready") do
    Request.create_and_send(server, query,
      signal_type: "ai.ask",
      source: "/examples/delivery",
      context: context,
      stream_to: self()
    )
  end

  defp events(request),
    do: request |> Request.Stream.events(stream_event_timeout_ms: 1_000) |> Enum.to_list()

  defp report(server, request, status) do
    eventually(fn ->
      match?({:ok, %{status: ^status}}, Session.delivery_status(server, request.id))
    end)

    {:ok, report} = Session.delivery_status(server, request.id)
    report
  end

  defp owner(server) do
    runtime = Server.children(server)[{:plugin, Session.Plugin}].pid
    {runtime, :sys.get_state(runtime).delivery}
  end

  defp collect_signals(acc \\ []) do
    receive do
      {:signal, %Jido.Signal{} = signal} -> collect_signals([signal | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end

  defp stream do
    %{
      reply:
        {:stream,
         [
           %{
             tool_calls: [
               %{
                 index: 0,
                 id: "echo-call",
                 type: "function",
                 function: %{name: "echo", arguments: "{\"value\":\""}
               }
             ]
           },
           {:wait, :arguments},
           %{tool_calls: [%{index: 0, function: %{arguments: "ready\"}"}}]}
         ], "tool_calls"}
    }
  end

  @tag history_case: "HIST-13/automatic-signals"
  test "the owning Agent delivers early tool activity and every typed event in canonical order",
       %{jido: jido} do
    {mock, context} = mock([stream(), %{reply: {:text, ["Done", " now"]}}])
    server = start(jido)
    assert {:ok, request} = request(server, context)
    assert_receive {:mock_llm_waiting, ^mock, :arguments, _}, 2_000
    assert_receive {:signal, %{type: "ai.request.started"} = started}, 2_000
    assert_receive {:signal, %{type: "ai.llm.delta"} = early}, 2_000
    assert early.data.delta == "echo"
    refute_receive {:echo_executed, _}, 0
    assert :ok = MockLLM.release(mock, :arguments)
    assert {:ok, "Done now"} = Request.await(request)
    assert_receive {:echo_executed, "ready"}
    report = report(server, request, :delivered)
    canonical = events(request)
    delivered = [started, early | collect_signals()]

    expected =
      Enum.flat_map(canonical, fn event ->
        assert {:ok, signals} = Jido.AI.Signal.from_event(event)
        signals
      end)

    assert Enum.map(delivered, &{&1.type, &1.data, &1.time}) ==
             Enum.map(expected, &{&1.type, &1.data, &1.time})

    assert Enum.all?(delivered, &String.starts_with?(&1.subject, "version-"))

    assert Enum.all?(
             delivered,
             fn signal ->
               data = Map.get(signal.data, :metadata, signal.data)
               data.request_id == request.id and data.run_id == report.run_id
             end
           )

    seqs = for %{data: %{seq: seq}} <- delivered, do: seq
    assert seqs == Enum.sort(seqs)
    assert report.enqueued == report.delivered and report.dropped == 0 and report.unconfirmed == 0
    assert report.terminal? and report.last_seq == List.last(canonical).seq
    assert :ok = Jido.Action.validate_static_data(Server.agent(server).state)
    assert_script_done(mock)
  end

  test "the public Agent facade delivers a multimodal query and final answer", %{jido: jido} do
    {mock, context} = mock([%{reply: {:text, "Read"}}])

    assert {:ok, server} =
             Jido.start_agent(jido, PublicAgent, default_dispatch: {:pid, target: self()})

    query = [
      ReqLLM.Message.ContentPart.text("Read this"),
      ReqLLM.Message.ContentPart.image_url("https://example.test/image.png")
    ]

    assert {:ok, request} = PublicAgent.ask(server, query, context: context, stream_to: self())
    assert {:ok, "Read"} = PublicAgent.await(request)
    report(server, request, :delivered)
    signals = collect_signals()
    assert Enum.find(signals, &(&1.type == "ai.request.started")).data.query == query
    assert List.last(signals).type == "ai.request.completed"
    assert Enum.any?(events(request), &(&1.kind == :request_completed))
    assert_script_done(mock)
  end

  test "disabled Signal delivery preserves the canonical stream and output", %{jido: jido} do
    {mock, context} = mock([%{reply: {:text, ["One", " two"]}}])
    server = start(jido, %{observability: %{emit_signals?: false}})
    assert {:ok, request} = request(server, context)
    assert {:ok, "One two"} = Request.await(request)
    received = events(request)
    assert Enum.any?(received, &(&1.kind == :llm_delta))
    assert Enum.map(received, & &1.seq) == Enum.to_list(1..length(received))
    assert %{enqueued: 0, delivered: 0, terminal?: true} = report(server, request, :disabled)
    refute_receive {:signal, _}, 0
    refute_receive {:publish_admitted, _, _}, 0
    assert_script_done(mock)
  end

  test "delta capture can be disabled while terminal Signal delivery stays enabled", %{jido: jido} do
    {mock, context} = mock([%{reply: {:text, ["One", " two"]}}])
    server = start(jido, %{observability: %{emit_signals?: true, emit_llm_deltas?: false}})
    assert {:ok, request} = request(server, context)
    assert {:ok, "One two"} = Request.await(request)
    report(server, request, :delivered)
    signals = collect_signals()
    refute Enum.any?(signals, &(&1.type == "ai.llm.delta"))
    assert Enum.any?(signals, &(&1.type == "ai.llm.response"))
    assert List.last(signals).type == "ai.request.completed"
    refute Enum.any?(events(request), &(&1.kind == :llm_delta))
    assert_script_done(mock)
  end

  test "an outbound rejection leaves the committed answer intact and reports unconfirmed delivery",
       %{jido: jido} do
    Application.put_env(:jido_ai, :delivery_probe, %{
      observer: self(),
      reject: "ai.request.completed"
    })

    Application.put_env(:jido_ai, :signal_delivery, timeout: 200)
    {mock, context} = mock([%{reply: {:text, "Done"}}])
    server = start(jido)
    assert {:ok, request} = request(server, context)
    assert {:ok, "Done"} = Request.await(request)

    assert %{reason: :receipt_timeout, unconfirmed: missing} =
             report(server, request, :unconfirmed)

    assert missing >= 1
    assert Server.agent(server).state.reply == "Done"
    assert List.last(events(request)).kind == :request_completed
    refute Enum.any?(collect_signals(), &(&1.type == "ai.request.completed"))
    assert_script_done(mock)
  end

  test "rejected admission closes observation without model retries or a false receipt", %{
    jido: jido
  } do
    Application.put_env(:jido_ai, :delivery_probe, %{observer: self(), reject_admission: true})
    {mock, context} = mock([%{reply: {:text, "Done"}}])
    server = start(jido)
    assert {:ok, request} = request(server, context)
    assert {:ok, "Done"} = Request.await(request)

    assert %{delivered: 0, dropped: dropped, unconfirmed: 0, reason: {:commit_rejected, _}} =
             report(server, request, :failed)

    assert dropped >= 2
    refute_receive {:signal, _}, 0
    assert_script_done(mock)
  end

  test "a held final Emit does not turn an answer commit into a delivery receipt", %{jido: jido} do
    Application.put_env(:jido_ai, :delivery_probe, %{
      observer: self(),
      hold: "ai.request.completed"
    })

    {mock, context} = mock([%{reply: {:text, "Done"}}])
    server = start(jido)
    assert {:ok, request} = request(server, context)
    assert {:ok, "Done"} = Request.await(request)
    assert_receive {:outbound, %{type: "ai.request.completed"}, _, worker}, 2_000
    assert {:ok, %{status: :pending}} = Session.delivery_status(server, request.id)
    refute Enum.any?(collect_signals(), &(&1.type == "ai.request.completed"))
    send(worker, :release)
    report(server, request, :delivered)
    assert_receive {:signal, %{type: "ai.request.completed"}}
    assert_script_done(mock)
  end

  test "forged publication cannot supply a grant or change domain state", %{jido: jido} do
    server = start(jido)
    {_runtime, delivery} = owner(server)
    signal = Jido.Signal.new!(Session.publish_type(), %{batch_id: "invented"}, source: "/forged")
    before = Server.snapshot(server)
    forged = %{owner: delivery, id: "invented", ticket: make_ref()}

    assert {:error, _} =
             Server.call(server, signal,
               context: %{jido_ai_delivery_grant: forged, jido_ai_delivery_ticket: forged.ticket}
             )

    assert Server.snapshot(server) == before

    assert {:error, :invalid_delivery_grant} =
             Delivery.consume(delivery, "invented", forged.ticket)

    assert {:error, :stale_delivery_receipt} =
             Delivery.receipt(delivery, "invented", forged.ticket)

    refute_receive {:signal, _}, 0
  end

  test "a consumed ticket cannot publish twice or be replayed after its receipt", %{jido: jido} do
    Application.put_env(:jido_ai, :delivery_probe, %{observer: self(), hold: "ai.request.started"})

    {mock, context} =
      mock([%{reply: {:stream, [{:wait, :provider}, %{content: "Done"}], "stop"}}])

    server = start(jido)
    assert {:ok, request} = request(server, context)
    assert_receive {:publish_admitted, signal, admitted}, 2_000
    assert_receive {:outbound, %{type: "ai.request.started"}, _, worker}, 2_000
    {_runtime, delivery} = owner(server)
    ticket = admitted.jido_ai_delivery_ticket

    assert {:error, :invalid_delivery_grant} =
             Delivery.consume(delivery, signal.data.batch_id, ticket)

    send(worker, :release)
    assert_receive {:signal, %{type: "ai.request.started"}}, 2_000
    assert {:error, _} = Server.call(server, signal, context: %{jido_ai_delivery_ticket: ticket})
    assert_receive {:mock_llm_waiting, ^mock, :provider, _}, 2_000
    assert :ok = MockLLM.release(mock, :provider)
    assert {:ok, "Done"} = Request.await(request)
    report(server, request, :delivered)
    refute Enum.any?(collect_signals(), &(&1.type == "ai.request.started"))
    assert_script_done(mock)
  end

  for pattern <- [nil, "ai.*.*", "ai.request.completed"] do
    test "default self dispatch preserves host route #{inspect(pattern)}", %{jido: jido} do
      {mock, context} = mock([%{reply: {:text, "Done"}}])
      extra = if unquote(pattern), do: [{unquote(pattern), Count}], else: []

      assert {:ok, definition} =
               Authoring.lower(%{base() | routes: base().routes ++ extra}, [source()])

      server = start_agent(jido, Jido.Agent.instantiate!(definition))
      assert {:ok, request} = request(server, context)
      assert {:ok, "Done"} = Request.await(request)
      report(server, request, :delivered)
      events = events(request)

      expected =
        case unquote(pattern) do
          nil ->
            0

          "ai.request.completed" ->
            1

          _ ->
            Enum.sum(
              Enum.map(events, fn e ->
                {:ok, s} = Jido.AI.Signal.from_event(e)
                Enum.count(s, &(length(String.split(&1.type, ".")) == 3))
              end)
            )
        end

      eventually(fn -> Server.status(server).phase == :idle end)
      assert Server.agent(server).state.observed == expected
      assert Server.agent(server).state.reply == "Done"
      assert Server.status(server).phase == :idle
      assert_script_done(mock)
    end
  end

  for limit <- [:queue_limit, :byte_limit] do
    test "#{limit} bounds pending observation while the canonical stream retains all model deltas",
         %{jido: jido} do
      limit = unquote(limit)

      Application.put_env(:jido_ai, :signal_delivery,
        timeout: 1_500,
        queue_limit: 3,
        byte_limit: 2_000
      )

      Application.put_env(:jido_ai, :delivery_probe, %{
        observer: self(),
        hold: "ai.request.started"
      })

      text = unquote(if limit == :byte_limit, do: String.duplicate("x", 4_000), else: "x")

      {mock, context} =
        mock([
          %{
            reply: {:stream, [{:wait, :provider}] ++ List.duplicate(%{content: text}, 12), "stop"}
          }
        ])

      server = start(jido)
      assert {:ok, request} = request(server, context)
      assert_receive {:outbound, %{type: "ai.request.started"}, _, worker}, 2_000
      assert_receive {:mock_llm_waiting, ^mock, :provider, _}, 2_000
      {_runtime, delivery} = owner(server)
      assert :ok = MockLLM.release(mock, :provider)
      assert %{reason: ^limit, dropped: count} = report(server, request, :failed)
      assert count > 0
      queued = :sys.get_state(delivery)
      assert queued.bytes <= 2_000
      assert length(queued.pending) + length(queued.active.items) <= 3
      send(worker, :release)
      assert {:ok, output} = Request.await(request)
      assert output == String.duplicate(text, 12)
      received = events(request)
      assert Enum.count(received, &(&1.kind == :llm_delta)) == 12
      assert Enum.map(received, & &1.seq) == Enum.to_list(1..length(received))
      eventually(fn -> :sys.get_state(delivery).active == nil end)
      state = :sys.get_state(delivery)
      assert state.pending == [] and state.bytes == 0
      assert %{status: :failed, delivered: 1, terminal?: true} = report(server, request, :failed)
      assert [%{type: "ai.request.started"}] = collect_signals()
      assert_script_done(mock)
    end
  end

  test "core dispatch adapter failure prevents a receipt even after successful outbound preparation",
       %{jido: jido} do
    Application.put_env(:jido_ai, :signal_delivery, timeout: 200)
    {mock, context} = mock([%{reply: {:text, "Done"}}])

    server =
      start(jido, %{}, default_dispatch: {JidoAI.Examples.SignalDelivery.Adapter, target: self()})

    assert {:ok, request} = request(server, context)
    assert {:ok, "Done"} = Request.await(request)
    assert_receive {:adapter_called, %{type: "ai.request.completed"}}, 2_000
    assert %{unconfirmed: count} = report(server, request, :unconfirmed)
    assert count > 0
    refute Enum.any?(collect_signals(), &(&1.type == "ai.request.completed"))
    assert_script_done(mock)
  end

  test "a core Directive timeout stops the outbound worker without replaying a committed batch",
       %{jido: jido} do
    Application.put_env(:jido_ai, :signal_delivery, timeout: 250)

    Application.put_env(:jido_ai, :delivery_probe, %{
      observer: self(),
      hold: "ai.request.completed"
    })

    {mock, context} = mock([%{reply: {:text, "Done"}}, %{reply: {:text, "Next"}}])
    server = start(jido, %{}, directive_timeout: 100)
    assert {:ok, request} = request(server, context)
    assert {:ok, "Done"} = Request.await(request)
    assert_receive {:outbound, %{type: "ai.request.completed"}, _, worker}, 2_000
    monitor = Process.monitor(worker)
    assert_receive {:DOWN, ^monitor, :process, ^worker, :killed}, 1_000
    report(server, request, :unconfirmed)
    refute Enum.any?(collect_signals(), &(&1.type == "ai.request.completed"))
    Application.put_env(:jido_ai, :delivery_probe, %{observer: self()})
    assert {:ok, next} = request(server, context)
    assert {:ok, "Next"} = Request.await(next)
    report(server, next, :delivered)
    completed = Enum.filter(collect_signals(), &(&1.type == "ai.request.completed"))
    assert [signal] = completed
    assert signal.data.request_id == next.id
    assert_script_done(mock)
  end

  test "cancellation closes the provider and delivers one typed request failure", %{jido: jido} do
    {mock, context} = mock([stream()])
    server = start(jido)
    assert {:ok, request} = request(server, context)
    assert_receive {:mock_llm_waiting, ^mock, :arguments, provider}, 2_000
    monitor = Process.monitor(provider)
    assert_receive {:signal, %{type: "ai.llm.delta"}}, 2_000
    assert :ok = Session.cancel(request)
    assert {:error, :cancelled} = Request.await(request)
    assert_receive {:DOWN, ^monitor, :process, ^provider, _}, 2_000
    report(server, request, :delivered)
    failures = Enum.filter(collect_signals(), &(&1.type == "ai.request.failed"))
    assert [failed] = failures
    assert failed.data.request_id == request.id and failed.data.error == {:cancelled, :cancelled}
    assert List.last(events(request)).kind == :request_cancelled
    refute_receive {:echo_executed, _}, 0
    eventually(fn -> MockLLM.report(mock).waiting == [] end)
    assert_script_done(mock)
  end

  test "owner restart discards the transient queue and rejects old tickets without replay", %{
    jido: jido
  } do
    Application.put_env(:jido_ai, :delivery_probe, %{observer: self(), hold: "ai.request.started"})

    {mock, context} =
      mock([
        %{reply: {:stream, [{:wait, :provider}, %{content: "Lost"}], "stop"}},
        %{reply: {:text, "Next"}}
      ])

    server = start(jido)
    assert {:ok, request} = request(server, context)
    assert_receive {:publish_admitted, signal, admitted}, 2_000
    assert_receive {:outbound, %{type: "ai.request.started"}, _, worker}, 2_000
    assert_receive {:mock_llm_waiting, ^mock, :provider, provider}, 2_000
    {runtime, delivery} = owner(server)
    delivery_ref = Process.monitor(delivery)
    provider_ref = Process.monitor(provider)
    Process.exit(runtime, :kill)
    assert_receive {:DOWN, ^delivery_ref, :process, ^delivery, _}, 2_000
    assert_receive {:DOWN, ^provider_ref, :process, ^provider, _}, 2_000
    Application.put_env(:jido_ai, :delivery_probe, %{observer: self()})
    # Core already committed this Emit. Owner death cannot retract it.
    send(worker, :release)
    assert_receive {:signal, %{type: "ai.request.started"}}, 2_000
    assert {:error, :stream_interrupted} = Request.await(request)
    {new_runtime, new_delivery} = owner(server)
    refute new_runtime == runtime or new_delivery == delivery
    assert {:error, :unknown_delivery} = Session.delivery_status(server, request.id)

    assert {:error, _} =
             Server.call(server, signal,
               context: %{jido_ai_delivery_ticket: admitted.jido_ai_delivery_ticket}
             )

    assert {:error, :invalid_delivery_grant} =
             Delivery.consume(
               new_delivery,
               signal.data.batch_id,
               admitted.jido_ai_delivery_ticket
             )

    assert {:ok, next} = request(server, context)
    assert {:ok, "Next"} = Request.await(next)
    report(server, next, :delivered)

    assert Enum.all?(collect_signals(), fn signal ->
             data = Map.get(signal.data, :metadata, signal.data)
             data.request_id == next.id
           end)

    eventually(fn -> MockLLM.report(mock).waiting == [] end)
    assert_script_done(mock)
  end

  test "server shutdown stops the delivery owner and the active outbound worker", %{jido: jido} do
    Application.put_env(:jido_ai, :delivery_probe, %{observer: self(), hold: "ai.request.started"})

    {mock, context} =
      mock([%{reply: {:stream, [{:wait, :provider}, %{content: "Lost"}], "stop"}}])

    server = start(jido)
    assert {:ok, _request} = request(server, context)
    assert_receive {:outbound, %{type: "ai.request.started"}, _, worker}, 2_000
    assert_receive {:mock_llm_waiting, ^mock, :provider, provider}, 2_000
    {runtime, delivery} = owner(server)
    refs = for pid <- [runtime, delivery, worker, provider], do: {pid, Process.monitor(pid)}
    assert :ok = Jido.stop_agent(jido, server)
    for {pid, ref} <- refs, do: assert_receive({:DOWN, ^ref, :process, ^pid, _}, 2_000)
    assert {:error, :signal_delivery_unavailable} = Session.delivery_status(server, "gone")
    eventually(fn -> MockLLM.report(mock).waiting == [] end)
    assert_script_done(mock)
  end

  test "DSL data Builder and source JSON preserve enabled and disabled delivery policy", %{
    jido: jido
  } do
    assert {:ok, definition} = Authoring.lower(base(), [source()])
    assert definition == Agent.agent()
    attrs = definition |> Jido.Agent.to_map() |> Map.drop([:id, :state])
    assert {:ok, built} = attrs |> Jido.Agent.Builder.new() |> Jido.Agent.Builder.build()

    registry =
      source()
      |> Map.put(:routes, [])
      |> atoms()
      |> Enum.uniq()
      |> Map.new(&{"atoms/#{&1}", {:atom, &1}})
      |> Map.put("models/answer", {:value, source().models.answer.model})

    assert {:ok, document} = Authoring.Codec.encode([source()], registry)

    assert {:ok, decoded} =
             Authoring.Codec.decode(base(), Jason.decode!(Jason.encode!(document)), registry)

    assert built == definition and decoded == definition
    quiet = %{source() | observability: %{emit_signals?: false}}
    assert {:ok, quiet_definition} = Authoring.lower(base(), [quiet])
    assert {:ok, quiet_document} = Authoring.Codec.encode([quiet], registry)

    assert {:ok, quiet_decoded} =
             Authoring.Codec.decode(
               base(),
               Jason.decode!(Jason.encode!(quiet_document)),
               registry
             )

    assert quiet_definition == quiet_decoded
    {mock, context} = mock(List.duplicate(%{reply: {:text, "Done"}}, 5))

    for {definition, status} <- [
          {Agent.agent(), :delivered},
          {definition, :delivered},
          {built, :delivered},
          {decoded, :delivered},
          {quiet_decoded, :disabled}
        ] do
      assert {:ok, server} =
               Jido.start_agent(jido, Jido.Agent.instantiate!(definition),
                 default_dispatch: {:pid, target: self()}
               )

      assert {:ok, request} = request(server, context)
      assert {:ok, "Done"} = Request.await(request)
      report(server, request, status)

      if status == :disabled,
        do: assert(collect_signals() == []),
        else: assert(collect_signals() != [])
    end

    assert_script_done(mock)

    for value <- [nil, "false", 0] do
      assert {:error, %{field: "observability"}} =
               Authoring.lower(base(), [%{source() | observability: %{emit_signals?: value}}])
    end
  end

  test "a late Emit may finish after receipt timeout without changing the unconfirmed report", %{
    jido: jido
  } do
    Application.put_env(:jido_ai, :signal_delivery, timeout: 100)

    Application.put_env(:jido_ai, :delivery_probe, %{
      observer: self(),
      hold: "ai.request.completed"
    })

    {mock, context} = mock([%{reply: {:text, "Done"}}])
    server = start(jido, %{}, directive_timeout: 2_000)
    assert {:ok, request} = request(server, context)
    assert {:ok, "Done"} = Request.await(request)
    assert_receive {:outbound, %{type: "ai.request.completed"}, _, worker}, 2_000
    before = report(server, request, :unconfirmed)
    assert Process.alive?(worker)
    send(worker, :release)
    assert_receive {:signal, %{type: "ai.request.completed"}}, 2_000
    eventually(fn -> Server.status(server).phase == :idle end)
    assert {:ok, ^before} = Session.delivery_status(server, request.id)
    refute_receive {:signal, %{type: "ai.request.completed"}}, 50
    assert_script_done(mock)
  end

  test "an expired admission ticket cannot emit when core admission later resumes", %{jido: jido} do
    Application.put_env(:jido_ai, :signal_delivery, timeout: 100)
    Application.put_env(:jido_ai, :delivery_probe, %{observer: self(), hold_admission: true})
    {mock, context} = mock([%{reply: {:text, "Done"}}])
    server = start(jido)
    assert {:ok, request} = request(server, context)
    assert_receive {:admission_held, worker}, 2_000
    {_runtime, delivery} = owner(server)
    task = :sys.get_state(delivery).active.task
    ref = Process.monitor(task.pid)
    report(server, request, :unconfirmed)
    assert_receive {:DOWN, ^ref, :process, _, _}, 2_000
    Application.put_env(:jido_ai, :delivery_probe, %{observer: self()})
    send(worker, :release)
    assert {:ok, "Done"} = Request.await(request)
    assert List.last(events(request)).kind == :request_completed
    eventually(fn -> Server.status(server).phase == :idle end)
    assert %{delivered: 0} = report(server, request, :unconfirmed)
    refute_receive {:signal, _}, 50
    assert_script_done(mock)
  end

  test "a provider failure delivers a typed failure with the actual request and run identity", %{
    jido: jido
  } do
    {mock, context} = mock([%{reply: {:error, 500, %{error: %{message: "provider refused"}}}}])
    server = start(jido)
    assert {:ok, request} = request(server, context)
    assert {:error, reason} = Request.await(request)
    report = report(server, request, :delivered)
    failed = Enum.filter(collect_signals(), &(&1.type == "ai.request.failed"))
    assert [signal] = failed
    assert signal.data.error == reason
    assert signal.data.request_id == request.id and signal.data.run_id == report.run_id
    assert List.last(events(request)).kind == :request_failed
    assert_script_done(mock)
  end

  test "completed disabled reports are bounded and the latest request remains inspectable", %{
    jido: jido
  } do
    {mock, context} = mock(List.duplicate(%{reply: {:text, "Done"}}, 102))
    server = start(jido, %{observability: %{emit_signals?: false}})

    ids =
      for _ <- 1..102 do
        assert {:ok, request} = request(server, context)
        assert {:ok, "Done"} = Request.await(request)
        assert List.last(events(request)).kind == :request_completed
        request.id
      end

    {_runtime, delivery} = owner(server)
    state = :sys.get_state(delivery)
    assert map_size(state.reports) == 100
    assert {:error, :unknown_delivery} = Session.delivery_status(server, hd(ids))

    assert {:ok, %{status: :disabled, terminal?: true}} =
             Session.delivery_status(server, List.last(ids))

    assert state.pending == [] and state.active == nil and state.bytes == 0
    refute_receive {:signal, _}, 0
    assert_script_done(mock)
  end

  test "core Directive limits reject observation before dispatch and still permit the answer commit",
       %{jido: jido} do
    {mock, context} = mock([%{reply: {:text, "Done"}}])
    server = start(jido, %{}, max_directives_per_turn: 1)
    assert {:ok, request} = request(server, context)
    assert {:ok, "Done"} = Request.await(request)
    assert %{delivered: 0, reason: {:commit_rejected, _}} = report(server, request, :failed)
    refute_receive {:outbound, _, _, _}, 0
    refute_receive {:signal, _}, 0
    assert List.last(events(request)).kind == :request_completed
    assert_script_done(mock)
  end

  test "invalid delivery limits fail Agent activation with a defined configuration error", %{
    jido: jido
  } do
    {mock, _context} = mock([])

    for opts <- [
          [queue_limit: 0],
          [byte_limit: -1],
          [batch_size: 65],
          [timeout: :infinity],
          [unknown: true],
          %{queue_limit: 1}
        ] do
      Application.put_env(:jido_ai, :signal_delivery, opts)
      assert {:error, reason} = Jido.start_agent(jido, Agent)
      text = inspect(reason)
      assert text =~ "invalid_signal_delivery_"
      refute text =~ "bad_return_value"
    end

    assert_script_done(mock)
  end

  defp atoms(%_{}), do: []
  defp atoms(map) when is_map(map), do: Enum.flat_map(map, fn {k, v} -> atoms(k) ++ atoms(v) end)
  defp atoms(list) when is_list(list), do: Enum.flat_map(list, &atoms/1)
  defp atoms(value) when is_tuple(value), do: value |> Tuple.to_list() |> atoms()
  defp atoms(atom) when is_atom(atom), do: [atom]
  defp atoms(_), do: []
  defp eventually(fun, attempts \\ 300)
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
