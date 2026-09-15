defmodule JidoAI.Examples.StreamingTest do
  use JidoAI.Examples.Case
  alias JidoAI.Examples.Streaming.Agent
  alias Jido.AI.{Request, Orchestration}

  test "public stream events precede the complete answer commit", %{jido: jido} do
    {mock, context} = native_mock([%{reply: {:stream, [%{content: "First "}, {:wait, :middle}, %{content: "last"}]}}])
    server = start_agent(jido, Agent.new!())

    assert {:ok, %{request: request, events: events}} =
             Agent.ask_stream(server, "Help", context: context, model: MockLLM.model())

    id = request.id
    assert_receive {:mock_llm_waiting, ^mock, :middle, worker}, 5_000
    monitor = Process.monitor(worker)
    assert_receive {:jido_ai_request_event, %{request_id: ^id, kind: :llm_delta, data: %{delta: "First "}}}, 5_000
    assert Server.agent(server).state.answer == ""
    :ok = MockLLM.release(mock, :middle)
    assert {:ok, "First last"} = Request.await(request)
    collected = Enum.to_list(events)
    assert List.last(collected).kind == :request_completed
    assert Enum.all?(collected, &(&1.request_id == id))
    assert Server.agent(server).state.answer == "First last"
    assert Server.agent(server).state.case_id == "case-42"
    assert_receive {:DOWN, ^monitor, :process, ^worker, _}, 5_000
    assert_script_done(mock)
  end

  test "public cancellation closes transport, preserves the answer, and permits new work", %{jido: jido} do
    {mock, context} =
      native_mock([
        %{reply: {:stream, [%{content: "Partial"}, {:wait, :cancel}]}},
        %{reply: {:stream, [%{content: "Recovered"}]}}
      ])

    server = start_agent(jido, Agent.new!(state: %{answer: "Previous", case_id: "existing"}))

    assert {:ok, %{request: request, events: events}} =
             Agent.ask_stream(server, "Help", context: context, model: MockLLM.model())

    assert_receive {:mock_llm_waiting, ^mock, :cancel, worker}, 5_000
    monitor = Process.monitor(worker)
    assert :ok = Orchestration.cancel(request)
    assert {:error, :cancelled} = Request.await(request)
    assert List.last(Enum.to_list(events)).kind == :request_cancelled
    assert_receive {:DOWN, ^monitor, :process, ^worker, _}, 5_000
    assert_receive {:mock_llm_closed, ^mock, ^worker}, 5_000
    assert Server.agent(server).state.answer == "Previous"
    assert Server.agent(server).state.case_id == "existing"
    assert {:ok, "Recovered"} = Agent.ask_sync(server, "Next", context: context, model: MockLLM.model())
    assert_script_done(mock)
  end
end
