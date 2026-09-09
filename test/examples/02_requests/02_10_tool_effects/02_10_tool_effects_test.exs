defmodule JidoAI.Examples.ToolEffectsTest do
  use JidoAI.Examples.Case
  @moduletag history_case: "API/effect-policy"
  alias Jido.AI.{Authoring, Request, Session}
  alias JidoAI.Examples.ToolEffects.Agent

  defp source do
    {_, options} = Enum.find(Agent.definition().plugins, &(elem(&1, 0) == Jido.AI.Runtime.Plugin))
    Map.from_struct(options[:profiles].assistant)
  end

  defp base do
    %{
      name: "effects_source",
      schema: Agent.domain_schema(),
      plugins: [JidoAI.Examples.ToolEffects.Observer, Jido.Plugin.Dispatch, Jido.Plugin.Scheduler],
      routes: [
        {"ai.ask", Authoring.ai(:assistant)},
        {"effects.change", JidoAI.Examples.ToolEffects.Change},
        {"effects.tick", JidoAI.Examples.ToolEffects.Tick}
      ]
    }
  end

  defp start(jido, changes \\ %{}) do
    {:ok, definition} = Authoring.lower(base(), [Map.merge(source(), changes)])
    start_agent(jido, Jido.Agent.instantiate!(definition))
  end

  defp call(id, kind, value \\ 1, field \\ :count),
    do: %{id: id, name: "change_case", arguments: %{kind: kind, value: value, field: field}}

  defp request(server, context),
    do:
      Request.create_and_send(server, "Work",
        signal_type: "ai.ask",
        source: "/examples/effects",
        context: context,
        stream_to: self()
      )

  defp change(server, field, value),
    do:
      Server.call(
        server,
        Jido.Signal.new!("effects.change", %{field: field, value: value}, %{
          source: "/examples/effects"
        })
      )

  defp record(server, request), do: Server.agent(server).state.requests[request.id]

  test "state and directives commit after the final answer and preserve unrelated changes", %{
    jido: jido
  } do
    {mock, context} =
      mock([
        %{reply: {:tools, [call("set", "set", 5)]}},
        %{reply: {:wait, :answer, {:text, "Done"}}}
      ])

    server = start(jido)
    assert {:ok, request} = request(server, context)
    assert_receive {:mock_llm_waiting, ^mock, :answer, _}, 2_000
    assert Server.agent(server).state.count == 0
    refute_receive {:effect_committed, _, _}, 20
    assert {:ok, _} = change(server, :label, "outside")
    MockLLM.release(mock, :answer)
    assert {:ok, "Done"} = Request.await(request)

    assert_receive {:effect_committed, "count", %{count: 5, label: "outside", reply: "Done"}},
                   2_000

    assert [%{effects: %{received_count: 2, allowed_count: 2, dropped_count: 0}}] =
             record(server, request).meta.tool_results

    assert :ok = Jido.Action.validate_static_data(Server.agent(server).state)
    assert_script_done(mock)
  end

  test "the next model tool round receives the candidate state before its commit", %{jido: jido} do
    {mock, context} =
      mock([
        %{reply: {:tools, [call("set", "set", 7)]}},
        %{reply: {:tools, [call("read", "read")]}},
        %{reply: {:wait, :answer, {:text, "Read seven"}}}
      ])

    server = start(jido)
    assert {:ok, request} = request(server, context)
    assert_receive {:effect_tool, _, %{kind: "read"}, %{count: 7}}, 2_000
    assert_receive {:mock_llm_waiting, ^mock, :answer, _}, 2_000
    assert Server.agent(server).state.count == 0
    [_, _, last] = MockLLM.report(mock).requests
    message = Enum.find(last.body["messages"], &(&1["tool_call_id"] == "read"))
    assert %{"ok" => true, "result" => %{"count" => 7}} = Jason.decode!(message["content"])
    MockLLM.release(mock, :answer)
    assert {:ok, "Read seven"} = Request.await(request)
    assert_receive {:effect_committed, "count", %{count: 7}}
    assert_script_done(mock)
  end

  test "parallel proposals merge different fields in call order despite reversed completion", %{
    jido: jido
  } do
    {mock, context} =
      mock([
        %{reply: {:tools, [call("a", "hold", 3), call("b", "hold", 4, :label)]}},
        %{reply: {:text, "Done"}}
      ])

    server = start(jido)
    assert {:ok, request} = request(server, context)
    assert_receive {:effect_tool, a, %{field: :count}, _}, 2_000
    assert_receive {:effect_tool, b, %{field: :label}, _}, 2_000
    send(b, :release)
    assert_receive {:jido_ai_request_event, %{kind: :tool_completed, tool_call_id: "b"}}, 2_000
    send(a, :release)
    assert {:ok, "Done"} = Request.await(request)
    assert_receive {:effect_committed, "count", %{count: 3, label: "4"}}, 2_000
    assert_receive {:effect_committed, "label", %{count: 3, label: "4"}}, 2_000
    assert_script_done(mock)
  end

  test "parallel writes to the same field fail without candidate state or directive commit", %{
    jido: jido
  } do
    {mock, context} = mock([%{reply: {:tools, [call("a", "set", 3), call("b", "set", 4)]}}])
    server = start(jido)
    assert {:ok, request} = request(server, context)
    assert {:error, {:tool_state_conflict, [:count]}} = Request.await(request)
    assert Server.agent(server).state.count == 0
    refute_receive {:effect_committed, _, _}, 20
    assert length(record(server, request).meta.tool_results) == 2
    assert_script_done(mock)
  end

  test "an intervening write to a proposed field fails final assembly without overwriting it", %{
    jido: jido
  } do
    {mock, context} =
      mock([
        %{reply: {:tools, [call("set", "set", 5)]}},
        %{reply: {:wait, :answer, {:text, "Done"}}}
      ])

    server = start(jido)
    assert {:ok, request} = request(server, context)
    assert_receive {:mock_llm_waiting, ^mock, :answer, _}, 2_000
    assert {:ok, _} = change(server, :count, 9)
    MockLLM.release(mock, :answer)
    assert {:error, {:tool_state_conflict, [:count]}} = Request.await(request)
    assert %{count: 9, reply: ""} = Server.agent(server).state
    refute_receive {:effect_committed, _, _}, 20
    assert_script_done(mock)
  end

  for kind <- ["protected", "invalid_state", "invalid_directive"] do
    test "#{kind} proposal fails before the next model call and preserves committed state", %{
      jido: jido
    } do
      {mock, context} = mock([%{reply: {:tools, [call("bad", unquote(kind))]}}])
      server = start(jido)
      assert {:ok, request} = request(server, context)
      assert {:error, reason} = Request.await(request)
      assert reason != nil
      assert_receive {:effect_tool, _, %{kind: kind}, _}
      assert kind == unquote(kind)
      assert %{count: 0, reply: ""} = Server.agent(server).state
      assert record(server, request).status == :failed
      refute Map.has_key?(Server.agent(server).state.requests, "forged")
      refute_receive {:effect_committed, _, _}, 20
      assert_script_done(mock)
    end
  end

  test "cancellation discards candidate state and post-commit work", %{jido: jido} do
    {mock, context} =
      mock([
        %{reply: {:tools, [call("set", "set", 5)]}},
        %{reply: {:wait, :answer, {:text, "Done"}}}
      ])

    server = start(jido)
    assert {:ok, request} = request(server, context)
    assert_receive {:mock_llm_waiting, ^mock, :answer, _}, 2_000
    assert :ok = Session.cancel(request)
    assert {:error, :cancelled} = Request.await(request)
    assert %{count: 0, reply: ""} = Server.agent(server).state
    refute_receive {:effect_committed, _, _}, 20
    assert [%{id: "set"}] = record(server, request).meta.tool_results
    assert MockLLM.report(mock).remaining == []
  end

  test "reasoning policy can narrow the Agent policy and records dropped effects", %{jido: jido} do
    {mock, context} =
      mock([%{reply: {:tools, [call("set", "set", 5)]}}, %{reply: {:text, "Done"}}])

    reasoning = Map.put(source().reasoning, :effect_policy, %{allow: [Jido.AI.Effects.State]})
    server = start(jido, %{reasoning: reasoning})
    assert {:ok, request} = request(server, Map.put(context, :effect_policy, %{mode: :allow_all}))
    assert {:ok, "Done"} = Request.await(request)
    assert Server.agent(server).state.count == 5
    refute_receive {:effect_committed, _, _}, 20

    assert [
             %{
               effects: %{received_count: 2, allowed_count: 1, dropped_count: 1},
               result: {:ok, _, [%{type: :state, values: %{count: 5}, deleted_keys: []}]}
             }
           ] = record(server, request).meta.tool_results

    assert_script_done(mock)
  end

  test "reasoning policy and caller context cannot broaden a denied Agent policy", %{jido: jido} do
    {mock, context} =
      mock([%{reply: {:tools, [call("set", "set", 5)]}}, %{reply: {:text, "Done"}}])

    server = start(jido, %{effect_policy: %{mode: :deny_all}})
    assert {:ok, request} = request(server, Map.put(context, :effect_policy, %{mode: :allow_all}))
    assert {:ok, "Done"} = Request.await(request)
    assert Server.agent(server).state.count == 0
    refute_receive {:effect_committed, _, _}, 20

    assert [%{effects: %{allowed_count: 0, dropped_count: 2}}] =
             record(server, request).meta.tool_results

    assert_script_done(mock)
  end

  test "an error with returned effects is not retried and keeps the model error envelope", %{
    jido: jido
  } do
    {mock, context} =
      mock([%{reply: {:tools, [call("error", "error", 2)]}}, %{reply: {:text, "Handled"}}])

    tools = Enum.map(source().tools, &Map.put(&1, :max_retries, 3))
    server = start(jido, %{tools: tools})
    assert {:ok, request} = request(server, context)
    assert {:ok, "Handled"} = Request.await(request)
    assert_receive {:effect_tool, _, %{kind: "error"}, _}
    refute_receive {:effect_tool, _, _, _}, 20
    assert_receive {:effect_committed, "count", %{count: 2}}, 2_000
    assert [%{attempts: 1, status: :error}] = record(server, request).meta.tool_results
    [_, last] = MockLLM.report(mock).requests
    tool = Enum.find(last.body["messages"], &(&1["role"] == "tool"))
    assert %{"ok" => false} = Jason.decode!(tool["content"])
    assert_script_done(mock)
  end

  test "one-Turn mode returns the shared Flow candidate and directives through core commit", %{
    jido: jido
  } do
    {mock, context} =
      mock([
        %{reply: {:tools, [call("set", "set", 6)]}},
        %{reply: {:wait, :answer, {:text, "Done"}}}
      ])

    server = start(jido, %{requests: %{mode: :turn}})
    task = Task.async(fn -> ask(server, context) end)
    assert_receive {:mock_llm_waiting, ^mock, :answer, _}, 2_000
    assert Server.agent(server).state.count == 0
    refute_receive {:effect_committed, _, _}, 20
    MockLLM.release(mock, :answer)
    assert {:ok, %{state: %{count: 6, reply: "Done"}}} = Task.await(task)
    assert_receive {:effect_committed, "count", %{count: 6, reply: "Done"}}, 2_000
    assert_script_done(mock)
  end

  test "the core Dispatch Plugin delivers only after the final commit", %{jido: jido} do
    {mock, context} =
      mock([
        %{reply: {:tools, [call("emit", "emit", 5)]}},
        %{reply: {:wait, :answer, {:text, "Done"}}}
      ])

    server = start(jido)
    assert {:ok, request} = request(server, context)
    assert_receive {:mock_llm_waiting, ^mock, :answer, _}, 2_000
    refute_receive {:signal, _}, 20
    MockLLM.release(mock, :answer)
    assert {:ok, "Done"} = Request.await(request)
    assert_receive {:signal, %Jido.Signal{type: "effects.tick", data: %{value: 5}}}, 2_000
    assert Server.agent(server).state.count == 5
    assert_script_done(mock)
  end

  test "output rejection discards accepted tool state and directives", %{jido: jido} do
    {mock, context} =
      mock([%{reply: {:tools, [call("set", "set", 5)]}}, %{reply: {:text, "Reject"}}])

    server =
      start(jido, %{
        controls: Map.put(source().controls, :output, [JidoAI.Examples.ToolEffects.Reject])
      })

    assert {:ok, request} = request(server, context)
    assert {:error, :fixture_output_rejected} = Request.await(request)
    assert %{count: 0, reply: ""} = Server.agent(server).state
    refute_receive {:effect_committed, _, _}, 20
    assert_script_done(mock)
  end

  test "a later provider error discards state and effects but keeps completed tool evidence", %{
    jido: jido
  } do
    {mock, context} =
      mock([%{reply: {:tools, [call("set", "set", 5)]}}, %{reply: {:error, 503, "Unavailable"}}])

    server = start(jido)
    assert {:ok, request} = request(server, context)
    assert {:error, _} = Request.await(request)
    assert %{count: 0, reply: ""} = Server.agent(server).state

    assert [%{id: "set", effects: %{allowed_count: 2}}] =
             record(server, request).meta.tool_results

    refute_receive {:effect_committed, _, _}, 20
    assert_script_done(mock)
  end

  test "core dispatch constraints filter signals after tool completion", %{jido: jido} do
    {mock, context} =
      mock([%{reply: {:tools, [call("emit", "emit", 5)]}}, %{reply: {:text, "Done"}}])

    policy =
      Map.put(source().effect_policy, :constraints, %{
        emit: %{allowed_signal_prefixes: ["allowed."], allowed_dispatches: [:pid]}
      })

    server = start(jido, %{effect_policy: policy})
    assert {:ok, request} = request(server, context)
    assert {:ok, "Done"} = Request.await(request)
    assert Server.agent(server).state.count == 5

    assert [%{effects: %{allowed_count: 1, dropped_count: 1}}] =
             record(server, request).meta.tool_results

    refute_receive {:signal, _}, 20
    assert_script_done(mock)
  end

  test "the core Scheduler owns delayed work and starts it only after final commit", %{jido: jido} do
    {mock, context} =
      mock([
        %{reply: {:tools, [call("schedule", "schedule", 0)]}},
        %{reply: {:wait, :answer, {:text, "Done"}}}
      ])

    policy = Map.put(source().effect_policy, :constraints, %{schedule: %{max_delay_ms: 0}})
    server = start(jido, %{effect_policy: policy})
    assert {:ok, request} = request(server, context)
    assert_receive {:mock_llm_waiting, ^mock, :answer, _}, 2_000
    assert Server.agent(server).state.ticks == 0
    MockLLM.release(mock, :answer)
    assert {:ok, "Done"} = Request.await(request)
    assert await_tick(server, System.monotonic_time(:millisecond) + 2_000) == 1

    assert [%{effects: %{allowed_count: 2, dropped_count: 0}}] =
             record(server, request).meta.tool_results

    assert_script_done(mock)
  end

  test "schedule delay constraints reject work outside the allowed delay", %{jido: jido} do
    {mock, context} =
      mock([%{reply: {:tools, [call("schedule", "schedule", 10)]}}, %{reply: {:text, "Done"}}])

    policy = Map.put(source().effect_policy, :constraints, %{schedule: %{max_delay_ms: 0}})
    server = start(jido, %{effect_policy: policy})
    assert {:ok, request} = request(server, context)
    assert {:ok, "Done"} = Request.await(request)
    assert %{count: 10, ticks: 0} = Server.agent(server).state

    assert [
             %{
               effects: %{allowed_count: 1, dropped_count: 1},
               result: {:ok, _, [%{type: :state, values: %{count: 10}, deleted_keys: []}]}
             }
           ] = record(server, request).meta.tool_results

    assert_script_done(mock)
  end

  test "DSL data Builder and source JSON retain the same effect policy and execute it", %{
    jido: jido
  } do
    source = source()
    assert {:ok, definition} = Authoring.lower(base(), [source])
    assert definition.routes == Agent.definition().routes
    attrs = definition |> Map.from_struct() |> Map.drop([:id, :state])
    assert {:ok, ^definition} = attrs |> Jido.Agent.Builder.new() |> Jido.Agent.Builder.build()
    # The host assigns IDs to known atoms and the static model record.
    registry =
      source
      |> Map.put(:routes, [])
      |> atoms()
      |> Kernel.++(profile_atoms(source))
      |> Enum.uniq()
      |> Map.new(&{"atoms/#{&1}", {:atom, &1}})

    registry =
      registry
      |> Map.put("models/answer", {:value, source.models.answer.model})

    assert {:ok, document} = Authoring.Codec.encode([source], registry)

    assert {:ok, ^definition} =
             Authoring.Codec.decode(base(), Jason.decode!(Jason.encode!(document)), registry)

    {mock, context} =
      mock([%{reply: {:tools, [call("set", "set", 8)]}}, %{reply: {:text, "Imported"}}])

    server = start_agent(jido, Jido.Agent.instantiate!(definition))
    assert {:ok, request} = request(server, context)
    assert {:ok, "Imported"} = Request.await(request)
    assert_receive {:effect_committed, "count", %{count: 8, reply: "Imported"}}, 2_000
    assert_script_done(mock)
  end

  test "live directive targets do not convert a portable tool value into display data", %{
    jido: jido
  } do
    {mock, context} =
      mock([%{reply: {:tools, [call("content", "content", 5)]}}, %{reply: {:text, "Done"}}])

    server = start(jido)
    assert {:ok, request} = request(server, context)
    assert {:ok, "Done"} = Request.await(request)
    assert_receive {:effect_committed, "count", %{count: 5}}, 2_000

    assert [
             %{
               result_storage: :transport,
               result:
                 {:ok,
                  %ReqLLM.ToolResult{
                    output: %{value: 5},
                    content: [%ReqLLM.Message.ContentPart{text: "Tool content"}]
                  }, effects}
             }
           ] = record(server, request).meta.tool_results

    assert :ok = Jido.Action.validate_static_data(effects)
    [_, last] = MockLLM.report(mock).requests
    tool = Enum.find(last.body["messages"], &(&1["role"] == "tool"))
    assert [%{"type" => "text"}, %{"type" => "text", "text" => "Tool content"}] = tool["content"]
    assert_script_done(mock)
  end

  test "public Agent effect options use the same policy and keep existing request tuples", %{
    jido: jido
  } do
    old = Application.fetch_env(:jido_ai, :model_aliases)
    Application.put_env(:jido_ai, :model_aliases, %{example: MockLLM.model()})

    on_exit(fn ->
      case old do
        {:ok, value} -> Application.put_env(:jido_ai, :model_aliases, value)
        :error -> Application.delete_env(:jido_ai, :model_aliases)
      end
    end)

    {mock, context} =
      mock([
        %{reply: {:tools, [%{id: "public", name: "public_effect", arguments: %{}}]}},
        %{reply: {:text, "Done"}}
      ])

    module = JidoAI.Examples.ToolEffects.PublicAgent
    server = start_agent(jido, module.new!())
    assert {:ok, request} = module.ask(server, "Work", context: context)
    assert {:ok, "Done"} = module.await(request)
    assert Server.agent(server).state.model == :changed
    refute_receive {:effect_committed, _, _}, 20

    assert [%{effects: %{allowed_count: 1, dropped_count: 1}}] =
             record(server, request).meta.tool_results

    assert_script_done(mock)
  end

  for outcome <- [:deny, :output_reject] do
    @tag :tmp_dir
    @tag history_case: "HIST-08/tool-io-effects"
    test "direct file IO remains after #{outcome} while state and directives do not commit", %{
      jido: jido,
      tmp_dir: dir
    } do
      path = Path.join(dir, "tool.txt")

      {mock, context} =
        mock([%{reply: {:tools, [call("file", "file", 5)]}}, %{reply: {:text, "Done"}}])

      changes =
        if unquote(outcome) == :deny,
          do: %{effect_policy: %{mode: :deny_all}},
          else: %{
            controls: Map.put(source().controls, :output, [JidoAI.Examples.ToolEffects.Reject])
          }

      server = start(jido, changes)
      assert {:ok, request} = request(server, Map.put(context, :effect_file, path))

      expected =
        if unquote(outcome) == :deny, do: {:ok, "Done"}, else: {:error, :fixture_output_rejected}

      assert Request.await(request) == expected
      assert File.read!(path) == "Tool side effect"
      assert Server.agent(server).state.count == 0
      refute_receive {:effect_committed, _, _}, 20
      assert_script_done(mock)
    end
  end

  defp atoms(%_{}), do: []
  defp atoms(map) when is_map(map), do: Enum.flat_map(map, fn {k, v} -> atoms(k) ++ atoms(v) end)
  defp atoms(list) when is_list(list), do: Enum.flat_map(list, &atoms/1)
  defp atoms(value) when is_tuple(value), do: value |> Tuple.to_list() |> atoms()
  defp atoms(value) when is_atom(value), do: [value]
  defp atoms(_), do: []

  defp await_tick(server, deadline) do
    ticks = Server.agent(server).state.ticks

    if ticks == 0 and System.monotonic_time(:millisecond) < deadline do
      Process.sleep(10)
      await_tick(server, deadline)
    else
      ticks
    end
  end
end
