defmodule Jido.AI.Reasoning.AlgorithmOfThoughts.StrategyTest do
  use Jido.AI.Test.ReasoningCase, async: false
  alias Jido.AI.Reasoning.AlgorithmOfThoughts, as: Method

  # See docs/v3-spike/aot-test-transfer.md for the old case map.
  test "initializes the native profile and default generation settings", %{jido: jido} do
    assert {:ok, profile} = Configuration.profile(definition(Method.method()))
    assert Jido.AI.Models.resolve(profile.models.answer.model) == Jido.AI.Models.resolve(:fast)
    assert %{profile: :standard, search_style: :dfs, require_explicit_answer: true} = profile.reasoning.options
    mock = mock([%{reply: {:text, "answer: 24"}}])
    server = start_reasoning(jido, Method.method())
    assert {:ok, %{details: %{phase: :idle}, request: nil}} = Orchestration.snapshot(server)
    assert {:ok, handle} = request(server, mock, Method.method())
    assert {:ok, %{answer: "24"}} = Request.await(handle)
    assert [wire] = MockLLM.report(mock).requests
    assert wire.body["temperature"] == 0.0 and wire.body["max_tokens"] == 2048
    assert_script_done(mock)
  end

  test "custom AoT profile search style and generation reach the provider", %{jido: jido} do
    mock = mock([%{reply: {:text, "answer: 24"}}])

    server =
      start_reasoning(jido, Method.method(),
        reasoning_options: %{profile: :short, search_style: :bfs},
        max_tokens: 4096,
        temperature: 0.1
      )

    assert {:ok, handle} = request(server, mock, Method.method())
    assert {:ok, %{answer: "24"}} = Request.await(handle)
    assert [wire] = MockLLM.report(mock).requests
    assert wire.body["temperature"] == 0.1 and wire.body["max_tokens"] == 4096
    assert hd(wire.body["messages"])["content"] == Method.default_system_prompt(:short, :bfs)
    assert_script_done(mock)
  end

  test "native Actions validate admission and cancellation inputs" do
    assert Jido.AI.Orchestration.Start.name() == "ai_session_start"
    assert Jido.AI.Orchestration.Cancel.name() == "ai_session_cancel"
    assert {:ok, _} = Zoi.parse(Jido.AI.Orchestration.Start.schema(), %{query: "Solve", request_id: "one"})
    assert {:error, _} = Zoi.parse(Jido.AI.Orchestration.Start.schema(), %{query: "Solve"})
    assert {:ok, _} = Zoi.parse(Jido.AI.Orchestration.Cancel.schema(), %{request_id: "one", reason: :changed_plan})
  end

  test "AoT query routes select the method and model observations stay read only", %{jido: jido} do
    server = start_reasoning(jido, Method.method())
    before = Server.agent(server)
    signal = Jido.Signal.new!("ai.aot.query", %{query: "Solve"}, source: "/test")
    assert %{id: :assistant, mode: :session} = Jido.AI.Authoring.request_binding(before, signal)
    assert Jido.AI.Authoring.request_method(before, signal) == Method.method()

    for type <- ["ai.llm.response", "ai.llm.delta"] do
      assert {:ok, after_agent} = Server.call(server, %{signal | type: type})
      assert after_agent.state == before.state
    end

    assert {:ok, %{request: nil}} = Orchestration.snapshot(server)
  end

  test "start owns a streaming call with a correlated request and prompt", %{jido: jido} do
    mock = mock([%{reply: {:stream, [%{content: "Trying"}, {:wait, :held}, %{content: "\nanswer: 24"}], "stop"}}])
    server = start_reasoning(jido, Method.method(), streaming: true, observability: %{diagnostics_content: true})
    assert {:ok, handle} = request(server, mock, Method.method(), "Solve this")
    assert_receive {:mock_llm_waiting, ^mock, :held, _}, 2_000
    assert {:ok, view} = Orchestration.snapshot(server, include_content: true)
    assert view.request.query == "Solve this" and view.request.status == :pending
    assert is_binary(view.details.current_llm_call_id)
    assert Process.alive?(view.live.worker_pid)
    assert_receive {:jido_ai_request_event, %{kind: :llm_delta} = delta}, 1_000
    assert delta.llm_call_id == view.details.current_llm_call_id
    assert delta.request_id == handle.id and delta.method == :algorithm_of_thoughts
    assert :ok = MockLLM.release(mock, :held)
    assert {:ok, %{answer: "24"}} = Request.await(handle)
    assert record(server, handle).meta.model_calls == 1
    assert_script_done(mock)
  end

  test "a busy second start returns its own request ID", %{jido: jido} do
    mock = mock([%{reply: {:wait, :held, {:text, "answer: 24"}}}])
    server = start_reasoning(jido, Method.method())
    assert {:ok, first} = request(server, mock, Method.method(), "first", request_id: "req_aot_1")
    assert_receive {:mock_llm_waiting, ^mock, :held, _}, 2_000
    assert {:error, :busy} = request(server, mock, Method.method(), "second", request_id: "req_aot_2")
    assert_receive {:jido_ai_request_event, %{kind: :request_failed, request_id: "req_aot_2", data: %{error: :busy}}}
    assert record(server, first).status == :pending
    assert :ok = MockLLM.release(mock, :held)
    assert {:ok, %{answer: "24"}} = Request.await(first)
    assert_script_done(mock)
  end

  test "rejection metadata does not overwrite the active AoT request", %{jido: jido} do
    mock = mock([%{reply: {:wait, :held, {:text, "answer: 24"}}}])
    server = start_reasoning(jido, Method.method())
    assert {:ok, first} = request(server, mock, Method.method())
    assert_receive {:mock_llm_waiting, ^mock, :held, _}, 2_000
    assert {:error, :busy} = request(server, mock, Method.method(), "second", request_id: "busy_aot")

    assert_receive {:jido_ai_request_event,
                    %{request_id: "busy_aot", method: :algorithm_of_thoughts, data: %{error: :busy}}}

    assert Map.keys(Server.agent(server).state.requests) == [first.id]
    assert length(MockLLM.report(mock).requests) == 1
    assert :ok = MockLLM.release(mock, :held)
    assert {:ok, %{answer: "24"}} = Request.await(first)
    assert_script_done(mock)
  end

  test "model completion stores the parsed puzzle result and usage", %{jido: jido} do
    text = """
    Trying a promising first operation:
    1. 8 - 6 : (4, 4, 2)
    - 4 + 2 : (6, 4) 24 = 6 * 4 -> found it!
    Backtracking the solution:
    Step 1: 8 - 6 = 2
    Step 2: 4 + 2 = 6
    Step 3: 6 * 4 = 24
    answer: (4 + (8 - 6)) * 4 = 24
    """

    mock = mock([%{reply: response(text, %{prompt_tokens: 4, completion_tokens: 9, total_tokens: 13})}])
    server = start_reasoning(jido, Method.method())
    assert {:ok, handle} = request(server, mock, Method.method())
    assert {:ok, result} = Request.await(handle)
    assert result.answer == "(4 + (8 - 6)) * 4 = 24"
    assert result.usage.total_tokens == 13
    assert result.first_operations_considered == 1 and result.backtracking_steps == 3
    assert result.raw_response == text and result.found_solution?
    assert record(server, handle).status == :completed
    assert Method.get_result(Server.agent(server)) == result
    assert_script_done(mock)
  end

  test "snapshot of a new AoT Agent has no result or live request", %{jido: jido} do
    server = start_reasoning(jido, Method.method())
    assert {:ok, view} = Orchestration.snapshot(server)
    assert view.details.phase == :idle and view.request == nil and view.live == nil
    assert Method.get_result(view.agent) == nil
    refute view.agent.state.completed
  end

  test "snapshot of running work keeps the selected long profile", %{jido: jido} do
    mock = mock([%{reply: {:wait, :held, {:text, "answer: 24"}}}])
    server = start_reasoning(jido, Method.method(), reasoning_options: %{profile: :long})
    assert {:ok, handle} = request(server, mock, Method.method(), "Test")
    assert_receive {:mock_llm_waiting, ^mock, :held, _}, 2_000
    assert {:ok, view} = Orchestration.snapshot(server)
    assert view.details.phase == :awaiting_llm and view.request.status == :pending
    assert {:ok, profile} = Configuration.profile(view.agent)
    assert profile.reasoning.options.profile == :long
    refute view.agent.state.completed

    assert hd(hd(MockLLM.report(mock).requests).body["messages"])["content"] ==
             Method.default_system_prompt(:long, :dfs)

    assert :ok = MockLLM.release(mock, :held)
    assert {:ok, %{answer: "24"}} = Request.await(handle)
    assert_script_done(mock)
  end

  test "public method selection replaces private Strategy action atoms" do
    assert Method.method() == :algorithm_of_thoughts
    agent = definition(Method.method())
    assert {:ok, router} = Jido.Signal.Router.new(agent.routes)

    for type <- ["ai.aot.query", Orchestration.cancel_type()] do
      assert {:ok, _} = Jido.Signal.Router.route(router, Jido.Signal.new!(type, %{}, source: "/test"))
    end

    assert {:error, _} = Jido.Signal.Router.route(router, Jido.Signal.new!("ai.aot.unknown", %{}, source: "/test"))
  end
end
