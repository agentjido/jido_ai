defmodule JidoAI.Examples.StreamingTest do
  use JidoAI.Examples.Case, async: true
  alias JidoAI.Examples.Streaming

  test "SSE deltas arrive before the final live commit", %{jido: jido} do
    {mock, context} =
      mock([%{reply: {:stream, [%{content: "First "}, {:wait, :middle}, %{content: "last"}]}}])

    server = start_agent(jido, Streaming.Agent.new!())
    before = Server.snapshot(server)
    task = Task.async(fn -> ask(server, context) end)
    assert_receive {:mock_llm_waiting, ^mock, :middle, _}, 5_000
    assert_receive {:stream_opened, _}, 5_000
    assert_receive {:token, "First "}, 5_000
    assert Server.snapshot(server) == before
    :ok = MockLLM.release(mock, :middle)
    assert {:ok, agent} = Task.await(task, 5_000)
    assert agent.state == %{answer: "First last", commits: 1, case_id: "case-42"}
    assert Server.snapshot(server) == %{agent: agent, state_version: 1}
    assert_script_done(mock)
  end

  test "live cancellation preserves state and closes owned provider work", %{jido: jido} do
    {mock, context} = mock([%{reply: {:stream, [%{content: "Partial"}, {:wait, :cancel}]}}])
    server = start_agent(jido, Streaming.Agent.new!())
    before = Server.snapshot(server)
    task = Task.async(fn -> ask(server, context) end)
    assert_receive {:mock_llm_waiting, ^mock, :cancel, worker}, 5_000
    monitor = Process.monitor(worker)
    assert_receive {:stream_opened, _stream}, 5_000
    assert_receive {:token, "Partial"}, 5_000
    assert :ok = Server.cancel(server)
    assert {:error, _} = Task.await(task, 5_000)
    assert Server.snapshot(server) == before
    assert_receive {:DOWN, ^monitor, :process, ^worker, _}, 5_000
    assert_receive {:mock_llm_closed, ^mock, ^worker}, 1_000
    assert_script_done(mock)
  end
end
