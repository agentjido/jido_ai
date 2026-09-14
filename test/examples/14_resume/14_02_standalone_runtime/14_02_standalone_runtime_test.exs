defmodule JidoAI.Examples.StandaloneRuntimeTest do
  use JidoAI.Examples.Case
  alias Jido.AI.Reasoning.ReAct
  alias ReAct.{Config, State, Token}
  alias JidoAI.Examples.StandaloneAuthoring.{Add, Change, Transform, Repair}
  alias JidoAI.Examples.StandaloneRuntime.Hold

  test "public start is lazy and its real Session keeps the supplied request and run IDs", %{
    jido: jido
  } do
    {mock, _} = mock([%{reply: {:text, "Ready"}}])
    config = config(mock)

    assert {:ok, started} =
             ReAct.start(
               "Start",
               config,
               opts(jido, request_id: "public-request", run_id: "public-run")
             )

    assert started.request_id == "public-request" and started.run_id == "public-run"
    assert MockLLM.report(mock).requests == []
    result = ReAct.collect_stream(started.events)
    assert result.result == "Ready" and result.termination_reason == :final_answer

    assert Enum.all?(
             result.trace,
             &(&1.request_id == started.request_id and &1.run_id == started.run_id)
           )

    assert Enum.map(result.trace, & &1.seq) == Enum.to_list(1..length(result.trace))
    assert {:ok, saved, _} = Token.decode_state(result.final_token, config)
    assert saved.status == :completed and saved.result == "Ready"
    assert saved.seq == List.last(result.trace).seq
    assert Enum.any?(saved.context.entries, &(&1.role == :assistant and &1.content == "Ready"))
    assert_script_done(mock)
  end

  test "public run executes real aliased tools and collects total usage and a terminal token", %{
    jido: jido
  } do
    {mock, _} =
      mock([
        %{reply: {:tools, [%{id: "sum-id", name: "sum", arguments: %{a: 4, b: 5}}]}},
        %{reply: {:text, "Nine"}}
      ])

    config = config(mock, tools: %{"sum" => Add})
    result = JidoAI.Examples.StandaloneRuntime.run("Sum", config, jido, self())
    assert result.result == "Nine" and result.usage.total_tokens == 30
    assert_receive {:standalone_add, _, 4, 5}
    assert Enum.count(result.trace, &(&1.kind == :tool_completed)) == 1
    assert List.last(result.trace).kind == :checkpoint
    assert {:ok, saved, _} = Token.decode_state(result.final_token, config)
    assert Enum.any?(saved.context.entries, &(&1.role == :tool and &1.tool_call_id == "sum-id"))
    assert_script_done(mock)
  end

  test "terminal collect and continue do not call the model again", %{jido: jido} do
    {mock, _} = mock([%{reply: {:text, "Saved"}}])
    config = config(mock)
    first = ReAct.run("Save", config, opts(jido))
    assert {:ok, view} = ReAct.collect(first.final_token, config, run_until_terminal?: false)
    assert view.result == "Saved" and view.trace == []
    assert {:ok, next} = ReAct.continue(first.final_token, config, opts(jido))
    second = ReAct.collect_stream(next.events)
    assert second.result == "Saved"
    assert Enum.map(second.trace, & &1.kind) == [:request_completed, :checkpoint]
    assert hd(second.trace).seq > List.last(first.trace).seq
    assert_script_done(mock)
  end

  test "a cancelled replacement token stays cancelled without runtime work", %{jido: jido} do
    {mock, _} = mock([])
    config = config(mock)
    token = State.new("Never run", nil) |> Token.issue(config)
    assert {:ok, cancelled} = ReAct.cancel(token, config, :user_stop)
    assert {:ok, next} = ReAct.continue(cancelled, config, opts(jido))
    result = ReAct.collect_stream(next.events)
    assert result.termination_reason == :cancelled
    assert {:ok, %{status: :cancelled}, _} = Token.decode_state(result.final_token, config)
    assert_script_done(mock)
  end

  test "real streamed deltas reach the public collector before its terminal token", %{jido: jido} do
    {mock, _} = mock([%{reply: {:stream, [%{content: "First "}, %{content: "second"}]}}])
    result = ReAct.run("Stream", config(mock, streaming: true), opts(jido))
    assert result.result == "First second"
    assert Enum.any?(result.trace, &(&1.kind == :llm_delta and &1.data.delta == "First "))
    assert Enum.map(Enum.take(result.trace, -2), & &1.kind) == [:request_completed, :checkpoint]
    assert_script_done(mock)
  end

  test "halting the public stream stops an active provider and its private Agent", %{jido: jido} do
    {mock, _} =
      mock([
        %{reply: {:stream, [%{content: "Part"}, {:wait, :consumer_halt}, %{content: "Unused"}]}}
      ])

    events = ReAct.stream("Halt", config(mock, streaming: true), opts(jido))
    owner = self()

    consumer =
      Task.async(fn ->
        Enum.reduce_while(events, [], fn event, seen ->
          if event.kind == :llm_delta do
            send(owner, {:delta_received, self()})

            receive do
              :halt -> {:halt, [event | seen]}
            end
          else
            {:cont, [event | seen]}
          end
        end)
      end)

    assert_receive {:delta_received, consumer_pid}, 2_000
    assert_receive {:mock_llm_waiting, ^mock, :consumer_halt, provider}, 2_000
    ref = Process.monitor(provider)
    send(consumer_pid, :halt)
    assert is_list(Task.await(consumer, 5_000))
    assert_receive {:DOWN, ^ref, :process, ^provider, _}, 2_000
    assert_script_done(mock)
  end

  test "consumer death stops a blocked tool and its linked Agent", %{jido: jido} do
    {mock, _} = mock([%{reply: {:tools, [%{id: "hold-id", name: "hold", arguments: %{}}]}}])
    config = config(mock, tools: [Hold])
    options = opts(jido)
    parent = self()

    {consumer, monitor} =
      spawn_monitor(fn ->
        result = ReAct.run("Hold", config, options)
        send(parent, {:consumer_result, result})
      end)

    assert_receive {:standalone_tool_waiting, tool, server}, 2_000
    tool_ref = Process.monitor(tool)
    server_ref = Process.monitor(server)
    assert Server.agent(server).state.requests |> Map.values() |> Enum.all?(&(&1.run_id != nil))
    Process.exit(consumer, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^consumer, :killed}
    assert_receive {:DOWN, ^tool_ref, :process, ^tool, _}, 2_000
    assert_receive {:DOWN, ^server_ref, :process, ^server, _}, 2_000
    assert_script_done(mock)
  end

  test "standalone state effects use the shared core state and next-request transformer", %{
    jido: jido
  } do
    {mock, _} =
      mock([
        %{reply: {:tools, [%{id: "count-id", name: "change", arguments: %{count: 7}}]}},
        %{reply: {:text, "Changed"}}
      ])

    config =
      config(mock,
        tools: [Change],
        request_transformer: Transform
      )

    result =
      ReAct.run(
        "Change",
        config,
        opts(jido, context: %{jido: jido, observer: self(), state: %{count: 0}})
      )

    assert result.result == "Changed"
    assert_receive {:standalone_count, 0}
    assert_receive {:standalone_count, 7}
    assert_script_done(mock)
  end

  test "standalone output repair uses the same callback as native Agent execution", %{jido: jido} do
    {mock, _} = mock([%{reply: {:text, "invalid"}}])

    config =
      config(mock,
        output: [
          schema: Zoi.object(%{answer: Zoi.string()}),
          repair_fun: {Repair, :fix},
          retries: 1
        ]
      )

    result = ReAct.run("Repair", config, opts(jido))
    assert result.result == %{answer: "Repaired"}
    assert_receive :standalone_repair
    assert_script_done(mock)
  end

  test "the legacy iteration limit result is retained after the final permitted tool round", %{
    jido: jido
  } do
    {mock, _} =
      mock([%{reply: {:tools, [%{id: "limit-add", name: "add", arguments: %{a: 1, b: 1}}]}}])

    config = config(mock, tools: [Add], max_iterations: 1)
    result = ReAct.run("Bound", config, opts(jido))
    assert result.termination_reason == :max_iterations
    assert result.result == "Maximum iterations reached without a final answer."
    assert_receive {:standalone_add, _, 1, 1}
    assert {:ok, resumed} = ReAct.continue(result.final_token, config, opts(jido))
    assert ReAct.collect_stream(resumed.events).termination_reason == :max_iterations
    assert_script_done(mock)
  end

  test "a rejected blank provider response keeps charged usage in the public result", %{
    jido: jido
  } do
    {mock, _} = mock([%{reply: {:stream, [], "length"}}])
    config = config(mock, streaming: true)
    result = ReAct.run("Incomplete", config, opts(jido))
    assert result.termination_reason == :failed
    refute Enum.any?(result.trace, &(&1.kind == :llm_completed))
    assert result.usage.total_tokens > 0
    assert {:ok, saved, _} = Token.decode_state(result.final_token, config)
    assert saved.usage == result.usage
    assert_script_done(mock)
  end

  test "normal loss of the private Agent terminates the public stream", %{jido: jido} do
    {mock, _} = mock([%{reply: {:tools, [%{id: "stop-hold", name: "hold", arguments: %{}}]}}])
    options = opts(jido)
    task = Task.async(fn -> ReAct.run("Stop", config(mock, tools: [Hold]), options) end)
    assert_receive {:standalone_tool_waiting, tool, server}, 2_000
    ref = Process.monitor(tool)
    Server.stop(server, :normal)
    result = Task.await(task, 2_000)
    assert result.termination_reason == :failed
    assert inspect(result.result) =~ "standalone_agent_stopped"
    assert_receive {:DOWN, ^ref, :process, ^tool, _}, 2_000
    assert_script_done(mock)
  end

  test "default native limits leave room for the configured long tool and stop the private Agent after success",
       %{jido: jido} do
    {mock, _} = mock([%{reply: {:tools, [%{id: "long-hold", name: "hold", arguments: %{}}]}}])
    config = config(mock, tools: [Hold], tool_timeout_ms: 90_000, max_iterations: 1)
    options = Keyword.delete(opts(jido), :limits)
    task = Task.async(fn -> ReAct.run("Long tool", config, options) end)
    assert_receive {:standalone_tool_waiting, tool, server}, 2_000
    assert {:ok, profile} = Jido.AI.Configuration.profile(Server.agent(server))
    assert profile.controls.timeout >= Config.stream_timeout(config)
    assert profile.controls.max_tool_calls == 16
    ref = Process.monitor(server)
    send(tool, :release)
    assert Task.await(task, 5_000).termination_reason == :max_iterations
    assert_receive {:DOWN, ^ref, :process, ^server, :normal}, 2_000
    assert_script_done(mock)
  end

  test "the supplied task supervisor owns only the stream adapter and is empty after completion",
       %{jido: jido} do
    {mock, _} = mock([%{reply: {:text, "Supervised"}}])
    supervisor = start_supervised!(Task.Supervisor)
    result = ReAct.run("Supervise", config(mock), opts(jido, task_supervisor: supervisor))
    assert result.result == "Supervised"
    assert Task.Supervisor.children(supervisor) == []
    assert_script_done(mock)
  end

  test "invalid run IDs fail before the provider and leave no private Agent work", %{jido: jido} do
    {mock, _} = mock([])
    config = config(mock)

    for id <- [nil, "", 42] do
      assert {:error, _} = ReAct.start("Bad ID", config, opts(jido, run_id: id))
    end

    assert_script_done(mock)
  end

  test "an untouched initial token starts through the real native runtime", %{jido: jido} do
    {mock, _} = mock([%{reply: {:text, "Started from data"}}])
    config = config(mock)

    token =
      State.new("Initial", nil, request_id: "initial-request", run_id: "initial-run")
      |> Token.issue(config)

    assert {:ok, started} = ReAct.continue(token, config, opts(jido))
    assert ReAct.collect_stream(started.events).result == "Started from data"
    assert_script_done(mock)
  end

  test "native tool bounds reject a whole batch before any side effect", %{jido: jido} do
    calls = for id <- ["one", "two"], do: %{id: id, name: "add", arguments: %{a: 1, b: 1}}
    {mock, _} = mock([%{reply: {:tools, calls}}])
    config = config(mock, tools: [Add])
    result = ReAct.run("Bound", config, opts(jido, limits: %{timeout: 5_000, max_tool_calls: 1}))
    assert result.termination_reason == :failed
    assert {:ok, %{status: :failed}, _} = Token.decode_state(result.final_token, config)
    refute_receive {:standalone_add, _, _, _}, 20
    assert_script_done(mock)
  end

  test "progressed state is refused before model work until the resume boundary is ported", %{
    jido: jido
  } do
    {mock, _} = mock([])
    config = config(mock)
    state = State.new("Resume", nil) |> State.inc_iteration()
    result = ReAct.stream_from_state(state, config, opts(jido)) |> ReAct.collect_stream()
    assert result.termination_reason == :failed
    assert inspect(result.result) =~ "checkpoint_phase_not_ported"
    assert_script_done(mock)
  end

  for {callback, before?, after?, sum} <- [
        {JidoAI.Examples.StandaloneRuntime.Before, true, false, 10},
        {JidoAI.Examples.StandaloneRuntime.After, false, true, 50},
        {JidoAI.Examples.StandaloneRuntime.Both, true, true, 100}
      ] do
    test "standalone context binds #{inspect(callback)} to the native tool profile", %{jido: jido} do
      call = %{id: "hook", name: "add", arguments: %{a: 2, b: 3}}
      {mock, _} = mock([%{reply: {:tools, [call]}}, %{reply: {:text, "Done"}}])
      config = config(mock, tools: [Add])

      result =
        ReAct.run(
          "Add",
          config,
          opts(jido,
            context: %{
              jido: jido,
              observer: self(),
              agent_module: unquote(callback)
            }
          )
        )

      assert result.result == "Done"

      if unquote(before?) do
        assert_receive {:standalone_before, %{id: "hook", action_module: Add, arguments: %{"a" => 2, "b" => 3}}}
      else
        refute_receive {:standalone_before, _}, 20
      end

      b = if unquote(before?), do: 8, else: 3
      assert_receive {:standalone_add, _, 2, ^b}
      raw_sum = 2 + b

      if unquote(after?) do
        assert_receive {:standalone_after, %{id: "hook", action_module: Add}, %{sum: ^raw_sum}}
      else
        refute_receive {:standalone_after, _, _}, 20
      end

      assert {:ok, %{sum: unquote(sum)}, []} =
               Enum.find(result.trace, &(&1.kind == :tool_completed)).data.result

      [_, final] = MockLLM.report(mock).requests
      [message] = Enum.filter(final.body["messages"], &(&1["role"] == "tool"))
      assert message["tool_call_id"] == "hook"

      assert Jason.decode!(message["content"]) == %{
               "ok" => true,
               "result" => %{"sum" => unquote(sum)}
             }

      assert {:ok, %{status: :completed}, _} = Token.decode_state(result.final_token, config)
      assert_script_done(mock)
    end
  end

  for {mode, reason} <- [
        {:error, {:request_transformer, :repair_credentials_unavailable}},
        {:invalid_messages, :invalid_request_messages}
      ] do
    test "standalone repair #{mode} retains its failure type and stops before another provider call",
         %{jido: jido} do
      {mock, _} = mock([%{reply: {:text, "Invalid"}}])

      config =
        config(mock,
          output: [schema: Zoi.object(%{answer: Zoi.string()})],
          request_transformer: JidoAI.Examples.StandaloneRuntime.RepairTransform
        )

      result =
        ReAct.run(
          "Repair",
          config,
          opts(jido, context: %{jido: jido, observer: self(), repair_mode: unquote(mode)})
        )

      assert result.termination_reason == :failed
      failed = Enum.find(result.trace, &(&1.kind == :request_failed))
      assert failed.data.error_type == :request_transform
      assert failed.data.error == unquote(Macro.escape(reason))
      assert Enum.count(result.trace, &(&1.kind == :output_failed)) == 1
      assert_receive {:standalone_repair_transform, :running, _}
      assert_receive {:standalone_repair_transform, :completed, _}
      assert {:ok, saved, _} = Token.decode_state(result.final_token, config)
      assert saved.error == unquote(Macro.escape(reason))
      assert saved.output.status == :error
      assert length(MockLLM.report(mock).requests) == 1
      assert_script_done(mock)
    end
  end

  test "standalone provider repair errors use the next attempt and keep portable checkpoints", %{
    jido: jido
  } do
    {mock, _} =
      mock([
        %{reply: {:text, "Invalid"}},
        %{reply: {:error, 503, "Temporary repair failure"}},
        %{reply: {:object, %{answer: "Recovered"}}}
      ])

    config =
      config(mock,
        output: [schema: Zoi.object(%{answer: Zoi.string()}), retries: 2],
        request_transformer: JidoAI.Examples.StandaloneRuntime.RepairTransform
      )

    result = ReAct.run("Repair", config, opts(jido))
    assert result.result == %{answer: "Recovered"}

    assert Enum.map(Enum.filter(result.trace, &(&1.kind == :output_repair)), & &1.data.attempt) ==
             [1, 2]

    assert_receive {:standalone_repair_transform, :running, _}
    assert_receive {:standalone_repair_transform, :completed, _}
    assert_receive {:standalone_repair_transform, :completed, _}
    refute_receive {:standalone_repair_transform, _, _}, 20
    assert {:ok, saved, _} = Token.decode_state(result.final_token, config)
    assert saved.status == :completed and saved.output.attempt == 2
    assert saved.checkpoint.runtime.model_calls == 3
    assert :ok = Jido.Action.validate_static_data(saved.checkpoint)
    refute inspect(saved.checkpoint, limit: :infinity) =~ "native-repair-key"
    assert result.usage.total_tokens == 30
    assert length(MockLLM.report(mock).requests) == 3
    assert_script_done(mock)
  end

  defp config(mock, extra \\ []) do
    options = Keyword.merge(MockLLM.options(mock), Keyword.get(extra, :llm_opts, []))
    assert URI.parse(options[:base_url]).host == "127.0.0.1"

    Config.new(
      Keyword.merge(
        [
          model: MockLLM.model(),
          streaming: false,
          tools: [],
          token_secret: "standalone-runtime-fixture"
        ],
        extra
      )
      |> Keyword.put(:llm_opts, options)
    )
  end

  defp opts(jido, extra \\ []),
    do:
      Keyword.merge(
        [context: %{jido: jido, observer: self()}, limits: %{timeout: 5_000, max_tool_calls: 32}],
        extra
      )
end
