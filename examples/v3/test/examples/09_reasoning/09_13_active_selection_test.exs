defmodule JidoAI.Examples.ActiveSelectionTest do
  use JidoAI.Examples.Case
  alias Jido.AI.Reasoning.Adaptive, as: Method
  alias JidoAI.Examples.{ActiveSelection, Adaptive, TRM}
  alias Jido.AI.{Authoring, Request, Session}

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

  test "the current Adaptive selection is committed before its first provider call", %{jido: jido} do
    script = TRM.script()
    {mock, context} = mock([%{reply: {:wait, :first_call, hd(script).reply}}] ++ tl(script))
    server = start_agent(jido, ActiveSelection.Agent.new!())

    assert {:ok, handle} =
             ActiveSelection.Agent.ask(server, "Improve the answer", context: context)

    assert_receive {:mock_llm_waiting, ^mock, :first_call, _}, 2_000
    active = Server.agent(server)
    assert active.state.selected_strategy == :trm
    assert Method.get_selected_strategy(active) == :trm
    assert is_float(Method.get_complexity_score(active))
    assert active.state.requests[handle.id].status == :pending
    assert active.state.requests[handle.id].meta.adaptive.strategy == :trm
    refute active.state.completed
    assert active.state.last_result == ""
    assert :ok = MockLLM.release(mock, :first_call)
    assert {:ok, "First answer"} = ActiveSelection.Agent.await(handle)
    assert_receive {:selection_commit, _}
    refute_receive {:selection_commit, _}
    assert_script_done(mock)
  end

  defp with_input_control do
    definition = ActiveSelection.Agent.agent()

    plugins =
      Enum.map(definition.plugins, fn
        {Jido.AI.Runtime.Plugin, config} ->
          p = config[:profiles].assistant

          {:ok, p} =
            Jido.AI.Profile.new(%{p | controls: %{p.controls | input: [ActiveSelection.Input]}})

          {Jido.AI.Runtime.Plugin, Keyword.put(config, :profiles, %{assistant: p})}

        other ->
          other
      end)

    attrs =
      definition |> Jido.Agent.to_map() |> Map.drop([:id, :state]) |> Map.put(:plugins, plugins)

    {:ok, definition} = Jido.Agent.new(attrs)
    Jido.Agent.instantiate!(definition)
  end

  test "input controls finish before selection becomes active", %{jido: jido} do
    script = TRM.script()
    {mock, context} = mock([%{reply: {:wait, :after_input, hd(script).reply}}] ++ tl(script))
    server = start_agent(jido, with_input_control())

    assert {:ok, handle} =
             ActiveSelection.Agent.ask(server, "Improve the answer", context: context)

    assert_receive {:before_selection, checker}, 2_000
    before = Server.agent(server)
    assert before.state.selected_strategy == nil
    assert Method.get_selected_strategy(before) == nil
    assert before.state.requests[handle.id].meta == %{}
    assert MockLLM.report(mock).requests == []
    send(checker, :continue_selection)
    assert_receive {:mock_llm_waiting, ^mock, :after_input, _}, 2_000
    assert Method.get_selected_strategy(Server.agent(server)) == :trm
    assert :ok = MockLLM.release(mock, :after_input)
    assert {:ok, "First answer"} = ActiveSelection.Agent.await(handle)
    assert_script_done(mock)
  end

  test "input rejection leaves no active selection and makes no model call", %{jido: jido} do
    {mock, context} = mock([])
    server = start_agent(jido, with_input_control())

    assert {:ok, handle} =
             ActiveSelection.Agent.ask(server, "Improve the answer", context: context)

    assert_receive {:before_selection, checker}, 2_000
    send(checker, :reject_selection)
    assert {:error, reason} = ActiveSelection.Agent.await(handle)
    assert inspect(reason) =~ "input_rejected"
    assert Method.get_selected_strategy(Server.agent(server)) == nil
    refute_receive {:selection_commit, _}
    assert_script_done(mock)
  end

  test "forged progress and replay of a consumed ticket cannot change a pending selection", %{
    jido: jido
  } do
    script = TRM.script()

    {mock, context} =
      mock([%{reply: {:wait, :protected_selection, hd(script).reply}}] ++ tl(script))

    server = start_agent(jido, ActiveSelection.Agent.new!())

    assert {:ok, handle} =
             ActiveSelection.Agent.ask(server, "Improve the answer", context: context)

    assert_receive {:mock_llm_waiting, ^mock, :protected_selection, _}, 2_000
    assert_receive {:selection_commit, committed}, 2_000
    before = Server.agent(server).state.requests[handle.id]

    forged = %{
      committed
      | data: Map.merge(committed.data, %{ticket: "forged", adaptive: %{strategy: :got}})
    }

    fake = %{request_id: handle.id, run_id: before.run_id, adaptive: %{strategy: :got}}

    for signal <- [forged, committed] do
      assert {:error, reason} =
               Server.call(server, signal, context: Map.put(context, :jido_ai_progress, fake))

      assert inspect(reason) =~ "invalid_progress"
      assert Server.agent(server).state.requests[handle.id] == before
      assert Server.agent(server).state.selected_strategy == :trm
    end

    assert :ok = MockLLM.release(mock, :protected_selection)
    assert {:ok, "First answer"} = ActiveSelection.Agent.await(handle)
    assert_script_done(mock)
  end

  test "a host rejection of the selection commit stops work before the provider", %{jido: jido} do
    {mock, context} = mock([])
    server = start_agent(jido, ActiveSelection.Agent.new!())

    assert {:ok, handle} =
             ActiveSelection.Agent.ask(server, "Improve the answer",
               context: Map.put(context, :reject_progress, true)
             )

    assert {:error, reason} = ActiveSelection.Agent.await(handle)
    assert inspect(reason) =~ "progress_policy_rejected"
    assert_receive {:selection_commit, _}
    assert_script_done(mock)
  end

  test "owner loss retains committed selection and does not replay the stopped method", %{
    jido: jido
  } do
    {mock, context} =
      mock(
        [%{reply: {:stream, [{:wait, :lost_selection_owner}], "stop"}}] ++ Adaptive.script(:cod)
      )

    server = start_agent(jido, ActiveSelection.Agent.new!())

    assert {:ok, %{request: handle, events: _}} =
             ActiveSelection.Agent.ask_stream(server, "Improve this answer", context: context)

    assert_receive {:mock_llm_waiting, ^mock, :lost_selection_owner, provider}, 2_000
    monitor = Process.monitor(provider)
    assert Method.get_selected_strategy(Server.agent(server)) == :trm
    owner = Server.children(server)[{:plugin, Session.Plugin}].pid
    Process.exit(owner, :kill)
    assert {:error, :stream_interrupted} = ActiveSelection.Agent.await(handle)
    assert_receive {:DOWN, ^monitor, :process, ^provider, _}, 2_000
    assert Method.get_selected_strategy(Server.agent(server)) == :trm
    assert Server.agent(server).state.requests[handle.id].meta.adaptive.strategy == :trm

    assert {:ok, "Four"} =
             ActiveSelection.Agent.ask_sync(server, "What is two plus two?", context: context)

    assert Method.get_selected_strategy(Server.agent(server)) == :cod
    assert_script_done(mock)
  end

  test "late progress cannot reopen a cancelled request", %{jido: jido} do
    {mock, context} =
      mock([%{reply: {:stream, [{:wait, :cancel_selection}], "stop"}}] ++ Adaptive.script(:cod))

    server = start_agent(jido, ActiveSelection.Agent.new!())

    assert {:ok, handle} =
             ActiveSelection.Agent.ask(server, "Improve this answer", context: context)

    assert_receive {:mock_llm_waiting, ^mock, :cancel_selection, provider}, 2_000
    assert_receive {:selection_commit, committed}, 2_000
    monitor = Process.monitor(provider)
    assert :ok = Session.cancel(handle, reason: :changed_task)
    assert {:error, {:cancelled, :changed_task}} = ActiveSelection.Agent.await(handle)
    assert_receive {:DOWN, ^monitor, :process, ^provider, _}, 2_000
    before = Server.agent(server).state.requests[handle.id]
    assert {:error, _} = Server.call(server, committed, context: context)
    assert Server.agent(server).state.requests[handle.id] == before
    assert Method.get_selected_strategy(Server.agent(server)) == :trm

    assert {:ok, "Four"} =
             ActiveSelection.Agent.ask_sync(server, "What is two plus two?", context: context)

    assert_script_done(mock)
  end

  test "native selection commit preserves unrelated domain work during input control", %{
    jido: jido
  } do
    script = TRM.script()
    {mock, context} = mock([%{reply: {:wait, :native_selection, hd(script).reply}}] ++ tl(script))
    source = Adaptive.source()
    source = %{source | controls: %{source.controls | input: [ActiveSelection.Input]}}
    assert {:ok, definition} = Authoring.lower(Adaptive.base(), [source])
    server = start_agent(jido, Jido.Agent.instantiate!(definition))

    assert {:ok, handle} =
             Request.create_and_send(server, "Improve this answer",
               signal_type: "ai.adaptive.query",
               source: "/examples/selection",
               context: context
             )

    assert_receive {:before_selection, checker}, 2_000
    close = Jido.Signal.new!("case.close", %{reason: "closed"}, source: "/examples/selection")
    assert {:ok, closed} = Server.call(server, close)
    assert closed.state.case_id == "closed"
    send(checker, :continue_selection)
    assert_receive {:mock_llm_waiting, ^mock, :native_selection, _}, 2_000
    active = Server.agent(server)
    assert active.state.case_id == "closed"
    assert active.state.requests[handle.id].status == :pending
    assert Method.get_selected_strategy(active) == :trm
    assert :ok = MockLLM.release(mock, :native_selection)
    assert {:ok, "First answer"} = Request.await(handle)
    assert Server.agent(server).state.case_id == "closed"
    assert_script_done(mock)
  end
end
