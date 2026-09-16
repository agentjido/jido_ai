defmodule Jido.AI.Reasoning.ChainOfDraft.StrategyTest do
  use Jido.AI.Test.ReasoningCase, async: false
  alias Jido.AI.Reasoning.ChainOfDraft

  # The old Strategy cases are mapped in docs/v3-spike/linear-test-transfer.md.
  test "uses Chain-of-Draft default prompt" do
    assert {:ok, profile} = Configuration.profile(definition(:chain_of_draft))
    assert profile.instructions == ChainOfDraft.default_system_prompt()
  end

  test "routes ai.cod.query through the shared session and owns its worker", %{jido: jido} do
    mock = mock([%{reply: {:wait, :held, {:text, "#### Done"}}}])
    server = start_reasoning(jido, :chain_of_draft)
    signal = Jido.Signal.new!("ai.cod.query", %{query: "Draft"}, source: "/test")
    assert %{id: :assistant} = Jido.AI.Authoring.request_binding(Server.agent(server), signal)
    assert {:ok, handle} = request(server, mock, :chain_of_draft)
    assert_receive {:mock_llm_waiting, ^mock, :held, _}, 2_000
    assert Process.alive?(owner(server))
    assert :ok = MockLLM.release(mock, :held)
    assert {:ok, "Done"} = Request.await(handle)
    assert_script_done(mock)
  end

  test "start commits one pending request before model work", %{jido: jido} do
    mock = mock([%{reply: {:wait, :held, {:text, "#### Done"}}}])
    server = start_reasoning(jido, :chain_of_draft)
    assert {:ok, handle} = request(server, mock, :chain_of_draft, "Solve quickly")
    assert_receive {:mock_llm_waiting, ^mock, :held, _}, 2_000
    assert %{status: :pending, method: :chain_of_draft, query: "Solve quickly"} = record(server, handle)
    assert {:ok, view} = Orchestration.snapshot(server)
    assert view.request.id == handle.id
    assert view.details.phase == :awaiting_llm
    assert Process.alive?(view.live.worker_pid)
    assert :ok = MockLLM.release(mock, :held)
    assert {:ok, "Done"} = Request.await(handle)
    assert_script_done(mock)
  end

  @tag :stable_smoke
  test "request completion extracts #### final answer", %{jido: jido} do
    mock = mock([%{reply: {:text, "20 - x = 12; x = 8. #### 8"}}])
    server = start_reasoning(jido, :chain_of_draft)
    assert {:ok, handle} = request(server, mock, :chain_of_draft)
    assert {:ok, "8"} = Request.await(handle)
    assert record(server, handle).status == :completed
    assert ChainOfDraft.get_conclusion(Server.agent(server)) == "8"
    assert record(server, handle).meta.termination_reason == :success
    assert {:ok, %{live: nil}} = Orchestration.snapshot(server)
    assert_script_done(mock)
  end

  test "provider failure stores its cause and releases the request", %{jido: jido} do
    mock = mock([%{reply: {:error, 429, "Rate limited"}}])
    server = start_reasoning(jido, :chain_of_draft)
    assert {:ok, handle} = request(server, mock, :chain_of_draft)
    assert {:error, error} = Request.await(handle)
    assert error.details.status == 429
    assert error.message =~ "Rate limited"
    assert record(server, handle).error == error
    assert record(server, handle).status == :failed
    assert {:ok, %{live: nil, details: %{phase: :request_failed}}} = Orchestration.snapshot(server)
    assert_script_done(mock)
  end

  test "busy second request returns a correlated failure without replacing the first", %{jido: jido} do
    mock = mock([%{reply: {:wait, :held, {:text, "#### First"}}}])
    server = start_reasoning(jido, :chain_of_draft)
    assert {:ok, first} = request(server, mock, :chain_of_draft)
    assert_receive {:mock_llm_waiting, ^mock, :held, _}, 2_000
    assert {:error, :busy} = request(server, mock, :chain_of_draft, "Second", request_id: "second")

    assert_receive {:jido_ai_request_event,
                    %{kind: :request_failed, request_id: "second", method: :chain_of_draft, data: %{error: :busy}}}

    assert Map.keys(Server.agent(server).state.requests) == [first.id]
    assert record(server, first).status == :pending
    assert :ok = MockLLM.release(mock, :held)
    assert {:ok, "First"} = Request.await(first)
    assert_script_done(mock)
  end
end
