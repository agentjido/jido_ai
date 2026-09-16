defmodule JidoAI.Examples.FailurePositionTest do
  use JidoAI.Examples.Case
  alias Jido.AI.{Request, Orchestration}
  alias Jido.AI.Reasoning.ReAct
  alias ReAct.{Config, Token}
  alias JidoAI.Examples.FailurePosition.Fault, as: Example
  alias JidoAI.Examples.StandaloneAuthoring.Add
  alias JidoAI.Examples.CheckpointResume

  test "first provider failure keeps reasoning position one and one started model", %{jido: jido} do
    {mock, _} = mock([failure()])
    config = config(mock)
    result = ReAct.run("Fail", config, opts(jido))
    assert_position(result, config, 1, 1)
    assert_script_done(mock)
  end

  test "first request-transform failure keeps position one with no model operation", %{jido: jido} do
    {mock, _} = mock([])
    config = config(mock)
    result = ReAct.run("Reject", config, opts(jido, reject_position: 1))
    assert_position(result, config, 1, 0)
    assert_script_done(mock)
  end

  test "provider failure after tools keeps the next reasoning position and both model calls", %{
    jido: jido
  } do
    {mock, _} = mock([tool(), failure()])
    config = config(mock, tools: [Add])
    result = ReAct.run("Sum", config, opts(jido))
    assert_position(result, config, 2, 2)
    assert_receive {:standalone_add, _, 2, 3}
    assert_script_done(mock)
  end

  test "request-transform failure after tools keeps the next position before another model starts",
       %{jido: jido} do
    {mock, _} = mock([tool()])
    config = config(mock, tools: [Add])
    result = ReAct.run("Sum", config, opts(jido, reject_position: 2))
    assert_position(result, config, 2, 1)
    assert_receive {:standalone_add, _, 2, 3}
    assert_script_done(mock)
  end

  for repairs <- [1, 2] do
    test "failure on repair model #{repairs} keeps reasoning position one", %{jido: jido} do
      count = unquote(repairs)
      {mock, _} = mock(List.duplicate(invalid(), count) ++ [failure()])
      config = config(mock, output: output(count))
      result = ReAct.run("Repair", config, opts(jido))
      assert_position(result, config, 1, count + 1)
      assert result.usage.total_tokens == count * 15
      assert_script_done(mock)
    end
  end

  test "repair validation failure after two model calls retains reasoning position one", %{
    jido: jido
  } do
    {mock, _} = mock([invalid(), invalid()])
    config = config(mock, output: output(1))
    result = ReAct.run("Repair", config, opts(jido))
    assert_position(result, config, 1, 2)
    assert result.usage.total_tokens == 30
    assert_script_done(mock)
  end

  test "repair transform failure keeps its reasoning position without a second model operation",
       %{jido: jido} do
    {mock, _} = mock([invalid()])
    config = config(mock, output: output(1))
    result = ReAct.run("Repair", config, opts(jido, reject_repair: true))
    assert_position(result, config, 1, 1)
    assert_script_done(mock)
  end

  test "a local repair callback failure does not advance reasoning or model counters", %{
    jido: jido
  } do
    {mock, _} = mock([invalid()])
    config = config(mock, output: Map.put(output(1), :repair_fun, {Example, :repair_failure}))
    result = ReAct.run("Repair", config, opts(jido))
    assert_position(result, config, 1, 1)
    assert inspect(result.result) =~ "local_repair_failed"
    assert_script_done(mock)
  end

  test "failed repair after a tool round retains reasoning position two and three model calls", %{
    jido: jido
  } do
    {mock, _} = mock([tool(), invalid(), failure()])
    config = config(mock, tools: [Add], output: output(1))
    result = ReAct.run("Sum then repair", config, opts(jido))
    assert_position(result, config, 2, 3)
    assert_receive {:standalone_add, _, 2, 3}
    assert_script_done(mock)
  end

  for stop <- [:cancel, :worker, :parent] do
    test "#{stop} during model repair retains the observed reasoning position", %{jido: jido} do
      {mock, _} = mock([invalid(), %{reply: {:wait, :repair, {:text, "Unused"}}}])
      config = config(mock, output: output(1))
      options = opts(jido)
      task = Task.async(fn -> ReAct.run("Hold repair", config, options) end)
      assert_receive {:reasoning_position, 1, :running, server}, 2_000
      assert_receive {:reasoning_position, 1, :completed, ^server}, 2_000
      assert_receive {:mock_llm_waiting, ^mock, :repair, provider}, 2_000
      monitor = Process.monitor(provider)
      owner = Server.children(server)[{:plugin, Jido.AI.Orchestration.Plugin}].pid
      [{id, job}] = Map.to_list(:sys.get_state(owner).jobs)

      case unquote(stop) do
        :cancel ->
          assert :ok =
                   Orchestration.cancel(%Request.Handle{id: id, server: server, query: "Hold repair"})

        :worker ->
          Process.exit(job.task.pid, :kill)

        :parent ->
          GenServer.stop(server, :normal)
      end

      result = Task.await(task, 5_000)
      assert_receive {:DOWN, ^monitor, :process, ^provider, _}, 2_000
      assert {:ok, saved, _} = Token.decode_state(result.final_token, config)
      assert saved.iteration == 1
      assert saved.status == unquote(if(stop == :cancel, do: :cancelled, else: :failed))
      assert saved.usage.total_tokens == 15
      assert saved.checkpoint == nil
      assert Enum.count(result.trace, &(&1.kind == :llm_started)) == 2
      last_model = Enum.filter(result.trace, &(&1.kind == :llm_started)) |> List.last()
      assert last_model.data.reasoning_iteration == 1 and last_model.iteration == 2
      if unquote(stop) != :parent, do: assert_position(result, config, 1, 2)
      assert_script_done(mock)
    end
  end

  test "a resumed after-tools checkpoint keeps position two when transform rejects before the model",
       %{jido: jido} do
    {mock, _} = mock([tool()])
    config = config(mock, tools: [Add])

    events =
      ReAct.stream("Sum", config, opts(jido)) |> CheckpointResume.through_checkpoint(:after_tools)

    assert {:ok, next} =
             ReAct.continue(List.last(events).data.token, config, opts(jido, reject_position: 2))

    result = ReAct.collect_stream(next.events)
    assert_position(result, config, 2, 1, 0)
    assert_script_done(mock)
  end

  test "successful repair keeps the same position in terminal metadata and State", %{jido: jido} do
    {mock, _} = mock([invalid(), %{reply: {:object, %{answer: "Fixed"}}}])
    config = config(mock, output: output(1))
    result = ReAct.run("Repair", config, opts(jido))
    assert result.result == %{answer: "Fixed"}
    assert_position(result, config, 1, 2)
    assert_script_done(mock)
  end

  test "input received with a final answer keeps the next position when the next transform fails",
       %{jido: jido} do
    queue = start_supervised!({Jido.AI.PendingInputServer, owner: self()})
    {mock, _} = mock([%{reply: {:wait, :final_answer, {:text, "First"}}}])
    config = config(mock, pending_input_server: queue)
    options = opts(jido, reject_position: 2)
    task = Task.async(fn -> ReAct.run("First", config, options) end)
    assert_receive {:mock_llm_waiting, ^mock, :final_answer, _}, 2_000
    assert :ok = Jido.AI.PendingInputServer.enqueue(queue, %{content: "Next"})
    assert :ok = MockLLM.release(mock, :final_answer)
    result = Task.await(task, 5_000)
    assert_position(result, config, 2, 1)
    assert Enum.any?(result.trace, &(&1.kind == :input_injected))
    assert_script_done(mock)
  end

  test "append after a repair checkpoint advances one reasoning position without resetting model calls",
       %{jido: jido} do
    {mock, _} = mock([invalid(), %{reply: {:object, %{answer: "Saved repair"}}}])
    config = config(mock, output: output(1))

    events =
      ReAct.stream("Repair", config, opts(jido))
      |> CheckpointResume.through_checkpoint(:after_llm, 2)

    options = opts(jido, reject_position: 2) |> Keyword.put(:query, "Next")
    assert {:ok, next} = ReAct.continue(List.last(events).data.token, config, options)
    result = ReAct.collect_stream(next.events)
    assert_position(result, config, 2, 2, 0)
    assert_script_done(mock)
  end

  defp assert_position(result, config, position, calls, new_calls \\ nil) do
    assert {:ok, ^position} = JidoAI.Examples.FailurePosition.saved_position(result.final_token, config)
    assert {:ok, state, _} = Token.decode_state(result.final_token, config)
    assert state.iteration == position
    terminal = Enum.find(result.trace, &Request.Stream.terminal_kind?(&1.kind))
    assert terminal.data.meta.reasoning_iteration == position
    assert terminal.data.meta.model_calls == calls
    assert terminal.data.reasoning_iteration == position
    assert Enum.count(result.trace, &(&1.kind == :llm_started)) == (new_calls || calls)

    assert Enum.all?(
             Enum.filter(result.trace, &(&1.kind == :llm_started)),
             &is_integer(&1.data[:reasoning_iteration])
           )
  end

  defp failure, do: %{reply: {:error, 400, "Provider failure"}}
  defp invalid, do: %{reply: {:object, %{answer: 42}}}
  defp tool, do: %{reply: {:tools, [%{id: "sum", name: "add", arguments: %{a: 2, b: 3}}]}}

  defp output(retries),
    do: %{
      schema: Zoi.object(%{answer: Zoi.string()}),
      retries: retries,
      on_validation_error: :repair
    }

  defp config(mock, extra \\ []),
    do:
      Config.new(
        Keyword.merge(
          [
            model: MockLLM.model(),
            tools: [],
            streaming: false,
            request_transformer: Example,
            stream_content: true,
            store_content: true,
            token_secret: "failure-position-case",
            llm_opts: MockLLM.options(mock)
          ],
          extra
        )
      )

  defp opts(jido, extra \\ []),
    do: [
      context: Map.merge(%{jido: jido, observer: self()}, Map.new(extra)),
      limits: %{timeout: 5_000, max_tool_calls: 32}
    ]
end
