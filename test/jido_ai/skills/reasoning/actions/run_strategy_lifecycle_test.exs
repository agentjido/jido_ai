defmodule Jido.AI.Actions.Reasoning.RunStrategyLifecycleTest do
  use Jido.AI.Test.CallableReasoningCase, async: false
  use Mimic
  alias Jido.AI.Actions.Reasoning.RunStrategy
  alias Jido.AI.{Configuration, Session}
  alias Jido.AgentServer, as: Server

  setup :set_mimic_from_context

  test "Profile timeout stops the provider and private owners", %{jido: jido} do
    {mock, context} = held(jido, :timeout, 400)
    task = Task.async(fn -> RunStrategy.run(%{prompt: "Task"}, context) end)
    refs = owners(mock, jido, :timeout)
    assert {:error, payload} = Task.await(task, 3_000)
    assert payload.strategy == :cot
    assert payload.status in [:failure, :running]
    assert is_binary(payload.diagnostics.error)
    stopped(refs, jido)
  end

  test "outer Exec timeout stops the provider and private owners", %{jido: jido} do
    {mock, context} = held(jido, :outer)
    task = Task.async(fn -> Jido.Exec.run(RunStrategy, %{prompt: "Task"}, context, timeout: 500) end)
    refs = owners(mock, jido, :outer)
    assert {:error, %Jido.Action.Error.TimeoutError{}} = Task.await(task, 3_000)
    stopped(refs, jido)
  end

  test "Exec cancellation stops the provider and private owners", %{jido: jido} do
    {mock, context} = held(jido, :cancel)
    execution = Jido.Exec.run_async(RunStrategy, %{prompt: "Task"}, context, timeout: 8_000)
    refs = owners(mock, jido, :cancel)
    assert :ok = Jido.Exec.cancel(execution)
    stopped(refs, jido)
  end

  test "caller death stops the linked private runtime", %{jido: jido} do
    {mock, context} = held(jido, :death)
    caller = spawn(fn -> RunStrategy.run(%{prompt: "Task"}, context) end)
    refs = owners(mock, jido, :death)
    Process.exit(caller, :kill)
    stopped(refs, jido)
  end

  test "concurrent calls keep separate sessions and results", %{jido: jido} do
    mock =
      start_supervised!(
        {MockLLM,
         script: [
           %{reply: {:wait, :one, {:text, "Conclusion: One"}}},
           %{reply: {:wait, :two, {:text, "Conclusion: Two"}}}
         ],
         observer: self()}
      )

    context = context(jido, mock, callable_profile(:chain_of_thought))
    first = Task.async(fn -> RunStrategy.run(%{prompt: "Same input"}, context) end)
    refs1 = owners(mock, jido, :one)
    second = Task.async(fn -> RunStrategy.run(%{prompt: "Same input"}, context) end)
    assert_receive {:mock_llm_waiting, ^mock, :two, provider}, 2_000
    servers = Jido.list_agents(jido)
    assert length(servers) == 2

    ids =
      for {_, server} <- servers do
        {:ok, records} = Server.plugin_state(server, Session.Plugin)
        [record] = Map.values(records)
        {record.id, record.run_id}
      end

    assert length(Enum.uniq(ids)) == 2

    refs2 =
      for {_, server} <- servers,
          pid <- [server, Server.children(server)[{:plugin, Session.Plugin}].pid],
          do: {Process.monitor(pid), pid}

    refs2 = [{Process.monitor(provider), provider} | refs2]
    :ok = MockLLM.release(mock, :one)
    assert {:ok, %{output: "One"}} = Task.await(first, 3_000)
    assert length(Jido.list_agents(jido)) == 1
    :ok = MockLLM.release(mock, :two)
    assert {:ok, %{output: "Two"}} = Task.await(second, 3_000)
    stopped(refs1 ++ refs2, jido)
    assert %{remaining: [], unexpected: [], waiting: []} = MockLLM.report(mock)
  end

  test "private history and result start fresh with the bound Profile ID", %{jido: jido} do
    profile = callable_profile(:chain_of_thought, %{memory: %{history: :messages}})

    mock =
      start_supervised!(
        {MockLLM, script: [%{reply: {:wait, :history, {:text, "Conclusion: Fresh"}}}], observer: self()}
      )

    context =
      context(jido, mock, profile)
      |> Map.put(:state, %{messages: [%{role: :user, content: "Parent secret"}], answer: "Old"})

    task = Task.async(fn -> RunStrategy.run(%{prompt: "New input"}, context) end)
    refs = owners(mock, jido, :history)
    [{_, server}] = Jido.list_agents(jido)
    agent = Server.agent(server)
    assert {:ok, ^profile} = Configuration.profile(agent, :review)
    assert agent.state.answer == nil
    refute inspect(agent.state.messages) =~ "Parent secret"
    :ok = MockLLM.release(mock, :history)
    assert {:ok, %{output: "Fresh"}} = Task.await(task, 3_000)
    stopped(refs, jido)
    assert [%{body: body}] = MockLLM.report(mock).requests
    refute inspect(body) =~ "Parent secret"
    assert context.state.answer == "Old"
  end

  test "readiness and both admission calls use one deadline", %{jido: jido} do
    owner = self()

    stub(Server, :await_ready, fn server, timeout ->
      send(owner, {:readiness_budget, timeout})
      Mimic.call_original(Server, :await_ready, [server, timeout])
    end)

    stub(Server, :agent, fn server, timeout ->
      send(owner, {:admission_read_budget, timeout})
      Mimic.call_original(Server, :agent, [server, timeout])
    end)

    stub(Server, :call, fn server, signal, opts ->
      if signal.type == "reasoning.run", do: send(owner, {:admission_budget, opts[:timeout]})
      Mimic.call_original(Server, :call, [server, signal, opts])
    end)

    mock = start_supervised!({MockLLM, script: script(:cot)})
    profile = callable_profile(:chain_of_thought, %{controls: %{timeout: 2_000}})
    assert {:ok, %{output: "Four"}} = RunStrategy.run(%{prompt: "Task"}, context(jido, mock, profile))
    assert_receive {:readiness_budget, ready}
    assert_receive {:admission_read_budget, read}
    assert_receive {:admission_budget, admit}
    assert 2_000 >= ready and ready >= read and read >= admit and admit > 0
  end

  test "a lost await reply recovers committed success", %{jido: jido} do
    stub(Jido.AI.Request, :await, fn handle, opts ->
      assert {:ok, "Four"} = Mimic.call_original(Jido.AI.Request, :await, [handle, opts])
      {:error, :timeout}
    end)

    mock = start_supervised!({MockLLM, script: script(:cot)})
    assert {:ok, payload} = RunStrategy.run(%{prompt: "Task"}, context(jido, mock, callable_profile(:chain_of_thought)))
    assert payload.output == "Four"
    assert payload.status == :success
    assert payload.usage.total_tokens == 15
    assert payload.diagnostics.recovered_error == "Request timed out"
    assert Jido.list_agents(jido) == []
  end

  test "an exhausted readiness deadline cannot admit new work", %{jido: jido} do
    stub(Server, :await_ready, fn _server, timeout ->
      Process.send_after(self(), :ready_after_deadline, timeout + 20)

      receive do
        :ready_after_deadline -> :ok
      after
        1_000 -> flunk("Readiness barrier did not finish")
      end
    end)

    stub(Jido.AI.Request, :create_and_send, fn _, _, _ -> flunk("Expired work must not be admitted") end)
    mock = start_supervised!({MockLLM, script: []})
    profile = callable_profile(:chain_of_thought, %{controls: %{timeout: 200}})
    assert {:error, :timeout} = RunStrategy.run(%{prompt: "Task"}, context(jido, mock, profile))
    assert Jido.list_agents(jido) == []
    assert %{requests: [], unexpected: []} = MockLLM.report(mock)
  end

  @tag capture_log: true
  test "cleanup kills a server that cannot finish its graceful stop", %{jido: jido} do
    owner = self()

    stub(Server, :stop, fn server, reason, timeout ->
      session = Server.children(server)[{:plugin, Session.Plugin}].pid
      send(owner, {:cleanup_owners, server, session})
      :ok = :sys.suspend(server)
      Mimic.call_original(Server, :stop, [server, reason, timeout])
    end)

    mock = start_supervised!({MockLLM, script: script(:cot)})

    assert {:ok, %{output: "Four"}} =
             RunStrategy.run(%{prompt: "Task"}, context(jido, mock, callable_profile(:chain_of_thought)))

    assert_receive {:cleanup_owners, server, session}
    refs = for pid <- [server, session], do: {Process.monitor(pid), pid}
    stopped(refs, jido)
  end

  test "a native tool call forwards its explicit Profile binding", %{jido: jido} do
    mock =
      start_supervised!(
        {MockLLM, script: [reason_tool_reply()] ++ script(:cot) ++ [text_reply("Reviewed")], observer: self()}
      )

    {server, handle} = nested_request(jido, mock)
    assert {:ok, "Reviewed"} = Jido.AI.Request.await(handle, timeout: 5_000)
    assert [{_, ^server}] = Jido.list_agents(jido)
    report = MockLLM.report(mock)
    assert %{remaining: [], unexpected: []} = report
    assert length(report.requests) == 3
    [first | _] = report.requests
    [tool] = first.body["tools"]
    assert Map.keys(tool["function"]["parameters"]["properties"]) == ["prompt"]
  end

  test "parent Session cancellation stops nested callable work", %{jido: jido} do
    mock =
      start_supervised!(
        {MockLLM, script: [reason_tool_reply(), %{reply: {:wait, :nested, {:text, "Late child"}}}], observer: self()}
      )

    {parent, handle} = nested_request(jido, mock)
    assert_receive {:mock_llm_waiting, ^mock, :nested, provider}, 2_000
    [{_, child}] = Enum.reject(Jido.list_agents(jido), fn {_, pid} -> pid == parent end)
    session = Server.children(child)[{:plugin, Session.Plugin}].pid
    refs = for pid <- [child, session, provider], do: {Process.monitor(pid), pid}
    assert :ok = Session.cancel(handle)
    for {ref, pid} <- refs, do: assert_receive({:DOWN, ^ref, :process, ^pid, _}, 3_000)
    assert [{_, ^parent}] = Jido.list_agents(jido)
    assert {:error, _} = Jido.AI.Request.await(handle, timeout: 1_000)
  end

  defp reason_tool_reply,
    do: %{reply: {:tools, [%{id: "reason-1", name: "reason", arguments: %{prompt: "Review two plus two"}}]}}

  defp nested_request(jido, mock) do
    bound = callable_profile(:chain_of_thought)

    outer =
      Jido.AI.Profile.new!(%{
        id: :outer,
        model: MockLLM.model(),
        reasoning: :react,
        tools: [
          %{
            target: RunStrategy,
            name: "reason",
            timeout: 5_000,
            forward_context: [:jido_ai_callable_profile, :ai, :jido]
          }
        ],
        controls: %{timeout: 8_000},
        requests: %{mode: :session, streaming: true},
        result: %{into: :answer}
      })

    {:ok, definition} =
      Jido.AI.Authoring.lower(
        %{
          name: "nested_callable_host",
          schema: Zoi.object(%{answer: Zoi.any() |> Zoi.default(nil)}),
          routes: [{"review", Jido.AI.Authoring.ai(:outer)}]
        },
        [outer]
      )

    server = start_supervised!({Server, agent: definition, jido: jido})

    context = %{
      jido: jido,
      jido_ai_callable_profile: bound,
      ai: %{outer: %{options: MockLLM.options(mock)}, review: %{options: MockLLM.options(mock)}}
    }

    assert {:ok, handle} =
             Jido.AI.Request.create_and_send(server, "Review this with a tool",
               signal_type: "review",
               source: "/test",
               context: context
             )

    {server, handle}
  end

  defp held(jido, barrier, timeout \\ 5_000) do
    mock = start_supervised!({MockLLM, script: [%{reply: {:wait, barrier, {:text, "Late answer"}}}], observer: self()})
    profile = callable_profile(:chain_of_thought, %{controls: %{timeout: timeout}})
    {mock, context(jido, mock, profile)}
  end

  defp context(jido, mock, profile),
    do: %{jido: jido, jido_ai_callable_profile: profile, ai: %{profile.id => %{options: MockLLM.options(mock)}}}

  defp owners(mock, jido, barrier) do
    assert_receive {:mock_llm_waiting, ^mock, ^barrier, provider}, 2_000
    [{_, server}] = Jido.list_agents(jido)
    session = Server.children(server)[{:plugin, Session.Plugin}].pid
    for pid <- [server, session, provider], do: {Process.monitor(pid), pid}
  end

  defp stopped(refs, jido) do
    for {ref, pid} <- refs, do: assert_receive({:DOWN, ^ref, :process, ^pid, _}, 3_000)
    assert Jido.list_agents(jido) == []
  end
end
