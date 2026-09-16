defmodule JidoAI.Examples.AdaptiveTest do
  use JidoAI.Examples.Case
  alias Jido.AI.Authoring
  alias Jido.AI.Request
  alias Jido.AI.Orchestration
  alias Jido.AI.Reasoning.Adaptive.Selection
  alias JidoAI.Examples.Adaptive

  defp start(jido, changes \\ %{}) do
    assert {:ok, definition} = Adaptive.definition(changes)
    start_agent(jido, Jido.Agent.instantiate!(definition))
  end

  defp request(server, context, query \\ "Improve the answer"),
    do:
      Request.create_and_send(server, query,
        signal_type: "ai.adaptive.query",
        source: "/examples/adaptive",
        context: context,
        stream_to: self()
      )

  defp record(server, handle), do: Server.agent(server).state.requests[handle.id]

  defp events(handle),
    do: handle |> Request.Stream.events(stream_event_timeout_ms: 1_000) |> Enum.to_list()

  defp answer(:aot, result), do: result.answer
  defp answer(:tot, result), do: Jido.AI.Reasoning.TreeOfThoughts.Result.best_answer(result)
  defp answer(_, result), do: result

  for {method, prompt, settings, expected} <- [
        {:cod, "What is two plus two?", %{}, "Four"},
        {:cot, "What is two plus two?", %{available_strategies: [:cot]}, "Four"},
        {:react, "Search for the answer", %{}, "Four"},
        {:aot, "Explore the options", %{available_strategies: [:aot, :tot]}, "(4 + (8 - 6)) * 4 = 24"},
        {:tot, "Explore the options", %{}, "Better path"},
        {:got, "Combine these perspectives", %{}, "Combined conclusion"},
        {:trm, "Improve this answer", %{}, "Unreviewed improvement"}
      ] do
    test "automatic #{method} selection executes the actual method without an extra model call",
         %{jido: jido} do
      method = unquote(method)
      {mock, context} = mock(Adaptive.script(method))
      server = start(jido, Adaptive.options(unquote(Macro.escape(settings))))
      assert {:ok, handle} = request(server, context, unquote(prompt))
      assert {:ok, result} = Request.await(handle)
      assert answer(method, result) == unquote(expected)
      assert Server.agent(server).state.reply == result
      data = record(server, handle)
      assert data.method == :adaptive
      assert data.meta.adaptive.strategy == method
      assert data.meta.adaptive.source == :automatic
      assert is_float(data.meta.adaptive.complexity_score)
      assert data.meta.model_calls == length(Adaptive.script(method))
      assert data.meta.usage.total_tokens == length(Adaptive.script(method)) * 15
      selected = data.meta.adaptive.method
      calls = Enum.filter(events(handle), &(&1.kind == :llm_completed))
      assert Enum.all?(calls, &(&1.method == :adaptive and &1.data.selected_method == selected))

      if method not in [:react, :tot] do
        for wire <- MockLLM.report(mock).requests, do: refute(Map.has_key?(wire.body, "tools"))
      end

      assert_script_done(mock)
    end
  end

  test "one Agent selects again after completion and preserves each method's result and metadata",
       %{jido: jido} do
    {mock, context} =
      mock(Adaptive.script(:cod) ++ Adaptive.script(:trm) ++ Adaptive.script(:got))

    server = start(jido)
    assert {:ok, first} = request(server, context, "What is two plus two?")
    assert {:ok, "Four"} = Request.await(first)
    old = record(server, first)
    assert {:ok, next} = request(server, context, "Improve the answer")
    assert {:ok, "Unreviewed improvement"} = Request.await(next)
    assert record(server, next).meta.reasoning.trm.supervision_step == 1
    assert {:ok, last} = request(server, context, "Combine perspectives")
    assert {:ok, "Combined conclusion"} = Request.await(last)
    assert record(server, first) == old
    assert record(server, last).meta.adaptive.strategy == :got
    assert record(server, last).meta.reasoning.graph.usage.total_tokens == 45
    assert_script_done(mock)
  end

  test "an explicit method override wins over keywords and preserves neutral selection metadata",
       %{jido: jido} do
    {mock, context} = mock(Adaptive.script(:cot))
    server = start(jido, Adaptive.options(%{strategy_override: :cot}))
    assert {:ok, handle} = request(server, context, "Improve and synthesize this puzzle")
    assert {:ok, "Four"} = Request.await(handle)

    assert record(server, handle).meta.adaptive == %{
             strategy: :cot,
             method: :chain_of_thought,
             complexity_score: 0.5,
             task_type: :manual_override,
             source: :override
           }

    assert_script_done(mock)
  end

  test "invalid available methods overrides thresholds and method options fail before model work" do
    {mock, _} = mock([])

    for opts <- [
          %{available_strategies: []},
          %{available_strategies: [:unknown]},
          %{available_strategies: [:cot, :cot]},
          %{strategy_override: :unknown},
          %{available_strategies: [:cot], strategy_override: :trm},
          %{complexity_thresholds: %{simple: 0.8, complex: 0.2}},
          %{complexity_thresholds: %{simple: -0.1}},
          %{complexity_thresholds: %{complex: "0.7"}},
          %{method_options: %{tot: %{max_depth: 0}}},
          %{method_options: %{unknown: %{}}},
          %{unknown: true}
        ] do
      assert {:error, _} = Adaptive.definition(Adaptive.options(opts))
    end

    assert_script_done(mock)
  end

  test "selected ReAct executes a real Action through the common tool path", %{jido: jido} do
    {mock, context} =
      mock([
        %{reply: {:tools, [%{id: "actual_work", name: "tree_work", arguments: %{n: 4}}]}},
        %{reply: {:text, "Work complete"}}
      ])

    server = start(jido)
    assert {:ok, handle} = request(server, context, "Use the tool")
    assert {:ok, "Work complete"} = Request.await(handle)
    assert record(server, handle).meta.adaptive.strategy == :react
    assert record(server, handle).meta.tool_calls == 1
    tool_events = Enum.filter(events(handle), &(&1.kind in [:tool_started, :tool_completed]))
    assert length(tool_events) == 2
    assert Enum.all?(tool_events, &(&1.data.selected_method == :react))
    assert Enum.find(tool_events, &(&1.kind == :tool_completed)).data.result == {:ok, %{n: 4}, []}
    assert_script_done(mock)
  end

  test "selected TRM failures retain selection phase data and usage and permit another choice", %{
    jido: jido
  } do
    {mock, context} =
      mock(
        Enum.take(Adaptive.script(:trm), 2) ++
          [%{reply: {:stream, [], "length"}}] ++ Adaptive.script(:cod)
      )

    server = start(jido)
    assert {:ok, handle} = request(server, context, "Improve the answer")
    assert {:error, {:failed, {:incomplete_response, :length}, result}} = Request.await(handle)
    assert result.adaptive.strategy == :trm and result.diagnostics.phase == :improvement
    assert result.trm.best_answer == "First answer" and result.usage.total_tokens == 45
    assert Server.agent(server).state.reply == nil
    assert {:ok, next} = request(server, context, "What is two plus two?")
    assert {:ok, "Four"} = Request.await(next)
    assert record(server, next).meta.adaptive.strategy == :cod
    assert_script_done(mock)
  end

  test "selection retains task precedence and threshold fallback with bounded scores" do
    assert {:trm, score, :iterative_reasoning} =
             Selection.analyze_prompt("Improve and combine the tool results")

    assert score >= 0 and score <= 1
    assert {:got, _, :synthesis} = Selection.analyze_prompt("Combine tool results")

    assert {:cot, _, :tool_use} =
             Selection.analyze_prompt("Search", %{available_strategies: [:cot]})

    assert {:react, _, _} = Selection.analyze_prompt("", %{available_strategies: []})
    # Legacy inert analysis keeps that fallback. Profile validation rejects the empty set.
    assert {:error, _} = Adaptive.definition(Adaptive.options(%{available_strategies: []}))
  end

  test "custom thresholds change the selected method at the actual provider", %{jido: jido} do
    {mock, context} = mock(Adaptive.script(:react))
    server = start(jido, Adaptive.options(%{complexity_thresholds: %{simple: 0.0, complex: 1.0}}))
    assert {:ok, handle} = request(server, context, "Hello")
    assert {:ok, "Four"} = Request.await(handle)
    assert record(server, handle).meta.adaptive.strategy == :react
    assert record(server, handle).meta.adaptive.task_type == :general
    assert_script_done(mock)
  end

  test "selected ToT can run a tool before generation and evaluation", %{jido: jido} do
    {mock, context} =
      mock(
        [
          %{reply: {:tools, [%{id: "search_work", name: "tree_work", arguments: %{n: 8}}]}}
        ] ++ Adaptive.script(:tot)
      )

    server = start(jido)
    assert {:ok, handle} = request(server, context, "Explore the options")
    assert {:ok, result} = Request.await(handle)
    assert answer(:tot, result) == "Better path"
    assert record(server, handle).meta.tool_calls == 1
    assert record(server, handle).meta.model_calls == 3
    assert record(server, handle).meta.usage.total_tokens == 45
    assert record(server, handle).meta.adaptive.strategy == :tot
    all = events(handle)
    tool_events = Enum.filter(all, &(&1.kind in [:tool_started, :tool_completed]))
    assert Enum.all?(tool_events, &(&1.data.selected_method == :tree_of_thoughts))
    assert Enum.find(tool_events, &(&1.kind == :tool_completed)).data.result == {:ok, %{n: 8}, []}

    assert Enum.filter(all, &(&1.kind == :llm_completed)) |> Enum.map(& &1.data.reasoning_phase) ==
             [:generation, :generation, :evaluation]

    assert_script_done(mock)
  end

  test "a transformer cannot enable tools for a selected linear method", %{jido: jido} do
    {mock, context} =
      mock([%{reply: {:tools, [%{id: "forbidden", name: "tree_work", arguments: %{n: 4}}]}}])

    server =
      start(jido, %{
        reasoning:
          Map.put(
            Adaptive.source().reasoning,
            :request_transformer,
            JidoAI.Examples.ToT.Transform
          )
      })

    assert {:ok, handle} = request(server, context, "What is two plus two?")

    assert {:error, {:failed, {:unexpected_tool_calls, :chain_of_draft}, details}} =
             Request.await(handle)

    assert details.adaptive.strategy == :cod and details.usage.total_tokens == 15
    refute_receive {:tree_work, _, _}, 20
    [wire] = MockLLM.report(mock).requests
    refute Map.has_key?(wire.body, "tools")
    refute Map.has_key?(wire.body, "tool_choice")
    assert_script_done(mock)
  end

  test "typed output is checked against the selected method before model work", %{jido: jido} do
    {mock, context} = mock([%{reply: {:object, %{value: 4}}}])
    server = start(jido, %{result: %{schema: Zoi.object(%{value: Zoi.integer()}), into: :reply}})
    assert {:ok, unsupported} = request(server, context, "Improve this answer")
    assert {:error, reason} = Request.await(unsupported)
    assert inspect(reason) =~ "Typed TRM"
    assert MockLLM.report(mock).requests == []
    assert Server.agent(server).state.reply == nil
    assert {:ok, typed} = request(server, context, "What is two plus two?")
    assert {:ok, %{value: 4}} = Request.await(typed)
    assert record(server, typed).meta.adaptive.strategy == :cod
    [wire] = MockLLM.report(mock).requests
    assert Map.has_key?(wire.body, "response_format")
    refute Map.has_key?(wire.body, "tools")
    assert_script_done(mock)
  end

  test "selected AoT validates a typed answer inside its method result", %{jido: jido} do
    {mock, context} =
      mock([%{reply: {:text, "Searching the candidates.\nanswer: {\"value\":24}"}}])

    server =
      start(
        jido,
        Adaptive.options(%{available_strategies: [:aot]})
        |> Map.put(:result, %{schema: Zoi.object(%{value: Zoi.integer()}), into: :reply})
      )

    assert {:ok, handle} = request(server, context, "Explore these options")
    assert {:ok, result} = Request.await(handle)
    assert result.answer == %{value: 24}
    assert record(server, handle).meta.adaptive.strategy == :aot
    [wire] = MockLLM.report(mock).requests
    refute Map.has_key?(wire.body, "response_format")
    assert_script_done(mock)
  end

  test "common limits stop a selected TRM phase and preserve selection metadata", %{jido: jido} do
    {mock, context} = mock(Enum.take(Adaptive.script(:trm), 2))
    server = start(jido, %{controls: %{Adaptive.source().controls | max_model_calls: 2}})
    assert {:ok, handle} = request(server, context, "Improve the answer")
    assert {:error, {:failed, cause, details}} = Request.await(handle)
    assert inspect(cause) =~ "limit"
    assert details.adaptive.strategy == :trm and details.usage.total_tokens == 30
    assert details.trm.best_answer == "First answer"
    assert Server.agent(server).state.reply == nil
    assert_script_done(mock)
  end

  test "output control can reject the selected graph result without a domain write", %{jido: jido} do
    {mock, context} = mock(Adaptive.script(:got))
    server = start(jido)

    assert {:ok, handle} =
             request(server, Map.put(context, :reject, :unapproved), "Combine perspectives")

    assert {:error, {:failed, :unapproved, details}} = Request.await(handle)
    assert details.adaptive.strategy == :got
    assert details.result == "Combined conclusion"
    assert details.usage.total_tokens == 45 and Server.agent(server).state.reply == nil
    assert_script_done(mock)
  end

  test "cancellation keeps the selected method and usage and permits a different next method", %{
    jido: jido
  } do
    {mock, context} =
      mock(
        Enum.take(Adaptive.script(:trm), 2) ++
          [%{reply: {:stream, [{:wait, :adaptive_cancel}], "stop"}}] ++ Adaptive.script(:cod)
      )

    server = start(jido)
    assert {:ok, handle} = request(server, context, "Improve the answer")
    assert_receive {:mock_llm_waiting, ^mock, :adaptive_cancel, provider}, 2_000
    monitor = Process.monitor(provider)
    assert record(server, handle).status == :pending
    assert {:error, :busy} = request(server, context, "Busy")
    assert :ok = Orchestration.cancel(handle, reason: :changed_task)
    assert {:error, {:cancelled, :changed_task}} = Request.await(handle)
    assert_receive {:DOWN, ^monitor, :process, ^provider, _}, 2_000
    assert record(server, handle).meta.adaptive.strategy == :trm
    assert record(server, handle).meta.usage.total_tokens == 30
    assert {:ok, next} = request(server, context, "What is two plus two?")
    assert {:ok, "Four"} = Request.await(next)
    assert record(server, next).meta.adaptive.strategy == :cod
    assert_script_done(mock)
  end

  test "owner restart interrupts selected graph work and permits a fresh selection", %{jido: jido} do
    {mock, context} =
      mock(
        Enum.take(Adaptive.script(:got), 2) ++
          [%{reply: {:stream, [{:wait, :adaptive_owner}], "stop"}}] ++ Adaptive.script(:cod)
      )

    server = start(jido)
    assert {:ok, handle} = request(server, context, "Combine perspectives")
    assert_receive {:mock_llm_waiting, ^mock, :adaptive_owner, provider}, 2_000
    monitor = Process.monitor(provider)
    Process.exit(Server.children(server)[{:plugin, Orchestration.Plugin}].pid, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^provider, _}, 2_000
    assert {:error, :stream_interrupted} = Request.await(handle)
    assert {:ok, next} = request(server, context, "What is two plus two?")
    assert {:ok, "Four"} = Request.await(next)
    assert_script_done(mock)
  end

  test "the total deadline closes transport for a selected tree method", %{jido: jido} do
    {mock, context} = mock([%{reply: {:stream, [{:wait, :adaptive_deadline}], "stop"}}])
    server = start(jido, %{controls: %{Adaptive.source().controls | timeout: 400}})
    assert {:ok, handle} = request(server, context, "Explore options")
    assert_receive {:mock_llm_waiting, ^mock, :adaptive_deadline, provider}, 2_000
    monitor = Process.monitor(provider)
    assert {:error, _} = Request.await(handle, timeout: 3_000)
    assert_receive {:DOWN, ^monitor, :process, ^provider, _}, 2_000
    assert record(server, handle).meta.adaptive.strategy == :tot
    assert Server.agent(server).state.reply == nil
    assert_script_done(mock)
  end

  test "model Signals and telemetry carry the selected method with the outer Adaptive identity",
       %{jido: jido} do
    id = "adaptive_#{System.unique_integer([:positive])}"

    :ok =
      :telemetry.attach(
        id,
        [:jido, :ai, :llm, :complete],
        &JidoAI.Examples.Telemetry.handle/4,
        self()
      )

    on_exit(fn -> :telemetry.detach(id) end)
    {mock, context} = mock(Adaptive.script(:trm))
    server = start(jido)
    assert {:ok, handle} = request(server, context, "Improve the answer")
    assert {:ok, _} = Request.await(handle)
    all = events(handle)
    calls = Enum.filter(all, &(&1.kind == :llm_completed))
    assert length(calls) == 3 and length(Enum.uniq_by(calls, & &1.llm_call_id)) == 3

    for event <- calls do
      assert event.method == :adaptive and event.data.selected_method == :trm
      assert {:ok, [signal, _]} = Jido.AI.Signal.from_event(event)
      assert signal.data.metadata.selected_method == :trm
      call = event.llm_call_id

      assert_receive {:linear_telemetry, [:jido, :ai, :llm, :complete], _,
                      %{llm_call_id: ^call, strategy: :adaptive, selected_method: :trm}},
                     2_000
    end

    assert Enum.count(all, &Request.Stream.terminal_kind?(&1.kind)) == 1
    assert_script_done(mock)
  end

  test "ordinary core Actions remain available while a selected method is active", %{jido: jido} do
    {mock, context} =
      mock([%{reply: {:wait, :ordinary_action, {:text, "Short thought\nAnswer: Four"}}}])

    server = start(jido)
    assert {:ok, handle} = request(server, context, "What is two plus two?")
    assert_receive {:mock_llm_waiting, ^mock, :ordinary_action, _}, 2_000
    signal = Jido.Signal.new!("case.close", %{reason: "closed"}, source: "/examples/adaptive")
    assert {:ok, agent} = Server.call(server, signal)
    assert agent.state.case_id == "closed" and agent.state.requests[handle.id].status == :pending
    assert :ok = MockLLM.release(mock, :ordinary_action)
    assert {:ok, "Four"} = Request.await(handle)
    assert Server.agent(server).state.case_id == "closed"
    assert record(server, handle).meta.adaptive.strategy == :cod
    assert_script_done(mock)
  end

  test "typed answer repair keeps the selected AoT method through both model calls", %{jido: jido} do
    {mock, context} =
      mock([
        %{reply: {:text, "Trying a promising first operation:\nanswer: {\"value\":\"bad\"}"}},
        %{reply: {:text, "Trying another promising first operation:\nanswer: {\"value\":24}"}}
      ])

    server =
      start(
        jido,
        Adaptive.options(%{available_strategies: [:aot, :trm]})
        |> Map.put(:result, %{
          schema: Zoi.object(%{value: Zoi.integer()}),
          into: :reply,
          max_repairs: 1
        })
      )

    assert {:ok, handle} = request(server, context, "Explore the options")
    assert {:ok, result} = Request.await(handle)
    assert result.answer == %{value: 24}
    assert record(server, handle).meta.adaptive.strategy == :aot
    assert record(server, handle).meta.output.status == :repaired
    assert record(server, handle).meta.model_calls == 2
    assert record(server, handle).meta.usage.total_tokens == 30

    assert Enum.filter(events(handle), &(&1.kind == :llm_completed))
           |> Enum.all?(&(&1.data.selected_method == :algorithm_of_thoughts))

    for wire <- MockLLM.report(mock).requests,
        do: refute(Map.has_key?(wire.body, "response_format"))

    assert_script_done(mock)
  end

  test "rich queries and steering retain explicit native limits before model work", %{jido: jido} do
    {mock, context} = mock([])
    assert {:error, _} = Adaptive.definition(%{controls: %{steering: true}})
    server = start(jido)
    assert {:ok, handle} = request(server, context, [ReqLLM.Message.ContentPart.text("Rich")])
    assert {:error, reason} = Request.await(handle)
    assert inspect(reason) =~ "text query"
    assert Server.agent(server).state.reply == nil
    assert_script_done(mock)
  end

  test "DSL data Builder source JSON direct Flow and ordinary turns use the same adaptive contract",
       %{jido: jido} do
    {mock, context} = mock(List.duplicate(Adaptive.script(:trm), 6) |> List.flatten())
    source = Adaptive.source()
    assert {:ok, definition} = Adaptive.definition()
    assert definition == Adaptive.Agent.definition()
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
             Authoring.Codec.decode(
               Adaptive.base(),
               Jason.decode!(Jason.encode!(document)),
               registry
             )

    assert decoded == built and built == definition

    for value <- [Adaptive.Agent.definition(), definition, built, decoded] do
      server = start_agent(jido, Jido.Agent.instantiate!(value))
      assert {:ok, handle} = request(server, context)
      assert {:ok, "Unreviewed improvement"} = Request.await(handle)
      assert record(server, handle).meta.adaptive.strategy == :trm
    end

    assert {:ok, profile} = Jido.AI.Profile.new(source)
    assert {:ok, flow} = Authoring.reasoning_flow(profile)

    direct_context =
      Map.merge(context, %{agent_state: %{reply: nil}, jido_ai_profiles: %{assistant: profile}})

    assert {:ok, %{result: "Unreviewed improvement", meta: meta}} =
             Jido.Exec.run(flow, %{query: "Improve the answer"}, direct_context)

    assert meta.reasoning.trm.supervision_step == 1 and meta.adaptive.strategy == :trm
    server = start(jido)

    signal =
      Jido.Signal.new!("ai.adaptive.query", %{query: "Improve the answer"}, source: "/examples/adaptive")

    assert {:ok, agent} = Jido.AI.Test.Requests.call_and_await(server, signal, context: context, timeout: 5_000)
    assert agent.state.reply == "Unreviewed improvement"
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
