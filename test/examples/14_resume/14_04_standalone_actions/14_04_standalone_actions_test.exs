defmodule JidoAI.Examples.StandaloneActionsTest do
  use JidoAI.Examples.Case
  alias Jido.AI.Reasoning.ReAct.Actions.{Start, Continue, Collect, Cancel, Helpers}
  alias Jido.AI.Reasoning.ReAct.Token
  alias JidoAI.Examples.CheckpointResume
  alias JidoAI.Examples.StandaloneActions, as: Example
  alias JidoAI.Examples.StandaloneAuthoring.Add

  test "Start and Collect execute real tools through Exec and retain the lazy public envelope", %{
    jido: jido
  } do
    {mock, _} = mock(tool_script())
    params = params(mock, %{request_id: "action-request", run_id: "action-run"})
    context = context(jido)
    assert {:ok, started} = Jido.Exec.run(Start, params, context)
    assert started.request_id == "action-request" and started.run_id == "action-run"
    assert started.checkpoint_token == nil
    assert MockLLM.report(mock).requests == []

    assert {:ok, result} =
             Jido.Exec.run(Collect, Map.put(params, :events, started.events), context)

    assert result.result == "Five" and result.usage.total_tokens == 30
    assert_receive {:standalone_add, _, 2, 3}

    assert {:ok, saved, _} =
             Token.decode_state(result.final_token, Helpers.build_config(params, context))

    assert saved.request_id == "action-request" and saved.status == :completed
    assert_script_done(mock)
  end

  test "a portable Flow composes Start and Collect while its live stream stays in execution", %{
    jido: jido
  } do
    {mock, _} = mock(tool_script())
    assert :ok = Jido.Action.validate_static_data(Example.Flow.flow())
    assert {:ok, result} = Jido.Exec.run(Example.Flow, params(mock), context(jido))
    assert result.result == "Five"
    assert_receive {:standalone_add, _, 2, 3}
    assert_script_done(mock)
  end

  test "an Agent route commits the collected result from the standalone Action Flow", %{
    jido: jido
  } do
    {mock, _} = mock(tool_script())
    {:ok, definition} = Example.Agent.new()
    server = start_agent(jido, definition)
    signal = Jido.Signal.new!("case.run", params(mock), source: "/examples/standalone-actions")
    assert {:ok, agent} = Server.call(server, signal, context: context(jido), timeout: 10_000)
    assert agent.state.result.result == "Five"
    assert :ok = Jido.Action.validate_static_data(agent.state)
    assert_receive {:standalone_add, _, 2, 3}
    assert_script_done(mock)
  end

  test "Continue runs a saved pending tool through Exec without another first model call", %{
    jido: jido
  } do
    {mock, _} = mock(tool_script())
    params = params(mock)
    context = context(jido)
    token = checkpoint(params, context, :after_llm)
    params = Map.delete(params, :query)
    refute_receive {:standalone_add, _, _, _}, 20

    assert {:ok, continued} =
             Jido.Exec.run(Continue, Map.put(params, :checkpoint_token, token), context)

    assert {:ok, result} = Collect.run(Map.put(params, :events, continued.events), context)
    assert result.result == "Five"
    assert_receive {:standalone_add, _, 2, 3}
    assert length(MockLLM.report(mock).requests) == 2
    assert_script_done(mock)
  end

  test "Collect from a checkpoint retains current runtime resources and supervisor", %{jido: jido} do
    {mock, _} = mock(tool_script())
    supervisor = start_supervised!(Task.Supervisor)
    params = params(mock)
    token = checkpoint(params, context(jido), :after_llm)
    params = Map.delete(params, :query)

    params =
      Map.merge(params, %{
        checkpoint_token: token,
        task_supervisor: supervisor,
        runtime_context: %{observer: self()}
      })

    assert {:ok, result} = Jido.Exec.run(Collect, params, %{jido: jido, observer: nil})
    assert result.result == "Five"
    assert_receive {:standalone_add, _, 2, 3}
    assert Task.Supervisor.children(supervisor) == []
    assert_script_done(mock)
  end

  test "Collect can inspect a pending token without model or tool work", %{jido: jido} do
    {mock, _} = mock([hd(tool_script())])
    params = params(mock)
    context = context(jido)
    token = checkpoint(params, context, :after_llm)
    params = Map.delete(params, :query)

    assert {:ok, result} =
             Jido.Exec.run(
               Collect,
               Map.merge(params, %{checkpoint_token: token, run_until_terminal?: false}),
               context
             )

    assert result.result == nil and result.trace == []
    assert result.token_payload.state.status == :awaiting_tools
    refute_receive {:standalone_add, _, _, _}, 20
    assert_script_done(mock)
  end

  test "Cancel returns a replacement token that Collect cannot execute", %{jido: jido} do
    {mock, _} = mock([hd(tool_script())])
    params = params(mock)
    context = context(jido)
    token = checkpoint(params, context, :after_llm)
    params = Map.delete(params, :query)

    assert {:ok, %{cancelled: true, token: cancelled}} =
             Jido.Exec.run(
               Cancel,
               Map.merge(params, %{checkpoint_token: token, reason: :user_cancelled}),
               context
             )

    assert {:ok, result} = Collect.run(Map.put(params, :checkpoint_token, cancelled), context)
    assert result.termination_reason == :cancelled
    refute_receive {:standalone_add, _, _, _}, 20
    assert_script_done(mock)
  end

  test "native Action limits stop a saved pending tool before execution", %{jido: jido} do
    {mock, _} =
      mock([
        %{
          reply:
            {:tools,
             [
               %{id: "bound-a", name: "add", arguments: %{a: 1, b: 2}},
               %{id: "bound-b", name: "add", arguments: %{a: 3, b: 4}}
             ]}
        }
      ])

    params = params(mock)
    context = context(jido)
    token = checkpoint(params, context, :after_llm)
    params = Map.delete(params, :query)

    params =
      Map.merge(params, %{checkpoint_token: token, limits: %{timeout: 5_000, max_tool_calls: 1}})

    assert {:ok, result} = Jido.Exec.run(Collect, params, context)
    assert result.termination_reason == :failed
    assert inspect(result.result) =~ "AI tool limit reached"
    refute_receive {:standalone_add, _, _, _}, 20
    assert_script_done(mock)
  end

  test "Action query validation and invalid tokens fail before a provider request", %{jido: jido} do
    {mock, _} = mock([])
    params = params(mock)
    assert {:error, :query_required} = Start.run(%{params | query: ""}, context(jido))
    assert {:error, _} = Jido.Exec.run(Start, Map.delete(params, :query), context(jido))
    assert {:error, :events_or_checkpoint_token_required} = Collect.run(params, context(jido))

    assert {:error, _} =
             Continue.run(Map.put(params, :checkpoint_token, "invalid"), context(jido))

    assert_script_done(mock)
  end

  test "Start retains multimodal query parts through its real provider request", %{jido: jido} do
    {mock, _} = mock([%{reply: {:text, "Seen"}}])

    query = [
      ReqLLM.Message.ContentPart.text("Read this"),
      ReqLLM.Message.ContentPart.image_url("https://example.invalid/image.png")
    ]

    params = params(mock, %{query: query, tools: []})
    assert {:ok, started} = Jido.Exec.run(Start, params, context(jido))
    assert {:ok, result} = Collect.run(Map.put(params, :events, started.events), context(jido))
    assert result.result == "Seen"
    [wire] = MockLLM.report(mock).requests
    message = Enum.find(wire.body["messages"], &(&1["role"] == "user"))
    assert Enum.any?(message["content"], &(&1["type"] == "image_url"))
    assert_script_done(mock)
  end

  test "string-key Action input retains model options tools and metadata through Exec", %{
    jido: jido
  } do
    {mock, _} = mock(tool_script())
    params = Map.new(params(mock), fn {key, value} -> {Atom.to_string(key), value} end)
    assert {:ok, started} = Jido.Exec.run(Start, params, context(jido))
    assert {:ok, result} = Jido.Exec.run(Collect, %{"events" => started.events}, context(jido))
    assert result.result == "Five"
    assert_receive {:standalone_add, _, 2, 3}

    for action <- [Start, Continue, Collect, Cancel] do
      assert action.category() == "ai" and action.vsn() == "1.0.0"
      assert "react" in action.tags()
    end

    assert_script_done(mock)
  end

  test "Collect after tools retains their result without another execution", %{jido: jido} do
    {mock, _} = mock(tool_script())
    params = params(mock)
    context = context(jido)
    token = checkpoint(params, context, :after_tools)
    assert_receive {:standalone_add, _, 2, 3}
    params = params |> Map.delete(:query) |> Map.put(:checkpoint_token, token)
    assert {:ok, result} = Jido.Exec.run(Collect, params, context)
    assert result.result == "Five"
    refute_receive {:standalone_add, _, _, _}, 20
    assert_script_done(mock)
  end

  test "Exec cancellation stops the private Agent owned by a collecting Action", %{jido: jido} do
    {mock, _} = mock([%{reply: {:tools, [%{id: "held", name: "hold", arguments: %{}}]}}])
    supervisor = start_supervised!(Task.Supervisor)

    params =
      params(mock, %{tools: [JidoAI.Examples.StandaloneRuntime.Hold], task_supervisor: supervisor})

    context = context(jido)
    token = checkpoint(params, context, :after_llm)
    params = params |> Map.delete(:query) |> Map.put(:checkpoint_token, token)
    execution = Jido.Exec.run_async(Collect, params, context, timeout: 5_000)
    assert_receive {:standalone_tool_waiting, tool, server}, 2_000
    [runner] = Task.Supervisor.children(supervisor)
    runner_monitor = Process.monitor(runner)
    tool_monitor = Process.monitor(tool)
    server_monitor = Process.monitor(server)
    assert :ok = Jido.Exec.cancel(execution)
    assert_receive {:DOWN, ^tool_monitor, :process, ^tool, _}, 2_000
    assert_receive {:DOWN, ^server_monitor, :process, ^server, _}, 2_000
    assert_receive {:DOWN, ^runner_monitor, :process, ^runner, _}, 2_000
    assert Task.Supervisor.children(supervisor) == []
    assert_script_done(mock)
  end

  defp checkpoint(params, context, phase) do
    assert {:ok, started} = Start.run(params, context)
    events = CheckpointResume.through_checkpoint(started.events, phase)
    assert List.last(events).data.reason == phase
    List.last(events).data.token
  end

  defp params(mock, extra \\ %{}) do
    options = MockLLM.options(mock)
    assert URI.parse(options[:base_url]).host == "127.0.0.1"

    Map.merge(
      %{
        query: "Sum",
        model: MockLLM.model(),
        llm_opts: options,
        tools: [Add],
        token_secret: "standalone-actions",
        limits: %{timeout: 5_000, max_tool_calls: 32}
      },
      extra
    )
  end

  defp context(jido), do: %{jido: jido, observer: self()}

  defp tool_script,
    do: [
      %{reply: {:tools, [%{id: "action-add", name: "add", arguments: %{a: 2, b: 3}}]}},
      %{reply: {:text, "Five"}}
    ]
end
