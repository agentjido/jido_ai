defmodule JidoAI.Examples.ToolCallbacksTest do
  use JidoAI.Examples.Case
  alias Jido.AI.{Authoring, Request, Session}
  alias JidoAI.Examples.ToolCallbacks.{Agent, Consume, Hooks, ListItems, PublicAgent, Work}

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

  defp call(id, name, arguments), do: %{id: id, name: name, arguments: arguments}
  defp work(id, n), do: call(id, "callback_work", %{n: n})

  defp request(server, context),
    do:
      Request.create_and_send(server, "Work",
        signal_type: "ai.ask",
        source: "/examples/callbacks",
        context: context,
        stream_to: self()
      )

  defp record(server, request), do: Server.agent(server).state.requests[request.id]

  defp tool_value(request, id) do
    message = Enum.find(request.body["messages"], &(&1["tool_call_id"] == id))
    Jason.decode!(message["content"])
  end

  defp counter, do: start_supervised!({Elixir.Agent, fn -> %{} end})

  defp source do
    {_, options} = Enum.find(Agent.definition().plugins, &(elem(&1, 0) == Jido.AI.Runtime.Plugin))
    Map.from_struct(options[:profiles].assistant)
  end

  defp base do
    %{
      name: "tool_callback_example",
      module: Agent,
      vsn: Agent.vsn(),
      schema: Agent.domain_schema(),
      plugins: [JidoAI.Examples.ToolEffects.Observer],
      routes: [{"ai.ask", Authoring.ai(:assistant)}]
    }
  end

  defp start(jido, changes) do
    assert {:ok, definition} = Authoring.lower(base(), [Map.merge(source(), changes)])
    start_agent(jido, Jido.Agent.instantiate!(definition))
  end

  @tag history_case: "HIST-09/alias-round-trip"
  test "aliases reach the model and restore original keys before validation and real tool execution",
       %{jido: jido} do
    {mock, context} =
      mock([
        %{reply: {:tools, [call("list", "list_items", %{})]}},
        %{reply: {:tools, [call("use", "consume_item", %{key: "item-1"})]}},
        %{reply: {:wait, :answer, {:text, "Used item"}}}
      ])

    server = start_agent(jido, Agent.new!())
    assert {:ok, request} = request(server, context)
    assert_receive {:consumed, key}, 2_000
    assert key == ListItems.key()
    assert_receive {:mock_llm_waiting, ^mock, :answer, _}, 2_000
    assert Server.agent(server).state.aliases == %{}
    [_, second, third] = MockLLM.report(mock).requests
    assert %{"result" => %{"items" => [%{"key" => "item-1"}]}} = tool_value(second, "list")
    assert %{"result" => %{"used" => ^key}} = tool_value(third, "use")
    assert_receive {:operation_checked, %{name: "consume_item", arguments: %{key: ^key}}}

    assert_receive {:callback_view, %{pending_tool_calls: [%{id: "list", status: :ok}]}, config,
                    %{
                      agent_state: %{aliases: %{"item-1" => ^key}},
                      state: %{aliases: %{"item-1" => ^key}}
                    }}

    assert config.effect_policy.allow == MapSet.new([Jido.AI.Effects.State])
    assert :ok = MockLLM.release(mock, :answer)
    assert {:ok, "Used item"} = Request.await(request)
    assert Server.agent(server).state.aliases == %{"item-1" => key}
    assert [%{id: "list"}, %{id: "use"}] = record(server, request).meta.tool_results
    assert_script_done(mock)
  end

  @tag history_case: "HIST-09/direct-action"
  test "the same Action consumes an original key through direct core Exec without AI callbacks",
       _ do
    assert {:ok, %{used: key}} =
             Jido.Exec.run(Consume, %{key: ListItems.key()}, %{observer: self()})

    assert key == ListItems.key()
    assert_receive {:consumed, ^key}
    refute_receive {:before_hook, _, _}, 20
    refute_receive {:after_hook, _, _, _}, 20
  end

  @tag history_case: "HIST-09/callback-order"
  test "public Agent callbacks run once around rewritten arguments and real retry attempts", %{
    jido: jido
  } do
    {mock, context} = mock([%{reply: {:tools, [work("retry", "4")]}}, %{reply: {:text, "Done"}}])
    context = Map.merge(context, %{counter: counter(), retry: true})
    server = start_agent(jido, PublicAgent.new!())
    assert {:ok, request} = PublicAgent.ask(server, "Work", context: context, stream_to: self())
    assert {:ok, "Done"} = PublicAgent.await(request)
    assert_receive {:before_hook, %{id: "retry", arguments: %{"n" => "4"}}, _}
    assert_receive {:tool_ran, 4, 1, _}
    assert_receive {:tool_ran, 4, 2, _}
    assert_receive {:after_hook, %{id: "retry", arguments: %{n: 4}}, {:ok, %{n: 4}, []}, _}
    refute_receive {:before_hook, _, _}, 20
    refute_receive {:after_hook, _, _, _}, 20

    assert [%{attempts: 2, result: {:ok, %{n: 104}, []}}] =
             record(server, request).meta.tool_results

    [_, last] = MockLLM.report(mock).requests
    assert %{"result" => %{"n" => 104}} = tool_value(last, "retry")
    assert_script_done(mock)
  end

  test "all operation checks see rewritten arguments before any batch tool starts", %{jido: jido} do
    {mock, context} = mock([%{reply: {:tools, [work("first", "1"), work("blocked", "2")]}}])
    server = start_agent(jido, Agent.new!())
    assert {:ok, request} = request(server, Map.merge(context, %{counter: counter(), deny_n: 2}))
    assert {:error, :operation_denied} = Request.await(request)
    assert_receive {:operation_checked, %{id: "first", arguments: %{n: 1}}}
    assert_receive {:operation_checked, %{id: "blocked", arguments: %{n: 2}}}
    refute_receive {:tool_ran, _, _, _}, 20
    assert_script_done(mock)
  end

  for mode <- [:error, :interrupt, :invalid, :raise, :throw, :exit, :id, :name, :target] do
    @tag history_case: "HIST-09/failures"
    test "before #{mode} fails without tool work or successful output", %{jido: jido} do
      {mock, context} = mock([%{reply: {:tools, [work("before", "1")]}}])
      server = start_agent(jido, Agent.new!())

      assert {:ok, request} =
               request(
                 server,
                 Map.merge(context, %{counter: counter(), before_mode: unquote(mode)})
               )

      assert {:error, reason} = Request.await(request)
      refute reason in [nil, :timeout]

      if unquote(mode) == :interrupt,
        do: assert(reason == {:interrupt, :approval_needed}),
        else: assert(inspect(reason) =~ "tool_interceptor")

      assert_receive {:before_hook, %{id: "before"}, _}
      refute_receive {:tool_ran, _, _, _}, 20
      refute_receive {:after_hook, _, _, _}, 20
      assert record(server, request).status == :failed
      assert Server.agent(server).state.reply == ""
      assert_script_done(mock)
    end
  end

  for mode <- [:error, :invalid, :raise, :throw, :exit] do
    @tag history_case: "HIST-09/failures"
    test "after #{mode} fails without reversing completed Action IO", %{jido: jido} do
      path = Path.join(System.tmp_dir!(), "jido-callback-#{System.unique_integer([:positive])}")
      on_exit(fn -> File.rm(path) end)
      {mock, context} = mock([%{reply: {:tools, [work("after", "1")]}}])

      context =
        Map.merge(context, %{counter: counter(), after_mode: unquote(mode), output_file: path})

      server = start_agent(jido, Agent.new!())
      assert {:ok, request} = request(server, context)
      assert {:error, reason} = Request.await(request)
      assert inspect(reason) =~ "tool_interceptor"
      assert_receive {:tool_ran, 1, 1, _}
      assert File.read!(path) == "Tool 1 ran"
      assert Server.agent(server).state.reply == ""
      assert_script_done(mock)
    end
  end

  test "an unknown tool cannot acquire an executable through the callback", %{jido: jido} do
    {mock, context} = mock([%{reply: {:tools, [call("unknown", "unknown_tool", %{})]}}])
    server = start_agent(jido, Agent.new!())
    assert {:ok, request} = request(server, context)
    assert {:error, _} = Request.await(request)
    refute_receive {:before_hook, _, _}, 20
    refute_receive {:after_hook, _, _, _}, 20
    assert_script_done(mock)
  end

  test "result callbacks wait for every concurrency chunk and run in model call order", %{
    jido: jido
  } do
    {mock, context} =
      mock([
        %{reply: {:tools, [work("a", "1"), work("b", "2"), work("c", "3")]}},
        %{reply: {:text, "Done"}}
      ])

    server = start_agent(jido, Agent.new!())

    assert {:ok, request} =
             request(server, Map.merge(context, %{counter: counter(), hold_ns: [1, 3]}))

    assert_receive {:tool_ran, 1, 1, first}, 2_000
    assert_receive {:tool_ran, 2, 1, second}, 2_000
    monitor = Process.monitor(second)
    assert_receive {:DOWN, ^monitor, :process, ^second, _}, 2_000
    refute_receive {:after_hook, _, _, _}, 20
    send(first, :release)
    assert_receive {:tool_ran, 3, 1, worker}, 2_000
    refute_receive {:after_hook, _, _, _}, 20
    send(worker, :release)
    assert {:ok, "Done"} = Request.await(request)

    for id <- ["a", "b", "c"] do
      assert_receive {:after_hook, %{id: actual_id}, {:ok, _, []}, _}
      assert actual_id == id
    end

    assert Enum.map(record(server, request).meta.tool_results, & &1.id) == ["a", "b", "c"]
    assert_script_done(mock)
  end

  @tag history_case: "HIST-09/effects"
  test "callback effects are filtered before staging and transformer views retain completed output",
       %{jido: jido} do
    {mock, context} =
      mock([
        %{reply: {:tools, [work("effect", "7")]}},
        %{reply: {:wait, :answer, {:text, "Done"}}}
      ])

    context =
      Map.merge(context, %{
        counter: counter(),
        add_effects: true,
        effect_policy: %{mode: :allow_all}
      })

    server = start_agent(jido, Agent.new!())
    assert {:ok, request} = request(server, context)
    assert_receive {:mock_llm_waiting, ^mock, :answer, _}, 2_000

    assert_receive {:callback_view, %{pending_tool_calls: [%{id: "effect", result: {:ok, %{n: 107}, [_]}}]}, config,
                    %{state: %{count: 7}, agent_state: %{count: 7}}}

    assert config.effect_policy.allow == MapSet.new([Jido.AI.Effects.State])
    assert Server.agent(server).state.count == 0
    assert :ok = MockLLM.release(mock, :answer)
    assert {:ok, "Done"} = Request.await(request)
    assert Server.agent(server).state.count == 7

    assert [%{effects: %{received_count: 2, allowed_count: 1, dropped_count: 1}}] =
             record(server, request).meta.tool_results

    refute_receive {:effect_committed, _, _}, 20
    assert_script_done(mock)
  end

  test "the result callback observes a final canonical tool error once after retries", %{
    jido: jido
  } do
    {mock, context} =
      mock([%{reply: {:tools, [work("error", "9")]}}, %{reply: {:text, "Handled"}}])

    server = start_agent(jido, PublicAgent.new!())

    assert {:ok, request} =
             PublicAgent.ask(server, "Work", context: Map.merge(context, %{counter: counter(), fail_always: true}))

    assert {:ok, "Handled"} = PublicAgent.await(request)
    assert_receive {:tool_ran, 9, 1, _}
    assert_receive {:tool_ran, 9, 2, _}
    assert_receive {:after_hook, %{id: "error"}, {:error, reason, []}, _}
    assert reason != nil
    refute_receive {:after_hook, _, _, _}, 20
    assert [%{attempts: 2, status: :error}] = record(server, request).meta.tool_results
    [_, last] = MockLLM.report(mock).requests
    assert %{"ok" => false} = tool_value(last, "error")
    assert_script_done(mock)
  end

  for stage <- [:before, :after] do
    test "cancelling a held #{stage} callback stops its core task and permits a later request", %{
      jido: jido
    } do
      {mock, context} = mock([%{reply: {:tools, [work("held", "2")]}}, %{reply: {:text, "Next"}}])
      context = Map.put(context, :counter, counter())
      server = start_agent(jido, Agent.new!())
      assert {:ok, request} = request(server, Map.put(context, :hold_hook, unquote(stage)))
      assert_receive {:hook_waiting, unquote(stage), worker}, 2_000
      monitor = Process.monitor(worker)
      assert :ok = Session.cancel(request)
      assert_receive {:DOWN, ^monitor, :process, ^worker, _}, 2_000
      assert {:error, :cancelled} = Request.await(request)
      assert {:ok, next} = request(server, context)
      assert {:ok, "Next"} = Request.await(next)
      assert Server.agent(server).state.count == 0
      assert_script_done(mock)
    end
  end

  test "a callback cannot extend the total request deadline", %{jido: jido} do
    {mock, context} = mock([%{reply: {:tools, [work("deadline", "1")]}}])
    server = start(jido, %{controls: Map.put(source().controls, :timeout, 500)})

    assert {:ok, request} =
             request(server, Map.merge(context, %{counter: counter(), hold_hook: :before}))

    assert_receive {:hook_waiting, :before, worker}, 2_000
    monitor = Process.monitor(worker)
    assert {:error, reason} = Request.await(request, timeout: 2_000)
    refute reason == :timeout
    assert_receive {:DOWN, ^monitor, :process, ^worker, _}, 2_000
    refute_receive {:tool_ran, _, _, _}, 20
    assert record(server, request).status == :failed
    assert_script_done(mock)
  end

  test "a callback's invalid arguments fail validation before controls or execution", %{
    jido: jido
  } do
    {mock, context} = mock([%{reply: {:tools, [work("invalid", "1")]}}])
    server = start_agent(jido, Agent.new!())

    assert {:ok, request} =
             request(
               server,
               Map.merge(context, %{counter: counter(), before_mode: :invalid_args})
             )

    assert {:error, _} = Request.await(request)
    assert_receive {:before_hook, %{id: "invalid"}, _}
    refute_receive {:operation_checked, _}, 20
    refute_receive {:tool_ran, _, _, _}, 20
    assert_script_done(mock)
  end

  test "a literal Flow tool keeps its executable identity through both callbacks", %{jido: jido} do
    flow = JidoAI.Examples.ToolCallbacks.WorkFlow.flow()
    tool = Enum.find(source().tools, &(&1.target == Work))
    server = start(jido, %{tools: [%{tool | target: flow}]})

    {mock, context} =
      mock([%{reply: {:tools, [work("flow", "5")]}}, %{reply: {:text, "Flow done"}}])

    assert {:ok, request} = request(server, Map.put(context, :counter, counter()))
    assert {:ok, "Flow done"} = Request.await(request)
    assert_receive {:before_hook, %{action_module: ^flow}, _}
    assert_receive {:after_hook, %{action_module: ^flow}, {:ok, %{n: 5}, []}, _}
    assert_receive {:tool_ran, 5, 1, _}
    [_, last] = MockLLM.report(mock).requests
    assert %{"result" => %{"n" => 105}} = tool_value(last, "flow")
    assert_script_done(mock)
  end

  test "DSL data Builder and source JSON execute the same explicit callback module", %{jido: jido} do
    source = source()
    assert source.tool_interceptor == Hooks
    assert {:ok, definition} = Authoring.lower(base(), [source])
    assert definition == Agent.definition()
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

    {mock, context} =
      mock(
        Enum.flat_map(1..4, fn n ->
          [%{reply: {:tools, [work("format-#{n}", "#{n}")]}}, %{reply: {:text, "Done"}}]
        end)
      )

    context = Map.put(context, :counter, counter())

    for {definition, n} <- Enum.with_index([Agent.definition(), definition, built, decoded], 1) do
      server = start_agent(jido, Jido.Agent.instantiate!(definition))
      assert {:ok, request} = request(server, context)
      assert {:ok, "Done"} = Request.await(request)
      assert [%{result: {:ok, %{n: value}, []}}] = record(server, request).meta.tool_results
      assert value == n + 100
    end

    assert_script_done(mock)
  end

  test "invalid static callback references reject before Agent activation" do
    assert {:error, %{field: "tool_interceptor"}} =
             Jido.AI.Profile.new(%{source() | tool_interceptor: Work})

    assert {:error, %{field: "tool_interceptor"}} =
             Jido.AI.Profile.new(%{source() | tool_interceptor: "untrusted-module"})
  end

  test "a later result callback failure retains completed evidence but does not commit staged state",
       %{jido: jido} do
    {mock, context} = mock([%{reply: {:tools, [work("first", "1"), work("second", "2")]}}])
    server = start_agent(jido, Agent.new!())

    assert {:ok, request} =
             request(
               server,
               Map.merge(context, %{
                 counter: counter(),
                 fail_after_id: "second",
                 add_effects: true
               })
             )

    assert {:error, reason} = Request.await(request)
    assert inspect(reason) =~ "after_tool_call"
    assert_receive {:tool_ran, 1, 1, _}
    assert_receive {:tool_ran, 2, 1, _}

    assert [%{id: "first", result: {:ok, %{n: 101}, [_]}}] =
             record(server, request).meta.tool_results

    assert %{reply: "", count: 0} = Server.agent(server).state
    refute_receive {:effect_committed, _, _}, 20
    assert_script_done(mock)
  end

  test "callbacks receive trusted request and Agent identity despite caller context", %{
    jido: jido
  } do
    {mock, context} =
      mock([%{reply: {:tools, [work("identity", "8")]}}, %{reply: {:text, "Done"}}])

    instance = Agent.new!()
    server = start_agent(jido, instance)

    context =
      Map.merge(context, %{
        counter: counter(),
        request_id: "forged",
        run_id: "forged",
        agent_module: Work,
        state: %{forged: true},
        effect_policy: %{mode: :allow_all}
      })

    assert {:ok, request} = request(server, context)
    assert {:ok, "Done"} = Request.await(request)
    stored = record(server, request)

    for stage <- [:before, :after] do
      assert_receive {:hook_context, ^stage, view}
      assert view.request_id == request.id
      assert view.run_id == stored.run_id
      assert view.agent_id == instance.id
      assert view.agent_module == Agent
      assert view.state.count == 0
      refute Map.has_key?(view.state, :forged)
      assert view.effect_policy.allow == MapSet.new([Jido.AI.Effects.State])
    end

    assert_script_done(mock)
  end

  test "one-Turn Agents use the same callbacks and commit their allowed state", %{jido: jido} do
    {mock, context} = mock([%{reply: {:tools, [work("turn", "6")]}}, %{reply: {:text, "Done"}}])
    server = start(jido, %{requests: %{mode: :turn}})
    context = Map.merge(context, %{counter: counter(), add_effects: true})

    assert {:ok, %{state: %{reply: "Done", count: 6}}} =
             Server.call(
               server,
               Jido.Signal.new!("ai.ask", %{query: "Work"}, source: "/examples/callbacks"),
               context: context
             )

    assert_receive {:after_hook, %{id: "turn"}, {:ok, %{n: 6}, []}, _}
    refute_receive {:effect_committed, _, _}, 20
    [_, last] = MockLLM.report(mock).requests
    assert %{"result" => %{"n" => 106}} = tool_value(last, "turn")
    assert_script_done(mock)
  end

  defp atoms(%_{}), do: []
  defp atoms(map) when is_map(map), do: Enum.flat_map(map, fn {k, v} -> atoms(k) ++ atoms(v) end)
  defp atoms(list) when is_list(list), do: Enum.flat_map(list, &atoms/1)
  defp atoms(value) when is_tuple(value), do: value |> Tuple.to_list() |> atoms()
  defp atoms(atom) when is_atom(atom), do: [atom]
  defp atoms(_), do: []
end
