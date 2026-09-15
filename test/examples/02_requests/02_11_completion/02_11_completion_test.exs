defmodule JidoAI.Examples.CompletionTest do
  use JidoAI.Examples.Case
  alias Jido.AI.Request
  alias JidoAI.Examples.Completion.FixtureAgent, as: Agent
  alias JidoAI.Examples.Completion.{Ledger, Store}

  defp start(jido, limit \\ nil, plugin_opts \\ []) do
    definition = Agent.definition()
    {:ok, definition} = Jido.AI.Authoring.with_state_size_limit(definition, limit)

    plugins =
      Enum.map(definition.plugins, fn
        {Ledger, _} -> {Ledger, plugin_opts}
        other -> other
      end)

    start_agent(
      jido,
      Jido.Agent.instantiate!(%{definition | plugins: plugins})
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
    do: Enum.filter(events, &(&1.kind in [:request_completed, :request_failed, :request_cancelled]))

  defp record(server, request), do: Server.agent(server).state.requests[request.id]

  for mode <- ["reject"] do
    test "a #{mode} Plugin reduction becomes a committed request failure without repeating tool work",
         %{jido: jido} do
      {mock, context} =
        mock([
          %{
            reply: {:tools, [%{id: "ledger", name: "ledger_tool", arguments: %{mode: unquote(mode)}}]}
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

  test "a post-commit directive failure preserves the answer and is not retried", %{jido: jido} do
    {mock, context} =
      mock([
        %{
          reply: {:tools, [%{id: "ledger", name: "ledger_tool", arguments: %{mode: "dispatch_fail"}}]}
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
      Jido.Agent.instantiate!(Agent.definition(), state: %{requests: %{pending.id => pending}})

    assert instance.state.requests[pending.id].completion_reserve == nil
    server = start_agent(jido, instance)
    handle = Request.Handle.new(pending.id, server, pending.query)
    assert {:error, :request_interrupted} = Request.await(handle)
    assert record(server, handle).status == :failed
    assert record(server, handle).run_id == pending.run_id
    assert record(server, handle).completion_reserve == nil
    assert_script_done(mock)
  end

  test "a refused durable completion stops the Agent without another write or Directive dispatch", %{
    jido: jido
  } do
    {mock, context} = mock([%{reply: {:text, "Refused"}}])
    store = start_supervised!(Store)
    instance = Agent.new!()
    adapter = {Store, store: store, failure: :conflict}
    assert {:ok, server} = Jido.start_agent(jido, instance, persistence: adapter, restore: false)
    monitor = Process.monitor(server)
    assert {:ok, request} = request(server, context)

    assert {:error, :agent_server_unavailable} = Request.await(request)
    assert_receive {:DOWN, ^monitor, :process, ^server, _}, 2_000

    assert {:ok, restored, _revision} =
             Jido.Persistence.load_agent_with_revision(adapter, Agent, instance.id, instance: jido)

    assert restored.state.requests[request.id].status == :pending
    assert restored.state.reply == ""
    assert Store.completion_writes(store) == 1
    assert Store.writes(store) >= 2
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
               Jido.Persistence.load_agent_with_revision(adapter, Agent, instance.id, instance: jido)

      assert revision + 1 == Store.writes(store)
      assert restored.state.reply == "Stored"
      assert restored.state.requests[request.id].status == :completed
      assert {:error, :agent_server_unavailable} = Request.await(request)
      assert_script_done(mock)
    end
  end
end
