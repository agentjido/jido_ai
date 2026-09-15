defmodule JidoAI.Examples.StandaloneInputTest do
  use JidoAI.Examples.Case
  alias Jido.AI.{PendingInputServer, Session}
  alias Jido.AI.Reasoning.ReAct
  alias ReAct.{Config, Token}
  alias JidoAI.Examples.CheckpointResume
  alias JidoAI.Examples.StandaloneRuntime.Hold

  test "a caller queue keeps FIFO input refs and its own capacity before the first model", %{
    jido: jido
  } do
    queue = queue(max_queue_size: 2)

    assert :ok =
             PendingInputServer.enqueue(queue, %{
               id: "one",
               content: "  First input  ",
               source: "/caller",
               refs: %{case_id: 1}
             })

    assert :ok = PendingInputServer.enqueue(queue, %{id: "two", content: "Second input"})
    assert {:error, :queue_full} = PendingInputServer.enqueue(queue, %{content: "Overflow"})
    {mock, _} = mock([%{reply: {:text, "Both inputs"}}])
    config = config(mock, queue)
    result = JidoAI.Examples.StandaloneInput.run("Initial", config, %{jido: jido, observer: self()})
    assert result.result == "Both inputs"
    [wire] = MockLLM.report(mock).requests
    assert users(wire) == ["Initial", "First input", "Second input"]
    consumed = Enum.filter(result.trace, &(&1.kind == :input_injected))
    assert Enum.map(consumed, & &1.data.input_id) == ["one", "two"]
    assert hd(consumed).data.refs == %{case_id: 1} and hd(consumed).data.source == "/caller"
    assert List.last(consumed).seq < Enum.find(result.trace, &(&1.kind == :llm_started)).seq
    assert {:ok, saved, _} = Token.decode_state(result.final_token, config)
    entry = Enum.find(conversation_entries(saved.context), &(Jido.AI.Query.summarize(&1.content) == "First input"))
    assert entry.refs.case_id == 1 and entry.refs.source == "/caller"
    assert sealed?(queue)
    assert_script_done(mock)
  end

  test "input during a final response forces a second model call and one terminal outcome", %{
    jido: jido
  } do
    queue = queue()

    {mock, _} =
      mock([
        %{reply: {:wait, :first, {:text, "First answer"}}},
        %{reply: {:text, "Updated answer"}}
      ])

    config = config(mock, queue)
    task = run_task("Initial", config, jido)
    assert_receive {:mock_llm_waiting, ^mock, :first, _}, 2_000
    assert :ok = PendingInputServer.enqueue(queue, %{content: "Change the answer"})
    assert :ok = MockLLM.release(mock, :first)
    result = Task.await(task, 5_000)
    assert result.result == "Updated answer" and result.usage.total_tokens == 30
    assert Enum.count(result.trace, &(&1.kind == :request_completed)) == 1
    [_, wire] = MockLLM.report(mock).requests
    assert users(wire) == ["Initial", "Change the answer"]

    assert Enum.any?(
             wire.body["messages"],
             &(&1["role"] == "assistant" && &1["content"] == "First answer")
           )

    assert sealed?(queue)
    assert_script_done(mock)
  end

  test "a real held tool and public steering use the supplied queue", %{jido: jido} do
    queue = queue()

    {mock, _} =
      mock([
        %{reply: {:tools, [%{id: "held", name: "hold", arguments: %{}}]}},
        %{reply: {:text, "After tool"}}
      ])

    config = config(mock, queue, tools: [Hold])
    task = run_task("Use tool", config, jido)
    assert_receive {:standalone_tool_waiting, tool, server}, 2_000
    owner = Server.children(server)[{:plugin, Session.Plugin}].pid
    [job] = :sys.get_state(owner).jobs |> Map.values()
    assert job.queue == queue
    assert :ok = PendingInputServer.enqueue(queue, %{id: "caller", content: "Caller input"})
    assert {:ok, agent} = ReAct.steer(server, "Public input")
    [record] = Map.values(agent.state.requests)
    assert %{status: :queued, input_id: public_id} = record.last_control
    send(tool, :release)
    result = Task.await(task, 5_000)
    assert result.result == "After tool"
    consumed = Enum.filter(result.trace, &(&1.kind == :input_injected))
    assert Enum.map(consumed, & &1.data.input_id) == ["caller", public_id]
    assert Enum.count(result.trace, &(&1.kind == :tool_completed)) == 1

    assert users(List.last(MockLLM.report(mock).requests)) == [
             "Use tool",
             "Caller input",
             "Public input"
           ]

    assert sealed?(queue)
    assert_script_done(mock)
  end

  test "a missing queue fails before model work with the runtime error type", %{jido: jido} do
    queue = queue()
    PendingInputServer.stop(queue)
    {mock, _} = mock([])
    config = config(mock, queue)
    result = ReAct.run("No queue", config, opts(jido))
    failure = Enum.find(result.trace, &(&1.kind == :request_failed))
    assert failure.data.error == {:pending_input_server, :unavailable}
    assert failure.data.error_type == :runtime
    assert {:ok, %{status: :failed}, _} = Token.decode_state(result.final_token, config)
    refute Enum.any?(result.trace, &(&1.kind == :llm_started))
    assert_script_done(mock)
  end

  test "queue loss at final closure keeps usage and emits no successful terminal event", %{
    jido: jido
  } do
    queue = queue()
    {mock, _} = mock([%{reply: {:wait, :closure, {:text, "Cannot finish"}}}])
    config = config(mock, queue)
    task = run_task("Lose queue", config, jido)
    assert_receive {:mock_llm_waiting, ^mock, :closure, _}, 2_000
    PendingInputServer.stop(queue)
    MockLLM.release(mock, :closure)
    result = Task.await(task, 5_000)
    failure = Enum.find(result.trace, &(&1.kind == :request_failed))
    assert failure.data.error == {:pending_input_server, :unavailable}
    assert failure.data.error_type == :runtime
    assert result.usage.total_tokens == 15
    refute Enum.any?(result.trace, &(&1.kind == :request_completed))
    assert_script_done(mock)
  end

  test "model failure seals the caller queue without stopping it", %{jido: jido} do
    queue = queue()
    {mock, _} = mock([%{reply: {:error, 400, "fixture failure"}}])
    result = ReAct.run("Fail", config(mock, queue), opts(jido))
    assert result.termination_reason == :failed
    assert sealed?(queue)
    assert_script_done(mock)
  end

  test "halting a stream seals caller input and stops the held provider", %{jido: jido} do
    queue = queue()

    {mock, _} =
      mock([%{reply: {:stream, [%{content: "Visible"}, {:wait, :halt}, %{content: "unused"}]}}])

    config = config(mock, queue, streaming: true)
    observer = self()

    task =
      Task.async(fn ->
        ReAct.stream("Halt", config, opts(jido))
        |> Enum.reduce_while([], fn event, events ->
          if event.kind == :llm_delta do
            send(observer, {:visible, self()})

            receive do
              :halt -> {:halt, [event | events]}
            end
          else
            {:cont, [event | events]}
          end
        end)
      end)

    assert_receive {:visible, consumer}, 2_000
    assert_receive {:mock_llm_waiting, ^mock, :halt, provider}, 2_000
    monitor = Process.monitor(provider)
    assert :ok = PendingInputServer.enqueue(queue, %{content: "Undrained"})
    send(consumer, :halt)
    Task.await(task, 5_000)
    assert_receive {:DOWN, ^monitor, :process, ^provider, _}, 2_000
    assert sealed?(queue)
    assert {:ok, [%{content: "Undrained"}]} = PendingInputServer.drain_result(queue)
    assert_script_done(mock)
  end

  test "loss of the stream consumer seals a borrowed queue whose owner is still alive", %{
    jido: jido
  } do
    queue = queue()
    {mock, _} = mock([%{reply: {:wait, :consumer, {:text, "Unused"}}}])
    config = config(mock, queue)
    observer = self()

    consumer =
      spawn(fn ->
        JidoAI.Examples.StandaloneInput.run("Stop consumer", config, %{jido: jido, observer: observer})
      end)

    assert_receive {:mock_llm_waiting, ^mock, :consumer, provider}, 2_000
    monitor = Process.monitor(provider)
    Process.exit(consumer, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^provider, _}, 2_000
    assert eventually(fn -> sealed?(queue) end)
    assert_script_done(mock)
  end

  test "parent shutdown seals borrowed input and preserves its process", %{jido: jido} do
    queue = queue()
    {mock, _} = mock([%{reply: {:tools, [%{id: "parent", name: "hold", arguments: %{}}]}}])
    config = config(mock, queue, tools: [Hold])
    task = run_task("Stop parent", config, jido)
    assert_receive {:standalone_tool_waiting, tool, server}, 2_000
    monitor = Process.monitor(tool)
    GenServer.stop(server, :normal)
    result = Task.await(task, 5_000)
    assert result.termination_reason == :failed
    assert_receive {:DOWN, ^monitor, :process, ^tool, _}, 2_000
    assert sealed?(queue)
    assert_script_done(mock)
  end

  test "a resumed tool checkpoint binds a new queue without storing a process handle", %{
    jido: jido
  } do
    first = queue()
    assert :ok = PendingInputServer.enqueue(first, %{content: "Before save"})

    {mock, _} =
      mock([
        %{reply: {:tools, [%{id: "resume", name: "check", arguments: %{payload: %{n: 1}}}]}},
        %{reply: {:text, "After resume"}}
      ])

    config = config(mock, first, tools: [JidoAI.Examples.TraceAndCycles.Check])

    checkpoint =
      ReAct.stream("Save", config, opts(jido))
      |> CheckpointResume.through_checkpoint(:after_llm)
      |> List.last()

    assert checkpoint.data.reason == :after_llm
    assert sealed?(first)
    assert {:ok, saved, _} = Token.decode_state(checkpoint.data.token, config)
    assert :ok = Jido.Action.validate_static_data(saved)
    refute inspect(saved.checkpoint, limit: :infinity) =~ "#PID"
    next_queue = queue()
    assert :ok = PendingInputServer.enqueue(next_queue, %{content: "After save"})
    next_config = config(mock, next_queue, tools: [JidoAI.Examples.TraceAndCycles.Check])
    assert {:ok, next} = ReAct.continue(checkpoint.data.token, next_config, opts(jido))
    result = ReAct.collect_stream(next.events)
    assert result.result == "After resume" and result.usage.total_tokens == 30
    [completed] = Enum.filter(result.trace, &(&1.kind == :tool_completed))
    assert {:ok, %{checked: true, fingerprint: fingerprint}, []} = completed.data.result

    assert fingerprint ==
             :crypto.hash(:sha256, :erlang.term_to_binary(%{"n" => 1}, [:deterministic]))
             |> Base.encode16(case: :lower)

    assert users(List.last(MockLLM.report(mock).requests)) == [
             "Save",
             "Before save",
             "After save"
           ]

    assert sealed?(next_queue)
    assert_script_done(mock)
  end

  test "creating a lazy stream does not drain or seal a caller queue", %{jido: jido} do
    queue = queue()
    {mock, _} = mock([])
    config = config(mock, queue)
    assert {:ok, _} = ReAct.start("Unused", config, opts(jido))
    assert :ok = PendingInputServer.enqueue(queue, %{content: "Still open"})
    assert {:ok, [%{content: "Still open"}]} = PendingInputServer.drain_result(queue)
    assert_script_done(mock)
  end

  test "input consumed after the last allowed answer keeps the standalone iteration limit", %{
    jido: jido
  } do
    queue = queue()
    {mock, _} = mock([%{reply: {:wait, :limit, {:text, "Last allowed answer"}}}])
    config = config(mock, queue, max_iterations: 1)
    task = run_task("One call", config, jido)
    assert_receive {:mock_llm_waiting, ^mock, :limit, _}, 2_000
    assert :ok = PendingInputServer.enqueue(queue, %{content: "Needs another call"})
    MockLLM.release(mock, :limit)
    result = Task.await(task, 5_000)
    assert result.termination_reason == :max_iterations
    assert result.result == "Maximum iterations reached without a final answer."
    assert result.usage.total_tokens == 15
    assert Enum.count(result.trace, &(&1.kind == :llm_started)) == 1
    assert Enum.any?(result.trace, &(&1.kind == :input_injected))
    assert {:ok, saved, _} = Token.decode_state(result.final_token, config)

    assert Enum.any?(
             conversation_entries(saved.context),
             &(Jido.AI.Query.summarize(&1.content) == "Needs another call")
           )

    assert sealed?(queue)
    assert_script_done(mock)
  end

  test "an empty queue seals before output repair and rejects late input", %{jido: jido} do
    queue = queue()
    {mock, _} = mock([%{reply: {:object, %{answer: 42}}}])

    config =
      config(mock, queue,
        output: %{
          schema: Zoi.object(%{answer: Zoi.string()}),
          on_validation_error: :repair,
          retries: 1,
          repair_fun: {JidoAI.Examples.StandaloneInput.Repair, :fix}
        }
      )

    task = run_task("Repair", config, jido)
    assert_receive {:input_sealed_repair, repair}, 2_000
    assert sealed?(queue)
    send(repair, :release)
    result = Task.await(task, 5_000)
    assert result.result == %{answer: "Fixed"}
    assert Enum.count(result.trace, &(&1.kind == :request_completed)) == 1
    assert sealed?(queue)
    assert_script_done(mock)
  end

  defp queue(opts \\ []) do
    {:ok, queue} = PendingInputServer.start(Keyword.put(opts, :owner, self()))
    on_exit(fn -> PendingInputServer.stop(queue) end)
    queue
  end

  defp sealed?(queue),
    do:
      Process.alive?(queue) and
        :sys.get_state(queue).sealed? and
        PendingInputServer.enqueue(queue, %{content: "Too late"}) == {:error, :closed}

  defp users(wire),
    do: wire.body["messages"] |> Enum.filter(&(&1["role"] == "user")) |> Enum.map(& &1["content"])

  defp config(mock, queue, extra \\ []),
    do:
      Config.new(
        Keyword.merge(
          [
            model: MockLLM.model(),
            tools: [],
            streaming: false,
            pending_input_server: queue,
            token_secret: "standalone-input-fixture",
            llm_opts: MockLLM.options(mock)
          ],
          extra
        )
      )

  defp opts(jido),
    do: [context: %{jido: jido, observer: self()}, limits: %{timeout: 5_000, max_tool_calls: 32}]

  defp run_task(query, config, jido) do
    observer = self()
    Task.async(fn -> JidoAI.Examples.StandaloneInput.run(query, config, %{jido: jido, observer: observer}) end)
  end

  defp eventually(fun, tries \\ 100)
  defp eventually(fun, 0), do: fun.()

  defp eventually(fun, tries),
    do:
      if(fun.(),
        do: true,
        else:
          (
            Process.sleep(10)
            eventually(fun, tries - 1)
          )
      )
end
