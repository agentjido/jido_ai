defmodule JidoAI.Examples.CompletionTest do
  use JidoAI.Examples.Case
  alias Jido.AI.{Request, Session}
  alias JidoAI.Examples.Completion.{Agent, Ledger, Store}

  defp start(jido, limit \\ nil, plugin_opts \\ []) do
    definition = Agent.agent()

    plugins =
      Enum.map(definition.plugins, fn
        {Ledger, _} -> {Ledger, plugin_opts}
        other -> other
      end)

    start_agent(
      jido,
      Jido.Agent.instantiate!(%{definition | max_state_size: limit, plugins: plugins})
    )
  end

  defp request(server, context),
    do:
      Request.create_and_send(server, "Work",
        signal_type: "ai.ask",
        source: "/examples/completion",
        context: context,
        stream_to: self()
      )

  defp events(request),
    do: request |> Request.Stream.events(stream_event_timeout_ms: 2_000) |> Enum.to_list()

  defp terminal(events),
    do:
      Enum.filter(events, &(&1.kind in [:request_completed, :request_failed, :request_cancelled]))

  defp record(server, request), do: Server.agent(server).state.requests[request.id]

  for mode <- ["reject", "inflate"] do
    test "a #{mode} Plugin reduction becomes a committed request failure without repeating tool work",
         %{jido: jido} do
      {mock, context} =
        mock([
          %{
            reply:
              {:tools, [%{id: "ledger", name: "ledger_tool", arguments: %{mode: unquote(mode)}}]}
          },
          %{reply: {:text, "Done"}},
          %{reply: {:text, "Next"}}
        ])

      server = start(jido, 5_000)
      assert {:ok, request} = request(server, context)
      assert {:error, {:completion_failed, _}} = Request.await(request, timeout: 1_500)
      assert_receive {:ledger_tool, unquote(mode)}
      assert_receive {:ledger_reduce, unquote(mode)}
      refute_receive {:ledger_tool, _}, 20
      refute_receive {:ledger_reduce, _}, 20
      refute_receive {:ledger_dispatch, _}, 20
      assert %{reply: "", ledger: %{value: ""}} = Server.agent(server).state
      assert record(server, request).status == :failed
      assert [%{kind: :request_failed}] = terminal(events(request))
      assert {:ok, next} = request(server, context)
      assert {:ok, "Next"} = Request.await(next)
      assert_script_done(mock)
    end
  end

  test "an oversized answer becomes a small committed failure within the state limit", %{
    jido: jido
  } do
    {mock, context} = mock([%{reply: {:text, String.duplicate("answer", 5_000)}}])
    server = start(jido, 1_500)
    assert {:ok, request} = request(server, context)
    assert {:error, _} = failure = Request.await(request, timeout: 1_500)
    refute failure == {:error, :timeout}
    assert record(server, request).status == :failed
    assert record(server, request).completion_reserve == nil
    assert record(server, request).meta.completion.details_elided?
    assert Server.agent(server).state.reply == ""
    assert :erlang.external_size(Server.agent(server).state) <= 1_500
    assert [%{kind: :request_failed}] = terminal(events(request))
    assert_script_done(mock)
  end

  test "reserved bytes permit a small failure when another Turn fills the state", %{jido: jido} do
    {mock, context} =
      mock([%{reply: {:wait, :answer, {:text, String.duplicate("answer", 5_000)}}}])

    limit = 5_000
    server = start(jido, limit)
    assert {:ok, request} = request(server, context)
    assert_receive {:mock_llm_waiting, ^mock, :answer, _}, 2_000
    pending = Server.agent(server).state
    assert byte_size(pending.requests[request.id].completion_reserve) == 512
    fill = limit - :erlang.external_size(pending)
    assert fill > 0

    assert {:ok, _} =
             Server.call(server, Jido.Signal.new!("fill", %{bytes: fill}, source: "/test"))

    assert :erlang.external_size(Server.agent(server).state) == limit
    assert :ok = MockLLM.release(mock, :answer)
    assert {:error, {:completion_failed, :details_elided}} = Request.await(request)
    assert record(server, request).status == :failed
    assert record(server, request).completion_reserve == nil
    assert record(server, request).meta == %{completion: %{details_elided?: true}}
    assert Server.agent(server).state.reply == String.duplicate(".", fill)
    assert :erlang.external_size(Server.agent(server).state) <= limit
    assert [%{kind: :request_failed}] = terminal(events(request))
    assert_script_done(mock)
  end

  test "admission rejects before model work when the completion reserve does not fit", %{
    jido: jido
  } do
    {mock, context} = mock([])
    server = start(jido, 600)
    before = Server.snapshot(server)
    assert {:error, %{kind: :state_size}} = request(server, context)
    assert Server.snapshot(server) == before
    assert_script_done(mock)
  end

  test "a post-commit directive failure preserves the answer and is not retried", %{jido: jido} do
    {mock, context} =
      mock([
        %{
          reply:
            {:tools, [%{id: "ledger", name: "ledger_tool", arguments: %{mode: "dispatch_fail"}}]}
        },
        %{reply: {:text, "Committed"}}
      ])

    server = start(jido)
    assert {:ok, request} = request(server, context)
    assert {:ok, "Committed"} = Request.await(request)
    assert_receive {:ledger_dispatch, "dispatch_fail"}, 2_000
    refute_receive {:ledger_dispatch, _}, 20
    assert %{reply: "Committed"} = Server.agent(server).state
    assert [%{kind: :request_completed}] = terminal(events(request))
    assert_script_done(mock)
  end

  test "an older pending v3 record without reserved bytes can be interrupted during activation",
       %{
         jido: jido
       } do
    {mock, _context} = mock([])

    pending = %{
      id: "old-request",
      run_id: "old-run",
      profile_id: :assistant,
      query: "Old work",
      status: :pending,
      inserted_at: 1,
      completed_at: nil,
      streamed: false,
      max_requests: 10
    }

    instance =
      Jido.Agent.instantiate!(Agent.agent(), state: %{requests: %{pending.id => pending}})

    assert instance.state.requests[pending.id].completion_reserve == nil
    server = start_agent(jido, instance)
    handle = Request.Handle.new(pending.id, server, pending.query)
    assert {:error, :request_interrupted} = Request.await(handle)
    assert record(server, handle).status == :failed
    assert record(server, handle).run_id == pending.run_id
    assert record(server, handle).completion_reserve == nil
    assert_script_done(mock)
  end

  test "a Plugin that denies every settlement returns an explicit uncommitted failure", %{
    jido: jido
  } do
    {mock, context} = mock([%{reply: {:text, "Denied"}}])
    server = start(jido, nil, deny_settle: true)
    assert {:ok, request} = request(server, context)
    assert {:error, {:completion_uncommitted, _}} = Request.await(request, timeout: 1_500)
    assert record(server, request).status == :pending
    assert Server.agent(server).state.reply == ""
    assert [%{kind: :request_failed, data: %{committed?: false}}] = terminal(events(request))
    assert {:error, {:completion_uncommitted, _}} = Request.await(request, timeout: 0)
    assert :ok = Session.cancel(request)

    for kind <- [:request_completed, :request_failed, :request_cancelled] do
      refute_receive {:jido_ai_request_event, %{kind: ^kind}}, 20
    end

    assert_script_done(mock)
  end

  test "a refused durable completion is reported without another write or Directive dispatch", %{
    jido: jido
  } do
    {mock, context} = mock([%{reply: {:text, "Refused"}}])
    store = start_supervised!(Store)
    instance = Agent.new!()
    adapter = {Store, store: store, failure: :conflict}
    assert {:ok, server} = Jido.start_agent(jido, instance, persistence: adapter, restore: false)
    assert {:ok, request} = request(server, context)

    assert {:error, {:completion_uncommitted, {:persistence_failed, :conflict}}} =
             Request.await(request)

    assert record(server, request).status == :pending
    assert Server.agent(server).state.reply == ""
    assert Store.completion_writes(store) == 1
    assert Store.writes(store) >= 2
    assert [%{kind: :request_failed, data: %{committed?: false}}] = terminal(events(request))
    assert_script_done(mock)
  end

  for failure <- [:indeterminate, :raise] do
    test "a #{failure} durable completion reply does not replay stored work", %{jido: jido} do
      {mock, context} =
        mock([
          %{
            reply: {:tools, [%{id: "stored", name: "ledger_tool", arguments: %{mode: "stored"}}]}
          },
          %{reply: {:wait, :answer, {:text, "Stored"}}}
        ])

      store = start_supervised!(Store)
      instance = Agent.new!()
      adapter = {Store, store: store, failure: unquote(failure)}

      assert {:ok, server} =
               Jido.start_agent(jido, instance, persistence: adapter, restore: false)

      monitor = Process.monitor(server)
      assert {:ok, request} = request(server, context)
      assert_receive {:ledger_tool, "stored"}, 2_000
      assert_receive {:mock_llm_waiting, ^mock, :answer, _}, 2_000
      assert :ok = MockLLM.release(mock, :answer)
      assert_receive {:DOWN, ^monitor, :process, ^server, _}, 2_000
      assert_receive {:ledger_reduce, "stored"}
      refute_receive {:ledger_tool, _}, 20
      refute_receive {:ledger_reduce, _}, 20
      refute_receive {:ledger_dispatch, _}, 20
      assert Store.completion_writes(store) == 1
      assert Store.writes(store) >= 2

      assert {:ok, restored, revision} =
               Jido.Persistence.load_agent_with_revision(adapter, Agent, instance.id,
                 instance: jido
               )

      assert revision == Store.writes(store)
      assert restored.state.reply == "Stored"
      assert restored.state.requests[request.id].status == :completed
      assert {:error, :agent_server_unavailable} = Request.await(request)
      assert_script_done(mock)
    end
  end
end
