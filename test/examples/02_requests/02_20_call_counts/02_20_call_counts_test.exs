defmodule JidoAI.Examples.CallCountsTest do
  use JidoAI.Examples.Case
  alias Jido.AI.{Request, Session}
  alias JidoAI.Examples.CallCounts.Agent

  setup do
    old = Application.fetch_env(:jido_ai, :model_aliases)
    Application.put_env(:jido_ai, :model_aliases, %{example: MockLLM.model()})

    on_exit(fn ->
      case old do
        {:ok, value} -> Application.put_env(:jido_ai, :model_aliases, value)
        :error -> Application.delete_env(:jido_ai, :model_aliases)
      end
    end)
  end

  defp submit(server, context, opts \\ []) do
    Request.create_and_send(
      server,
      "Review",
      Keyword.merge(
        [
          signal_type: "case.review",
          source: "/examples/counts",
          context: context,
          stream_to: self()
        ],
        opts
      )
    )
  end

  defp record(server, request), do: Server.agent(server).state.requests[request.id]

  defp events(request),
    do: request |> Request.Stream.events(stream_event_timeout_ms: 2_000) |> Enum.to_list()

  defp assert_counts(server, request, count) do
    saved = record(server, request)
    assert saved.meta.model_calls == count
    stream = events(request)
    assert Enum.count(stream, &(&1.kind == :llm_started)) == count
    assert List.last(stream).data.meta.model_calls == count
    assert List.last(stream).data.meta == saved.meta
    assert :ok = Jido.Action.validate_static_data(Server.agent(server).state)
    saved
  end

  for stage <- [:input, :model] do
    test "#{stage} control rejection records zero model operations", %{jido: jido} do
      {mock, context} = mock([])
      server = start_agent(jido, Agent.new!())
      assert {:ok, request} = submit(server, Map.put(context, :reject_at, unquote(stage)))
      assert {:error, _} = Request.await(request)
      assert_counts(server, request, 0)
      assert_script_done(mock)
    end
  end

  test "all eight methods retain the first failed model operation", %{jido: jido} do
    methods = [
      :react,
      :chain_of_thought,
      :chain_of_draft,
      :algorithm_of_thoughts,
      :tree_of_thoughts,
      :graph_of_thoughts,
      :trm,
      :adaptive
    ]

    {mock, context} =
      mock(List.duplicate(%{reply: {:error, 503, "Unavailable"}}, length(methods)))

    for method <- methods do
      definition = JidoAI.Examples.PluginStack.definition(reasoning: method)
      route = Enum.find(definition.routes, &match?({Jido.AI.Session.Start, _}, &1.target)).path
      server = start_agent(jido, definition)
      assert {:ok, request} = submit(server, context, signal_type: route)
      assert {:error, _} = Request.await(request)
      assert_counts(server, request, 1)
    end

    assert length(MockLLM.report(mock).requests) == length(methods)
    assert_script_done(mock)
  end

  test "later provider failure retains both operations and completed usage", %{jido: jido} do
    {mock, context} =
      mock([
        %{reply: {:tools, [%{id: "echo", name: "scope_echo", arguments: %{value: 2}}]}},
        %{reply: {:error, 503, "Unavailable"}}
      ])

    server = start_agent(jido, Agent.new!())
    assert {:ok, request} = submit(server, context)
    assert {:error, _} = Request.await(request)
    saved = assert_counts(server, request, 2)
    assert saved.meta.usage.total_tokens == 15
    assert [%{id: "echo", result: {:ok, %{value: 2}, []}}] = saved.meta.tool_results
    assert length(MockLLM.report(mock).requests) == 2
    assert_script_done(mock)
  end

  test "HTTP retries count once even when the operation fails", %{jido: jido} do
    {mock, context} =
      mock([%{reply: {:error, 429, "Limited"}}, %{reply: {:error, 503, "Unavailable"}}])

    options =
      MockLLM.options(mock)
      |> Keyword.put(:max_retries, 1)
      |> Keyword.update!(:req_http_options, &Keyword.delete(&1, :retry))

    context = put_in(context.ai.assistant.options, options)
    server = start_agent(jido, Agent.new!())
    assert {:ok, request} = submit(server, context)
    assert {:error, _} = Request.await(request)
    assert_counts(server, request, 1)
    assert length(MockLLM.report(mock).requests) == 2
    assert_script_done(mock)
  end

  test "provider option validation counts the operation without inventing HTTP work", %{
    jido: jido
  } do
    {mock, context} = mock([])
    server = start_agent(jido, Agent.new!())
    assert {:ok, request} = submit(server, context, llm_opts: [temperature: :invalid])
    assert {:error, _} = Request.await(request)
    saved = assert_counts(server, request, 1)
    assert saved.meta.usage == %{}
    assert_script_done(mock)
  end

  test "cancellation retains observed operations and the next request starts from zero", %{
    jido: jido
  } do
    {mock, context} = mock([%{reply: {:wait, :held, {:text, "Late"}}}, %{reply: {:text, "Next"}}])
    server = start_agent(jido, Agent.new!())
    assert {:ok, request} = submit(server, context)
    assert_receive {:mock_llm_waiting, ^mock, :held, provider}, 2_000
    monitor = Process.monitor(provider)
    assert :ok = Session.cancel(request)
    assert {:error, :cancelled} = Request.await(request)
    saved = assert_counts(server, request, 1)
    assert_receive {:DOWN, ^monitor, :process, ^provider, _}, 2_000
    assert {:ok, next} = submit(server, context)
    assert {:ok, "Next"} = Request.await(next)
    assert_counts(server, next, 1)
    assert record(server, request) == saved
    assert_script_done(mock)
  end

  test "failed model repair counts its operation but a repair callback does not", %{jido: jido} do
    {mock, context} =
      mock([
        %{reply: {:object, %{answer: 3}}},
        %{reply: {:error, 503, "Unavailable"}},
        %{reply: {:object, %{answer: 4}}}
      ])

    definition =
      JidoAI.Examples.PluginStack.definition(output: [schema: Zoi.object(%{answer: Zoi.string()}), retries: 1])

    server = start_agent(jido, definition)
    assert {:ok, request} = submit(server, context, signal_type: "ai.react.query")
    assert {:error, _} = Request.await(request)
    saved = assert_counts(server, request, 2)
    assert saved.meta.output.status == :error
    assert saved.meta.usage.total_tokens == 15

    callback = JidoAI.Examples.ErrorContract.Agent
    server = start_agent(jido, callback.new!())
    context = Map.put(context, :failure, :repair_unavailable)
    assert {:ok, request} = callback.ask(server, "Repair", context: context, stream_to: self())
    assert {:error, :repair_unavailable} = Request.await(request)
    assert_counts(server, request, 1)
    assert_script_done(mock)
  end

  test "an inner Quota rejection is distinct from a charged model call", %{jido: jido} do
    start_supervised!({Jido.AI.Quota.Store, []})

    {mock, context} =
      mock([%{reply: {:tools, [%{id: "echo", name: "scope_echo", arguments: %{value: 1}}]}}])

    definition =
      JidoAI.Examples.PluginStack.definition(
        tools: [JidoAI.Examples.RequestScope.Echo],
        quota: [scope: "counts", max_requests: 1]
      )

    server = start_agent(jido, definition)
    assert {:ok, request} = submit(server, context, signal_type: "ai.react.query")
    assert {:error, _} = Request.await(request)
    saved = assert_counts(server, request, 2)
    assert saved.meta.usage.total_tokens == 15
    assert %{requests: 1, total_tokens: 15} = Jido.AI.Quota.Store.get("counts")
    assert length(MockLLM.report(mock).requests) == 1
    assert_script_done(mock)
  end

  test "a shared model-call limit stops the next operation before it starts", %{jido: jido} do
    {mock, context} =
      mock([%{reply: {:tools, [%{id: "echo", name: "scope_echo", arguments: %{value: 1}}]}}])

    {_, opts} = Enum.find(Agent.definition().plugins, &(elem(&1, 0) == Jido.AI.Runtime.Plugin))
    profile = opts[:profiles].assistant |> Map.from_struct()
    profile = put_in(profile.controls.max_model_calls, 1)

    assert {:ok, definition} =
             Jido.AI.Authoring.lower(
               %{
                 name: "limited_counts",
                 schema: Agent.domain_schema(),
                 routes: [{"case.review", Jido.AI.Authoring.ai(:assistant)}]
               },
               [profile]
             )

    server = start_agent(jido, definition)
    assert {:ok, request} = submit(server, context)
    assert {:error, _} = Request.await(request)
    assert_counts(server, request, 1)
    assert_script_done(mock)
  end

  test "owner loss leaves the uncommitted count unknown and a new owner serves the next request",
       %{jido: jido} do
    {mock, context} =
      mock([
        %{reply: {:tools, [%{id: "held", name: "wait", arguments: %{n: 2}}]}},
        %{reply: {:text, "Recovered"}}
      ])

    module = JidoAI.Examples.Session.Agent
    server = start_agent(jido, module.new!())
    assert {:ok, request} = module.ask(server, "Wait", context: context, stream_to: self())
    id = request.id
    assert_receive {:session_owner, owner, ^id}, 2_000
    assert_receive {:tool_waiting, worker, 2}, 2_000
    monitor = Process.monitor(worker)
    Process.exit(owner, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^worker, _}, 2_000
    assert {:error, :stream_interrupted} = Request.await(request)
    refute Map.has_key?(record(server, request).meta, :model_calls)
    assert {:ok, next} = module.ask(server, "Next", context: context, stream_to: self())
    assert {:ok, "Recovered"} = Request.await(next)
    assert_counts(server, next, 1)
    assert_script_done(mock)
  end

  test "cancellation before model work retains a known zero count", %{jido: jido} do
    {mock, context} = mock([])
    server = start_agent(jido, Agent.new!())
    assert {:ok, request} = submit(server, Map.put(context, :hold_input, true))
    assert_receive {:input_held, worker}, 2_000
    monitor = Process.monitor(worker)
    assert :ok = Session.cancel(request)
    assert {:error, :cancelled} = Request.await(request)
    assert_receive {:DOWN, ^monitor, :process, ^worker, _}, 2_000
    assert_counts(server, request, 0)
    assert_script_done(mock)
  end

  test "late duplicate observation Signals cannot change a completed count", %{jido: jido} do
    {mock, context} = mock([%{reply: {:text, "Done"}}])
    server = start_agent(jido, Agent.new!())
    assert {:ok, request} = submit(server, context)
    assert {:ok, "Done"} = Request.await(request)
    saved = assert_counts(server, request, 1)

    data = %{
      request_id: request.id,
      call_id: "late",
      model: "example",
      result: {:ok, %{text: "Duplicate"}},
      usage: %{total_tokens: 99}
    }

    for type <- ["ai.llm.response", "ai.llm.response", "ai.usage"] do
      signal = Jido.Signal.new!(type, data, source: "/examples/counts")
      assert {:ok, _} = Server.call(server, signal)
    end

    assert record(server, request) == saved
    id = request.id
    refute_receive {:jido_ai_request_event, %{request_id: ^id}}, 20
    assert_script_done(mock)
  end
end
