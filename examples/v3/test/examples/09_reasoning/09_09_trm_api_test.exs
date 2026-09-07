defmodule JidoAI.Examples.TRMAPITest do
  use JidoAI.Examples.Case
  alias Jido.AI.Request
  alias Jido.AI.Reasoning.TRM, as: Method
  alias JidoAI.Examples.{TRM, TRMAPI}

  setup do
    saved = Application.fetch_env(:jido_ai, :model_aliases)

    Application.put_env(:jido_ai, :model_aliases, %{
      example: MockLLM.model(),
      fast: MockLLM.model()
    })

    on_exit(fn ->
      case saved do
        {:ok, value} -> Application.put_env(:jido_ai, :model_aliases, value)
        :error -> Application.delete_env(:jido_ai, :model_aliases)
      end
    end)

    :ok
  end

  defp profile(module) do
    {_, config} = Enum.find(module.agent().plugins, &(elem(&1, 0) == Jido.AI.Runtime.Plugin))
    config[:profiles].assistant
  end

  defp record(server, handle), do: Server.agent(server).state.requests[handle.id]

  defp empty(agent, id \\ nil) do
    assert Method.get_answer_history(agent, id) == []
    assert Method.get_current_answer(agent, id) == nil
    assert Method.get_confidence(agent, id) == 0.0
    assert Method.get_supervision_step(agent, id) == 0
    assert Method.get_best_answer(agent, id) == nil
    assert Method.get_best_score(agent, id) == 0.0
  end

  test "public defaults and retained helpers distinguish the scored answer from the current improvement",
       %{jido: jido} do
    assert Map.new(TRMAPI.Public.strategy_opts()) == %{
             model: :example,
             max_supervision_steps: 5,
             act_threshold: 0.9
           }

    assert TRMAPI.Public.description() == "TRM agent public_recursive"
    assert profile(TRMAPI.Public).controls.max_model_calls == 15
    assert profile(TRMAPI.Public).controls.max_iterations == 15
    refute profile(TRMAPI.Public).requests.steering
    assert profile(TRMAPI.Public).memory.history == nil
    {mock, context} = mock(TRM.script())
    assert {:ok, agent} = TRMAPI.Public.new()
    assert agent.state.last_prompt == "" and agent.state.last_result == ""
    empty(agent)

    for {name, arity} <- [
          reason: 2,
          reason: 3,
          reason_sync: 2,
          reason_sync: 3,
          await: 1,
          await: 2,
          strategy_opts: 0
        ] do
      assert function_exported?(TRMAPI.Public, name, arity)
    end

    assert_raise FunctionClauseError, fn -> TRMAPI.Public.reason(self(), []) end
    assert_raise FunctionClauseError, fn -> TRMAPI.Public.reason_sync(self(), []) end
    server = start_agent(jido, agent)
    assert {:ok, "First answer"} = TRMAPI.Public.reason_sync(server, "Analyze", context: context)
    agent = Server.agent(server)
    assert agent.state.last_prompt == "Analyze" and agent.state.completed
    assert agent.state.last_result == "First answer"
    assert Method.method() == :trm
    assert Method.get_answer_history(agent) == ["Unreviewed improvement"]
    assert Method.get_current_answer(agent) == "Unreviewed improvement"
    assert Method.get_best_answer(agent) == "First answer"
    assert Method.get_best_score(agent) == 0.95 and Method.get_confidence(agent) == 0.95
    assert Method.get_supervision_step(agent) == 1
    assert_script_done(mock)
  end

  test "a pending public request clears convenience state and keeps older method data available",
       %{jido: jido} do
    second = TRM.cycle("Second answer", 0.96, "Second improvement")

    {mock, context} =
      mock(TRM.script() ++ [%{reply: {:wait, :second_trm, hd(second).reply}}] ++ tl(second))

    server = start_agent(jido, TRMAPI.Public.new!())
    assert {:ok, first} = TRMAPI.Public.reason(server, "First", context: context)
    assert {:ok, "First answer"} = TRMAPI.Public.await(first)
    old = record(server, first)
    assert {:ok, next} = TRMAPI.Public.reason(server, "Second", context: context)
    assert_receive {:mock_llm_waiting, ^mock, :second_trm, _}, 2_000
    pending = Server.agent(server)
    assert pending.state.last_prompt == "Second" and pending.state.last_result == ""
    refute pending.state.completed
    empty(pending)
    empty(pending, "missing")
    assert Method.get_best_answer(pending, first.id) == "First answer"
    assert Method.get_answer_history(pending, first.id) == ["Unreviewed improvement"]
    assert :ok = MockLLM.release(mock, :second_trm)
    assert {:ok, "Second answer"} = TRMAPI.Public.await(next)
    assert record(server, first) == old
    assert Method.get_current_answer(Server.agent(server)) == "Second improvement"
    assert record(server, next).meta.usage.total_tokens == 45
    assert_script_done(mock)
  end

  test "failed public improvement preserves prior review data and printable error state", %{
    jido: jido
  } do
    {mock, context} = mock(Enum.take(TRM.script(), 2) ++ [%{reply: {:stream, [], "length"}}])
    server = start_agent(jido, TRMAPI.Public.new!())
    assert {:ok, handle} = TRMAPI.Public.reason(server, "Fail", context: context)

    assert {:error, {:failed, {:incomplete_response, :length}, result}} =
             TRMAPI.Public.await(handle)

    agent = Server.agent(server)
    assert agent.state.completed and agent.state.last_result == result.result
    assert String.starts_with?(agent.state.last_result, "Error: ")
    assert result.diagnostics.cause == {:incomplete_response, :length}
    assert Method.get_best_answer(agent) == "First answer"
    assert Method.get_current_answer(agent) == "First answer"
    assert Method.get_best_score(agent) == 0.95 and Method.get_confidence(agent) == 0.95
    assert Method.get_answer_history(agent) == [] and Method.get_supervision_step(agent) == 1
    assert result.usage.total_tokens == 45
    assert record(server, handle).error == {:failed, {:incomplete_response, :length}, result}
    assert_script_done(mock)
  end

  test "old Strategy getters and prompts remain loadable without execution callbacks", %{
    jido: jido
  } do
    {mock, context} = mock(TRM.script())
    server = start_agent(jido, TRMAPI.Public.new!())
    assert {:ok, _} = TRMAPI.Public.reason_sync(server, "Inspect", context: context)
    agent = Server.agent(server)
    adapter = apply(Method, :strategy_module, [])
    assert Code.ensure_loaded?(adapter)

    for getter <- [
          :get_answer_history,
          :get_current_answer,
          :get_confidence,
          :get_supervision_step,
          :get_best_answer,
          :get_best_score
        ] do
      assert apply(adapter, getter, [agent]) == apply(Method, getter, [agent])
    end

    for prompt <- [
          :default_reasoning_prompt,
          :default_supervision_prompt,
          :default_improvement_prompt
        ] do
      assert apply(adapter, prompt, []) == apply(Method, prompt, [])
    end

    for {name, arity} <- [
          init: 2,
          cmd: 3,
          snapshot: 2,
          action_spec: 1,
          signal_routes: 1,
          start_action: 0,
          llm_result_action: 0,
          llm_partial_action: 0,
          request_error_action: 0
        ] do
      refute function_exported?(adapter, name, arity)
    end

    assert String.starts_with?(Method.generate_call_id(), "trm_")
    assert Method.default_reasoning_prompt() == Method.Reasoning.default_reasoning_system_prompt()

    assert Method.default_supervision_prompt() ==
             Method.Supervision.default_supervision_system_prompt()

    assert Method.default_improvement_prompt() ==
             Method.Supervision.default_improvement_system_prompt()

    assert_script_done(mock)
  end

  test "custom public settings reach all six provider calls and preserve the best scored answer",
       %{jido: jido} do
    {mock, context} =
      mock(
        TRM.cycle("Initial", 0.3, "Reviewed improvement") ++
          TRM.cycle("Further analysis", 0.7, "Last improvement")
      )

    server = start_agent(jido, TRMAPI.Custom.new!())
    assert TRMAPI.Custom.description() == "Custom recursive reasoning"

    assert Map.new(TRMAPI.Custom.strategy_opts()) == %{
             model: :example,
             max_supervision_steps: 2,
             act_threshold: 0.99
           }

    assert profile(TRMAPI.Custom).controls.max_model_calls == 6

    assert {:ok, "Reviewed improvement"} =
             TRMAPI.Custom.reason_sync(server, "Improve", context: context)

    agent = Server.agent(server)
    assert Method.get_supervision_step(agent) == 2 and Method.get_best_score(agent) == 0.7
    assert Method.get_answer_history(agent) == ["Reviewed improvement", "Last improvement"]
    assert Method.get_current_answer(agent) == "Last improvement"

    for wire <- MockLLM.report(mock).requests do
      assert String.starts_with?(
               hd(wire.body["messages"])["content"],
               "Use the supplied facts\n\n"
             )

      assert wire.body["max_tokens"] == 90 and wire.body["temperature"] == 0.4
      refute wire.body["stream"]
    end

    assert_script_done(mock)
  end

  test "the public default budget permits all five cycles and fifteen model calls", %{jido: jido} do
    script =
      Enum.flat_map(Enum.with_index([0.1, 0.3, 0.5, 0.7, 0.8], 1), fn {score, step} ->
        TRM.cycle("Analysis #{step}", score, "Improvement #{step}")
      end)

    {mock, context} = mock(script)
    server = start_agent(jido, TRMAPI.Public.new!())
    assert {:ok, handle} = TRMAPI.Public.reason(server, "Full run", context: context)
    assert {:ok, "Improvement 4"} = TRMAPI.Public.await(handle)
    assert Method.get_supervision_step(Server.agent(server)) == 5
    assert record(server, handle).meta.model_calls == 15
    assert record(server, handle).meta.usage.total_tokens == 225
    assert record(server, handle).meta.reasoning.trm.termination_reason == :max_steps
    assert_script_done(mock)
  end

  test "an explicit public model-call limit prevents the next phase and keeps the reviewed answer inspectable",
       %{jido: jido} do
    {mock, context} = mock(Enum.take(TRM.script(), 2))
    server = start_agent(jido, TRMAPI.Bounded.new!())
    assert profile(TRMAPI.Bounded).controls.max_model_calls == 2
    assert {:ok, handle} = TRMAPI.Bounded.reason(server, "Limit", context: context)
    assert {:error, {:failed, reason, result}} = TRMAPI.Bounded.await(handle)
    assert inspect(reason) =~ "limit"
    assert Method.get_best_answer(Server.agent(server)) == "First answer"
    assert result.usage.total_tokens == 30
    assert_script_done(mock)
  end

  test "public cancellation rejects busy input closes improvement transport and accepts a later request",
       %{jido: jido} do
    {mock, context} =
      mock(
        Enum.take(TRM.script(), 2) ++
          [%{reply: {:stream, [{:wait, :held_public_trm}], "stop"}}] ++ TRM.script()
      )

    server = start_agent(jido, TRMAPI.Public.new!())
    assert {:ok, handle} = TRMAPI.Public.reason(server, "Cancel", context: context)
    assert_receive {:mock_llm_waiting, ^mock, :held_public_trm, provider}, 2_000
    monitor = Process.monitor(provider)
    assert {:error, :busy} = TRMAPI.Public.reason(server, "Busy", context: context)
    assert :ok = TRMAPI.Public.cancel(server, reason: :changed_task)
    assert {:error, {:cancelled, :changed_task}} = TRMAPI.Public.await(handle)
    assert_receive {:DOWN, ^monitor, :process, ^provider, _}, 2_000
    assert record(server, handle).meta.usage.total_tokens == 30
    assert {:ok, "First answer"} = TRMAPI.Public.reason_sync(server, "Next", context: context)
    assert_script_done(mock)
  end

  test "the common Agent can select TRM through the same authoring path", %{jido: jido} do
    {mock, context} = mock(TRM.script())
    server = start_agent(jido, TRMAPI.Common.new!())
    assert {:ok, "First answer"} = TRMAPI.Common.ask_sync(server, "Common", context: context)
    assert Method.get_best_answer(Server.agent(server)) == "First answer"
    assert Method.get_supervision_step(Server.agent(server)) == 1
    assert_script_done(mock)
  end

  test "TRM getters do not read another method's retained record", %{jido: jido} do
    {mock, context} = mock(JidoAI.Examples.GoT.script())
    server = start_agent(jido, JidoAI.Examples.GoTAPI.Public.new!())

    assert {:ok, handle} =
             JidoAI.Examples.GoTAPI.Public.explore(server, "Graph", context: context)

    assert {:ok, _} = Request.await(handle)
    empty(Server.agent(server))
    empty(Server.agent(server), handle.id)
    assert_script_done(mock)
  end

  test "the default public model alias resolves through the common provider path", %{jido: jido} do
    {mock, context} = mock(TRM.script())
    assert TRMAPI.Default.strategy_opts()[:model] == :fast
    assert profile(TRMAPI.Default).models.answer.model == :fast
    server = start_agent(jido, TRMAPI.Default.new!())

    assert {:ok, "First answer"} =
             TRMAPI.Default.reason_sync(server, "Default model", context: context)

    assert Server.agent(server).state.model == :fast
    assert_script_done(mock)
  end

  test "public streaming emits phase completions before one selected-answer terminal event", %{
    jido: jido
  } do
    {mock, context} = mock(TRM.script())
    server = start_agent(jido, TRMAPI.Public.new!())

    assert {:ok, %{request: handle, events: stream}} =
             TRMAPI.Public.ask_stream(server, "Stream", context: context)

    events = Enum.to_list(stream)
    assert Enum.map(events, & &1.seq) == Enum.to_list(1..length(events))
    assert Enum.all?(events, &(&1.method == :trm and &1.request_id == handle.id))
    assert Enum.count(events, &Request.Stream.terminal_kind?(&1.kind)) == 1

    assert Enum.filter(events, &(&1.kind == :llm_completed))
           |> Enum.map(& &1.data.reasoning_phase) == [:reasoning, :supervision, :improvement]

    assert List.last(events).kind == :request_completed
    assert {:ok, "First answer"} = TRMAPI.Public.await(handle)
    assert Server.agent(server).state.last_result == "First answer"
    assert_script_done(mock)
  end
end
