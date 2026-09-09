defmodule JidoAI.Examples.ToTAPITest do
  use JidoAI.Examples.Case
  alias Jido.AI.Request
  alias Jido.AI.Reasoning.TreeOfThoughts, as: Method
  alias JidoAI.Examples.{ToT, ToTAPI}
  alias JidoAI.Examples.ToolCallbacks.{ListItems, Consume}

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
    {_, config} = Enum.find(module.definition().plugins, &(elem(&1, 0) == Jido.AI.Runtime.Plugin))
    config[:profiles].assistant
  end

  defp native_definition(changes) do
    base = %{
      name: "tree_aliases",
      module: ToTAPI.Aliases,
      schema: ToTAPI.Aliases.domain_schema(),
      routes: [{"ai.tot.query", Jido.AI.Authoring.ai(:assistant)}]
    }

    Jido.AI.Authoring.lower(base, [Map.merge(Map.from_struct(profile(ToTAPI.Aliases)), changes)])
  end

  defp record(server, handle), do: Server.agent(server).state.requests[handle.id]
  defp counter, do: start_supervised!({Elixir.Agent, fn -> %{} end})
  defp work(id, n), do: %{id: id, name: "callback_work", arguments: %{n: n}}

  defp events(handle),
    do: handle |> Request.Stream.events(stream_event_timeout_ms: 1_000) |> Enum.to_list()

  defp tool_value(request, id) do
    request.body["messages"]
    |> Enum.find(&(&1["tool_call_id"] == id))
    |> Map.fetch!("content")
    |> Jason.decode!()
  end

  test "public options retain search defaults and provider generation defaults", %{jido: jido} do
    opts = ToTAPI.Default.strategy_opts()
    assert opts[:model] == :example and opts[:tools] == []
    assert opts[:branching_factor] == 3 and opts[:max_depth] == 3
    assert opts[:traversal_strategy] == :best_first and opts[:top_k] == 3
    assert opts[:min_depth] == 2 and opts[:max_nodes] == 100
    assert opts[:max_duration_ms] == nil and opts[:beam_width] == nil
    assert opts[:early_success_threshold] == 1.0 and opts[:convergence_window] == 2
    assert opts[:min_score_improvement] == 0.02 and opts[:max_parse_retries] == 1
    assert opts[:max_tool_round_trips] == 3
    assert opts[:tool_timeout_ms] == 15_000 and opts[:tool_max_retries] == 1
    assert opts[:tool_retry_backoff_ms] == 200
    assert ToTAPI.Default.description() == "ToT agent default_tree"
    assert profile(ToTAPI.Default).controls.max_iterations == 802
    assert profile(ToTAPI.Default).controls.max_tool_calls == 10_000
    refute profile(ToTAPI.Default).requests.steering
    assert profile(ToTAPI.Default).memory.history == nil
    {mock, context} = mock(ToT.script())
    server = start_agent(jido, ToTAPI.Public.new!())
    assert {:ok, result} = ToTAPI.Public.explore_sync(server, "Route", context: context)
    assert ToTAPI.Public.best_answer(result) == "Better path"

    for wire <- MockLLM.report(mock).requests do
      assert wire.body["max_tokens"] == 1024 and wire.body["temperature"] == 0.2
    end

    assert_script_done(mock)
  end

  test "public helpers retain separate results and current pending state", %{jido: jido} do
    {mock, context} =
      mock(
        ToT.script() ++
          [
            %{reply: {:wait, :next_tree, {:text, ToT.thoughts(["Next answer"])}}},
            %{reply: {:text, ToT.scores(%{t1: 0.9})}}
          ]
      )

    server = start_agent(jido, ToTAPI.Public.new!())
    assert Method.get_result(Server.agent(server)) == nil
    assert Method.get_nodes(Server.agent(server)) == %{}
    assert {:ok, first} = ToTAPI.Public.explore(server, "First", context: context)
    assert {:ok, result} = ToTAPI.Public.await(first)
    agent = Server.agent(server)
    assert Method.method() == :tree_of_thoughts
    assert Method.get_result(agent, first.id) == result
    assert map_size(Method.get_nodes(agent)) == 3
    assert Method.get_best_node(agent).content == "Better path"
    assert Method.get_solution_path(agent) == result.best.path_ids
    assert ToTAPI.Public.top_candidates(result, 1) == [result.best]
    assert ToTAPI.Public.result_summary(result).best_answer == "Better path"

    assert ToTAPI.Public.result_summary(nil) == %{
             best_answer: nil,
             top_candidates: [],
             tree: %{},
             termination: %{}
           }

    assert ToTAPI.Public.best_answer(nil) == nil and ToTAPI.Public.top_candidates(nil) == []

    assert agent.state.last_prompt == "First" and agent.state.last_result == result and
             agent.state.completed

    adapter = apply(Method, :strategy_module, [])
    assert Code.ensure_loaded?(adapter)

    for fun <- [:get_nodes, :get_best_node, :get_solution_path, :get_result] do
      assert apply(adapter, fun, [agent]) == apply(Method, fun, [agent])
    end

    assert Method.get_result(agent, "missing") == nil
    assert Method.get_nodes(agent, "missing") == %{}
    assert String.starts_with?(Method.generate_call_id(), "tot_")
    assert Method.default_generation_prompt() == Method.Machine.default_generation_prompt()
    assert Method.default_evaluation_prompt() == Method.Machine.default_evaluation_prompt()
    assert {:ok, next} = ToTAPI.Public.explore(server, "Next", context: context)
    assert_receive {:mock_llm_waiting, ^mock, :next_tree, _}, 2_000
    pending = Server.agent(server)
    assert pending.state.last_prompt == "Next" and pending.state.last_result == nil
    refute pending.state.completed
    assert Method.get_result(pending) == nil and Method.get_nodes(pending) == %{}
    assert Method.get_result(pending, first.id) == result
    assert :ok = MockLLM.release(mock, :next_tree)
    assert {:ok, %{best: %{content: "Next answer"}}} = ToTAPI.Public.await(next)
    assert length(Enum.at(MockLLM.report(mock).requests, 2).body["messages"]) == 2
    assert_script_done(mock)
  end

  test "custom public settings reach non-streaming generation and evaluation", %{jido: jido} do
    {mock, context} = mock(ToT.script())
    server = start_agent(jido, ToTAPI.Custom.new!())
    assert {:ok, result} = ToTAPI.Custom.explore_sync(server, "Custom", context: context)
    assert length(result.candidates) == 1 and result.best.content == "First path"
    assert ToTAPI.Custom.description() == "Custom search"

    assert ToTAPI.Custom.strategy_opts()[:agent_effect_policy] == %{
             allow: [Jido.AI.Effects.State]
           }

    assert ToTAPI.Custom.strategy_opts()[:strategy_effect_policy] == %{mode: :allow_all}
    [generation, evaluation] = MockLLM.report(mock).requests
    assert hd(generation.body["messages"])["content"] == "Generate one approach"
    assert hd(evaluation.body["messages"])["content"] == "Score the approach"

    for wire <- [generation, evaluation] do
      assert wire.body["max_tokens"] == 99 and wire.body["temperature"] == 0.4
      refute wire.body["stream"]
    end

    assert_script_done(mock)
  end

  test "public search duration retains its provider timeout and permits an explicit override", %{
    jido: jido
  } do
    assert profile(ToTAPI.Timed).models.answer.generation[:receive_timeout] == 100
    assert profile(ToTAPI.TimeoutOverride).models.answer.generation[:receive_timeout] == 250

    {mock, context} =
      mock([
        %{reply: {:stream, [{:wait, :timed_tree}, %{content: ToT.thoughts(["Late"])}], "stop"}}
      ])

    context =
      put_in(
        context.ai.assistant.options,
        Keyword.delete(context.ai.assistant.options, :receive_timeout)
      )

    server = start_agent(jido, ToTAPI.Timed.new!())
    assert {:ok, handle} = ToTAPI.Timed.explore(server, "Wait", context: context)
    assert_receive {:mock_llm_waiting, ^mock, :timed_tree, provider}, 2_000
    monitor = Process.monitor(provider)
    assert {:error, {:failed, _, result}} = ToTAPI.Timed.await(handle, timeout: 1_500)
    assert result.termination.status == "error"
    assert_receive {:DOWN, ^monitor, :process, ^provider, _}, 2_000
    assert Process.alive?(server) and record(server, handle).status == :failed
    assert Method.get_result(Server.agent(server), handle.id) == result
    assert_script_done(mock)
  end

  test "failed public search retains its explored nodes and canonical result", %{jido: jido} do
    {mock, context} =
      mock(ToT.script() ++ [%{reply: {:text, "invalid"}}, %{reply: {:text, "invalid again"}}])

    server = start_agent(jido, ToTAPI.Default.new!())
    assert {:ok, handle} = ToTAPI.Default.explore(server, "Explore", context: context)

    assert {:error, {:failed, {:parse_failed, :generation, :thoughts_parse_failed}, result}} =
             ToTAPI.Default.await(handle)

    agent = Server.agent(server)
    assert Method.get_result(agent, handle.id) == result
    assert agent.state.last_result == result and agent.state.completed
    assert map_size(Method.get_nodes(agent, handle.id)) == 3
    assert Method.get_best_node(agent).content == "Better path"
    assert Method.get_solution_path(agent) == []
    assert result.usage.total_tokens == 60
    assert_script_done(mock)
  end

  test "ToT getters reject actual results from another reasoning method", %{jido: jido} do
    {mock, context} = mock([%{reply: {:text, "answer: different"}}])
    server = start_agent(jido, JidoAI.Examples.AoT.Public.new!())
    assert {:ok, handle} = JidoAI.Examples.AoT.Public.explore(server, "Other", context: context)
    assert {:ok, _} = Request.await(handle)
    agent = Server.agent(server)
    assert Method.get_result(agent, handle.id) == nil and Method.get_result(agent) == nil
    assert Method.get_nodes(agent) == %{} and Method.get_best_node(agent) == nil
    assert_script_done(mock)
  end

  @tag history_case: "HIST-09/alias-round-trip"
  test "ToT aliases reach the model and restore original keys before Action validation", %{
    jido: jido
  } do
    {mock, context} =
      mock([
        %{reply: {:tools, [%{id: "list", name: "list_items", arguments: %{}}]}},
        %{reply: {:tools, [%{id: "use", name: "consume_item", arguments: %{key: "item-1"}}]}},
        hd(ToT.script()),
        %{reply: {:wait, :alias_score, {:text, ToT.scores(%{t1: 0.4, t2: 0.8})}}}
      ])

    server = start_agent(jido, ToTAPI.Aliases.new!())

    assert {:ok, handle} =
             Request.create_and_send(server, "Use an item",
               signal_type: "ai.tot.query",
               source: "/examples/tot-api",
               context: context,
               stream_to: self()
             )

    assert_receive {:consumed, key}, 2_000
    assert key == ListItems.key()
    assert_receive {:after_hook, %{id: "list"}, {:ok, %{items: [%{key: ^key}]}, []}, _}
    assert_receive {:operation_checked, %{id: "use", arguments: %{key: ^key}}}
    assert_receive {:mock_llm_waiting, ^mock, :alias_score, _}, 2_000
    assert Server.agent(server).state.aliases == %{}
    [_, second, third, _] = MockLLM.report(mock).requests

    assert tool_value(second, "list") == %{
             "ok" => true,
             "result" => %{"items" => [%{"key" => "item-1"}]}
           }

    assert tool_value(third, "use") == %{"ok" => true, "result" => %{"used" => key}}
    assert :ok = MockLLM.release(mock, :alias_score)
    assert {:ok, result} = Request.await(handle)
    assert result.best.content == "Better path" and result.usage.total_tokens == 60
    assert Server.agent(server).state.aliases == %{"item-1" => key}

    assert [%{id: "list", result: {:ok, %{items: [%{key: "item-1"}]}, [_]}}, %{id: "use"}] =
             record(server, handle).meta.tool_results

    assert_script_done(mock)
  end

  test "the alias Actions retain original-key behavior under direct core Exec", _ do
    assert {:ok, %{items: [%{key: key}]}} = Jido.Exec.run(ListItems, %{}, %{observer: self()})
    assert {:ok, %{used: ^key}} = Jido.Exec.run(Consume, %{key: key}, %{observer: self()})
    refute_receive {:before_hook, _, _}, 20
    refute_receive {:after_hook, _, _, _}, 20
  end

  test "public callbacks receive the raw final retry result and transform the next model input",
       %{jido: jido} do
    {mock, context} = mock([%{reply: {:tools, [work("retry", "4")]}}] ++ ToT.script())
    server = start_agent(jido, ToTAPI.Public.new!())
    context = Map.merge(context, %{counter: counter(), retry: true})

    assert {:ok, handle} =
             ToTAPI.Public.explore(server, "Work",
               context: context,
               stream_to: self(),
               tool_context: %{
                 origin_label: "request",
                 agent_id: "forged",
                 agent_module: __MODULE__
               }
             )

    assert {:ok, _} = ToTAPI.Public.await(handle)
    assert_receive {:tot_public_context, "retry", callback_context}
    assert callback_context.origin_label == "request"
    assert callback_context.agent_id == Server.agent(server).id
    assert callback_context.agent_module == ToTAPI.Public
    assert callback_context.request_id == handle.id
    assert callback_context.run_id == record(server, handle).run_id
    assert callback_context.agent_state.last_prompt == ""
    assert Server.agent(server).state.last_prompt == "Work"
    assert_receive {:before_hook, %{id: "retry", arguments: %{"n" => "4"}}, _}
    assert_receive {:tool_ran, 4, 1, _}
    assert_receive {:tool_ran, 4, 2, _}
    assert_receive {:after_hook, %{id: "retry", arguments: %{n: 4}}, {:ok, %{n: 4}, []}, _}
    refute_receive {:before_hook, _, _}, 20
    refute_receive {:after_hook, _, _, _}, 20

    assert [%{id: "retry", attempts: 2, result: {:ok, %{n: 104}, []}}] =
             record(server, handle).meta.tool_results

    assert tool_value(Enum.at(MockLLM.report(mock).requests, 1), "retry") == %{
             "ok" => true,
             "result" => %{"n" => 104}
           }

    assert [%{data: %{result: {:ok, %{n: 104}, []}}}] =
             Enum.filter(events(handle), &(&1.kind == :tool_completed))

    assert_script_done(mock)
  end

  for mode <- [:error, :interrupt, :invalid, :raise, :throw, :exit, :id, :name, :target] do
    test "ToT before #{mode} fails before tool execution", %{jido: jido} do
      {mock, context} = mock([%{reply: {:tools, [work("before", "1")]}}])
      server = start_agent(jido, ToTAPI.Public.new!())
      context = Map.merge(context, %{counter: counter(), before_mode: unquote(mode)})
      assert {:ok, handle} = ToTAPI.Public.explore(server, "Work", context: context)
      assert {:error, {:failed, reason, result}} = ToTAPI.Public.await(handle)
      assert reason != nil and result.termination.reason == :error
      assert result.usage.total_tokens == 15
      assert_receive {:before_hook, %{id: "before"}, _}
      refute_receive {:tool_ran, _, _, _}, 20
      refute_receive {:after_hook, _, _, _}, 20
      assert Server.agent(server).state.last_result == result
      assert_script_done(mock)
    end
  end

  for mode <- [:error, :invalid, :raise, :throw, :exit] do
    test "ToT after #{mode} keeps a failed search after actual tool work", %{jido: jido} do
      {mock, context} = mock([%{reply: {:tools, [work("after", "1")]}}])
      server = start_agent(jido, ToTAPI.Public.new!())
      context = Map.merge(context, %{counter: counter(), after_mode: unquote(mode)})

      assert {:ok, handle} =
               ToTAPI.Public.explore(server, "Work", context: context, stream_to: self())

      assert {:error, {:failed, reason, result}} = ToTAPI.Public.await(handle)
      assert inspect(reason) =~ "tool_interceptor"
      assert_receive {:tool_ran, 1, 1, _}
      assert Elixir.Agent.get(context.counter, & &1) == %{1 => 1}
      assert Server.agent(server).state.last_result == result
      assert List.last(events(handle)).kind == :request_failed
      assert_script_done(mock)
    end
  end

  test "public cancellation keeps its reason and a fresh search can start", %{jido: jido} do
    {mock, context} = mock([%{reply: {:stream, [{:wait, :cancel_tree}], "stop"}}] ++ ToT.script())
    server = start_agent(jido, ToTAPI.Public.new!())
    assert {:ok, handle} = ToTAPI.Public.explore(server, "Wait", context: context)
    assert_receive {:mock_llm_waiting, ^mock, :cancel_tree, provider}, 2_000
    monitor = Process.monitor(provider)
    assert {:error, _} = ToTAPI.Public.explore(server, "Busy", context: context)
    assert :ok = ToTAPI.Public.cancel(server, request_id: handle.id, reason: :changed_task)
    assert {:error, {:cancelled, :changed_task}} = ToTAPI.Public.await(handle)
    assert_receive {:DOWN, ^monitor, :process, ^provider, _}, 2_000

    assert {:ok, %{best: %{content: "Better path"}}} =
             ToTAPI.Public.explore_sync(server, "Next", context: context)

    assert_script_done(mock)
  end

  test "the public search budget permits more than ten model calls within method limits", %{
    jido: jido
  } do
    script =
      for {text, phase} <- [
            {ToT.thoughts(["Path"]), 0},
            {ToT.scores(%{t1: 0.8}), 1},
            {ToT.thoughts(["Solved"]), 2},
            {ToT.scores(%{t1: 1.0}), 3}
          ],
          reduce: [] do
        acc ->
          acc ++
            for(n <- 1..3, do: %{reply: {:tools, [work("round-#{phase}-#{n}", phase * 3 + n)]}}) ++
            [%{reply: {:text, text}}]
      end

    {mock, context} = mock(script)
    server = start_agent(jido, ToTAPI.Deep.new!())

    assert {:ok, handle} =
             ToTAPI.Deep.explore(server, "Deep", context: Map.put(context, :counter, counter()))

    assert {:ok, result} = ToTAPI.Deep.await(handle)
    assert result.best.content == "Solved" and result.termination.reason == :threshold
    assert record(server, handle).meta.model_calls == 16
    assert record(server, handle).meta.tool_calls == 12
    assert result.usage.total_tokens == 240
    assert_script_done(mock)
  end

  test "a later ToT result callback failure keeps completed tool evidence without committing effects",
       %{jido: jido} do
    {mock, context} = mock([%{reply: {:tools, [work("first", "1"), work("second", "2")]}}])

    assert {:ok, definition} =
             native_definition(%{
               tools: [
                 %{
                   name: "callback_work",
                   target: JidoAI.Examples.ToolCallbacks.Work,
                   forward_context: :all
                 }
               ]
             })

    server = start_agent(jido, Jido.Agent.instantiate!(definition))

    context =
      Map.merge(context, %{counter: counter(), add_effects: true, fail_after_id: "second"})

    assert {:ok, handle} =
             Request.create_and_send(server, "Work",
               signal_type: "ai.tot.query",
               source: "/examples/tot-api",
               context: context,
               stream_to: self()
             )

    assert {:error, {:failed, reason, _}} = Request.await(handle)
    assert inspect(reason) =~ "after_tool_call"
    assert_receive {:tool_ran, 1, 1, _}
    assert_receive {:tool_ran, 2, 1, _}

    assert [%{id: "first", result: {:ok, %{n: 101}, [_]}}] =
             record(server, handle).meta.tool_results

    assert Server.agent(server).state.count == 0 and Server.agent(server).state.reply == nil
    assert List.last(events(handle)).kind == :request_failed
    assert_script_done(mock)
  end

  test "a denied ToT alias-state effect cannot make a short key valid", %{jido: jido} do
    {mock, context} =
      mock([
        %{reply: {:tools, [%{id: "list", name: "list_items", arguments: %{}}]}},
        %{reply: {:tools, [%{id: "use", name: "consume_item", arguments: %{key: "item-1"}}]}}
      ])

    assert {:ok, definition} = native_definition(%{effect_policy: %{allow: []}})
    server = start_agent(jido, Jido.Agent.instantiate!(definition))

    assert {:ok, handle} =
             Request.create_and_send(server, "Use",
               signal_type: "ai.tot.query",
               source: "/examples/tot-api",
               context: context
             )

    assert {:error, {:failed, _, _}} = Request.await(handle)
    assert_receive {:listed, _}
    refute_receive {:consumed, _}, 20
    assert Server.agent(server).state.aliases == %{} and Server.agent(server).state.reply == nil

    assert [%{id: "list", result: {:ok, _, []}, effects: %{dropped_count: 1}}] =
             record(server, handle).meta.tool_results

    assert_script_done(mock)
  end

  test "an ordinary Agent turn uses the same ToT alias callbacks and complete state commit", %{
    jido: jido
  } do
    {mock, context} =
      mock(
        [
          %{reply: {:tools, [%{id: "list", name: "list_items", arguments: %{}}]}},
          %{reply: {:tools, [%{id: "use", name: "consume_item", arguments: %{key: "item-1"}}]}}
        ] ++ ToT.script()
      )

    assert {:ok, definition} = native_definition(%{requests: %{mode: :turn}})
    server = start_agent(jido, Jido.Agent.instantiate!(definition))
    signal = Jido.Signal.new!("ai.tot.query", %{query: "Use"}, source: "/examples/tot-api")
    assert {:ok, agent} = Server.call(server, signal, context: context, timeout: 5_000)
    assert agent.state.reply.best.content == "Better path"
    assert agent.state.aliases == %{"item-1" => ListItems.key()}
    assert_receive {:consumed, _}
    assert_script_done(mock)
  end
end
