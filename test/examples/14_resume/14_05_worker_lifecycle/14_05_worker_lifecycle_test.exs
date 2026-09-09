defmodule JidoAI.Examples.WorkerLifecycleTest do
  use JidoAI.Examples.Case
  alias Jido.AI.Request
  alias JidoAI.Examples.WorkerLifecycle, as: Example

  for {method, module} <- [react: Example.ReAct, cot: Example.CoT] do
    test "#{method} task failure stops held work and late task data cannot finish the next request",
         %{jido: jido} do
      module = unquote(module)
      method = unquote(method)

      {mock, context} =
        mock([held_reply(method), %{reply: {:wait, :next_answer, {:text, "Next"}}}])

      {:ok, server} = Jido.start_agent(jido, module)

      {:ok, request} =
        module.ask(server, "Hold",
          context: context,
          stream_to: self(),
          tool_context: %{tenant_id: "tenant-one"}
        )

      tool = held_process(method, mock, "tenant-one")
      owner = owner(server)
      task = :sys.get_state(owner).jobs[request.id].task
      old_run = :sys.get_state(owner).jobs[request.id].record.run_id
      tool_monitor = Process.monitor(tool)
      Process.exit(task.pid, :kill)
      assert_receive {:DOWN, ^tool_monitor, :process, ^tool, _}, 2_000
      assert {:error, :worker_crash} = module.await(request)
      assert Server.agent(server).state.requests[request.id].meta.worker_exit_reason == :killed
      assert Server.agent(server).state.requests[request.id].meta.error_type == :worker_task
      assert Process.alive?(server) and Process.alive?(owner)
      assert one_terminal(request, :request_failed)
      usage = Server.agent(server).state.requests[request.id].meta.usage
      assert Map.get(usage, :total_tokens, 0) == unquote(if(method == :react, do: 15, else: 0))

      {:ok, next} = module.ask(server, "Next", context: context, stream_to: self())
      assert_receive {:mock_llm_waiting, ^mock, :next_answer, _}, 2_000
      before = Server.agent(server).state.requests[next.id]
      send(owner, {task.ref, {:ok, %{result: "Late answer", meta: %{}}}})
      send(owner, {:DOWN, task.ref, :process, task.pid, :old_exit})

      assert :ok =
               GenServer.call(
                 owner,
                 {:event, request.id, old_run, :request_completed, %{result: "Late answer"}}
               )

      assert Server.agent(server).state.requests[next.id] == before
      assert :ok = MockLLM.release(mock, :next_answer)
      assert {:ok, "Next"} = module.await(next)
      assert one_terminal(next, :request_completed)
      assert :ok = Jido.Action.validate_static_data(Server.agent(server).state)
      assert_script_done(mock)
    end

    test "#{method} Session owner loss fails saved work and a fresh owner accepts the next request",
         %{jido: jido} do
      module = unquote(module)
      method = unquote(method)
      {mock, context} = mock([held_reply(method), %{reply: {:text, "Recovered"}}])
      {:ok, server} = Jido.start_agent(jido, module)
      {:ok, request} = module.ask(server, "Hold", context: context, stream_to: self())
      tool = held_process(method, mock)
      runtime = owner(server)
      task = :sys.get_state(runtime).jobs[request.id].task.pid
      tool_monitor = Process.monitor(tool)
      task_monitor = Process.monitor(task)
      Process.exit(runtime, :kill)
      assert_receive {:DOWN, ^tool_monitor, :process, ^tool, _}, 2_000
      assert_receive {:DOWN, ^task_monitor, :process, ^task, _}, 2_000
      assert {:error, :stream_interrupted} = module.await(request)
      assert Process.alive?(server)
      assert owner(server) != runtime
      {:ok, next} = module.ask(server, "Next", context: context)
      assert {:ok, "Recovered"} = module.await(next)
      assert_script_done(mock)
    end

    test "#{method} parent shutdown stops Session task and held work without retry", %{jido: jido} do
      module = unquote(module)
      method = unquote(method)
      {mock, context} = mock([held_reply(method)])
      {:ok, server} = Jido.start_agent(jido, module)
      {:ok, request} = module.ask(server, "Hold", context: context)
      tool = held_process(method, mock)
      runtime = owner(server)
      task = :sys.get_state(runtime).jobs[request.id].task.pid
      monitors = for pid <- [tool, task, runtime], do: {pid, Process.monitor(pid)}
      assert :ok = GenServer.stop(server, :normal)

      for {pid, monitor} <- monitors do
        assert_receive {:DOWN, ^monitor, :process, ^pid, _}, 2_000
      end

      assert {:error, _} = module.await(request)
      assert_script_done(mock)
    end

    test "#{method} wrong-run observations and old worker Signals cannot alter an active request",
         %{jido: jido} do
      module = unquote(module)
      {mock, context} = mock([%{reply: {:wait, :answer, {:text, "Actual"}}}])
      {:ok, server} = Jido.start_agent(jido, module)
      {:ok, request} = module.ask(server, "Wait", context: context, stream_to: self())
      assert_receive {:mock_llm_waiting, ^mock, :answer, _}, 2_000
      runtime = owner(server)
      before = Server.agent(server).state.requests[request.id]

      for message <- [
            {:event, request.id, "wrong-run", :llm_completed, %{text: "Forged"}},
            {:usage, request.id, "wrong-run", %{total_tokens: 999}},
            {:tool_signature, request.id, "wrong-run", "Forged"},
            {:reasoning_iteration, request.id, "wrong-run", 999},
            {:failure_type, request.id, "wrong-run", :forged}
          ] do
        assert :ok = GenServer.call(runtime, message)
      end

      signal =
        Jido.Signal.new!(
          "ai.#{unquote(method)}.worker.event",
          %{
            request_id: request.id,
            event: %{kind: :request_completed, data: %{result: "Forged"}}
          },
          source: "/old-worker"
        )

      Server.call(server, signal)
      assert Server.agent(server).state.requests[request.id] == before
      assert :ok = MockLLM.release(mock, :answer)
      assert {:ok, "Actual"} = module.await(request)
      events = Enum.to_list(Request.Stream.events(request))
      refute Enum.any?(events, &(inspect(&1.data) =~ "Forged"))
      assert Enum.count(events, &Request.Stream.terminal_kind?(&1.kind)) == 1
      assert Server.agent(server).state.requests[request.id].meta.usage.total_tokens == 15

      refute Map.has_key?(
               Server.agent(server).state.requests[request.id].meta,
               :prev_tool_signature
             )

      assert_script_done(mock)
    end
  end

  test "a delegated public ReAct request retains uploaded file IDs at the actual model boundary",
       %{jido: jido} do
    {mock, context} = mock([%{reply: {:text, "Read file"}}])
    {:ok, server} = Jido.start_agent(jido, Example.ReAct)

    query = [
      ReqLLM.Message.ContentPart.text("Read this file"),
      ReqLLM.Message.ContentPart.file_id("file_worker_123")
    ]

    {:ok, request} = Example.ReAct.ask(server, query, context: context, stream_to: self())
    assert {:ok, "Read file"} = Example.ReAct.await(request)
    [wire] = MockLLM.report(mock).requests
    user = Enum.find(wire.body["messages"], &(&1["role"] == "user"))

    assert Enum.any?(
             user["content"],
             &(&1["type"] == "file" and &1["file"]["file_id"] == "file_worker_123")
           )

    record = Server.agent(server).state.requests[request.id]
    assert record.query == query
    assert one_terminal(request, :request_completed)
    assert_script_done(mock)
  end

  defp owner(server), do: Server.children(server)[{:plugin, Jido.AI.Session.Plugin}].pid
  defp held_reply(:react), do: tool_reply()
  defp held_reply(:cot), do: %{reply: {:wait, :held_model, {:text, "Held"}}}

  defp held_process(method, mock, tenant \\ nil)

  defp held_process(:react, _mock, tenant) do
    assert_receive {:worker_tool, tool, ^tenant, _}, 2_000
    tool
  end

  defp held_process(:cot, mock, _tenant) do
    assert_receive {:mock_llm_waiting, ^mock, :held_model, provider}, 2_000
    provider
  end

  defp tool_reply, do: %{reply: {:tools, [%{id: "held", name: "hold", arguments: %{}}]}}

  defp one_terminal(request, kind) do
    terminal =
      request |> Request.Stream.events() |> Enum.filter(&Request.Stream.terminal_kind?(&1.kind))

    assert [%{kind: ^kind}] = terminal
  end
end
