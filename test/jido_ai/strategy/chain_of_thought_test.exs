defmodule Jido.AI.Reasoning.ChainOfThought.StrategyTest do
  use Jido.AI.Test.ReasoningCase, async: false
  alias Jido.AI.Reasoning.ChainOfThought
  alias ReqLLM.Message.ContentPart

  # Each removed Strategy case has a native replacement in linear-test-transfer.md.
  test "initializes an idle Agent with no request worker", %{jido: jido} do
    server = start_reasoning(jido, :chain_of_thought)
    assert {:ok, view} = Orchestration.snapshot(server)
    assert view.request == nil and view.live == nil
    assert view.details.phase == :idle
    assert ChainOfThought.get_steps(view.agent) == []
    assert Process.alive?(owner(server))
    assert view.agent.state.requests == %{}
  end

  test "uses the default model when not specified" do
    assert {:ok, profile} = Configuration.profile(definition(:chain_of_thought))
    assert Jido.AI.Models.resolve(profile.models.answer.model) == Jido.AI.Models.resolve(:fast)
  end

  test "resolves a model alias before the provider request", %{jido: jido} do
    previous = Application.fetch_env(:jido_ai, :model_aliases)
    Application.put_env(:jido_ai, :model_aliases, %{linear_test: MockLLM.model()})

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:jido_ai, :model_aliases, value)
        :error -> Application.delete_env(:jido_ai, :model_aliases)
      end
    end)

    mock = mock([%{reply: {:text, "Conclusion: 4"}}])
    server = start_reasoning(jido, :chain_of_thought, model: :linear_test)

    assert {:ok, handle} =
             Request.create_and_send(server, "Add",
               signal_type: "ai.cot.query",
               source: "/test",
               llm_opts: MockLLM.options(mock)
             )

    assert {:ok, "4"} = Request.await(handle)
    assert [%{body: %{"model" => "gpt-4o-mini"}}] = MockLLM.report(mock).requests
    assert_script_done(mock)
  end

  for {name, opts} <- [{"not provided", []}, {"false", [system_prompt: false]}, {"nil", [system_prompt: nil]}] do
    test "uses the default prompt when #{name}" do
      assert {:ok, profile} = Configuration.profile(definition(:chain_of_thought, unquote(opts)))
      assert profile.instructions == ChainOfThought.default_system_prompt()
    end
  end

  test "rejects a non-text prompt during definition validation" do
    assert_raise Jido.AI.Error.Validation.Invalid,
                 ~r/instructions: Expected text, an Action module, or nil/,
                 fn ->
                   definition(:chain_of_thought, system_prompt: 123)
                 end
  end

  test "the start Action validates a query and request ID before admission" do
    assert Jido.AI.Orchestration.Start.name() == "ai_session_start"

    assert {:ok, %{query: "Add", request_id: "one"}} =
             Zoi.parse(Jido.AI.Orchestration.Start.schema(), %{query: "Add", request_id: "one"})

    assert {:error, _} = Zoi.parse(Jido.AI.Orchestration.Start.schema(), %{query: "Add"})
    assert {:error, _} = Zoi.parse(Jido.AI.Orchestration.Start.schema(), %{query: 123, request_id: "one"})
  end

  test "legacy model observations do not start work or change domain state", %{jido: jido} do
    server = start_reasoning(jido, :chain_of_thought)
    before = Server.agent(server).state

    for type <- ["ai.llm.response", "ai.llm.delta", "ai.request.started", "ai.request.completed", "ai.request.failed"] do
      signal = Jido.Signal.new!(type, %{request_id: "unowned", result: "forged"}, source: "/test")
      assert {:ok, agent} = Server.call(server, signal)
      assert agent.state == before
    end

    assert {:ok, %{request: nil, live: nil}} = Orchestration.snapshot(server)
  end

  test "query routes bind the CoT profile to the shared session", %{jido: jido} do
    server = start_reasoning(jido, :chain_of_thought)
    signal = Jido.Signal.new!("ai.cot.query", %{query: "Add"}, source: "/test")
    assert %{id: :assistant, mode: :session} = Jido.AI.Authoring.request_binding(Server.agent(server), signal)
    assert Jido.AI.Authoring.request_method(Server.agent(server), signal) == :chain_of_thought
    assert {:ok, router} = Jido.Signal.Router.new(Server.agent(server).routes)
    assert {:ok, _} = Jido.Signal.Router.route(router, %{signal | type: Orchestration.cancel_type()})
  end

  test "start commits the prompt and request before a worker runs", %{jido: jido} do
    mock = mock([%{reply: {:wait, :held, {:text, "Conclusion: 4"}}}])
    server = start_reasoning(jido, :chain_of_thought)
    assert {:ok, handle} = request(server, mock, :chain_of_thought)
    assert_receive {:mock_llm_waiting, ^mock, :held, _}, 2_000
    assert %{status: :pending, query: "What is 2 + 2?"} = record(server, handle)
    assert {:ok, view} = Orchestration.snapshot(server)
    assert view.details.active_request_id == handle.id
    assert view.details.phase == :awaiting_llm
    assert Process.alive?(view.live.worker_pid)
    assert :ok = MockLLM.release(mock, :held)
    assert {:ok, "4"} = Request.await(handle)
    assert_script_done(mock)
  end

  test "the owned worker receives the prompt exactly once", %{jido: jido} do
    mock = mock([%{reply: {:wait, :held, {:text, "Conclusion: 4"}}}])
    server = start_reasoning(jido, :chain_of_thought)
    assert {:ok, handle} = request(server, mock, :chain_of_thought, "Test prompt")
    assert_receive {:mock_llm_waiting, ^mock, :held, _}, 2_000
    assert [wire] = MockLLM.report(mock).requests
    assert Enum.count(wire.body["messages"], &(&1["role"] == "user" and &1["content"] == "Test prompt")) == 1
    assert :ok = MockLLM.release(mock, :held)
    assert {:ok, "4"} = Request.await(handle)
    assert length(MockLLM.report(mock).requests) == 1
    assert record(server, handle).meta.model_calls == 1
    assert_script_done(mock)
  end

  test "completion parses steps and conclusion and stores usage", %{jido: jido} do
    mock = mock([%{reply: {:text, "Step 1: Add.\nConclusion: 4"}}])
    server = start_reasoning(jido, :chain_of_thought)
    assert {:ok, handle} = request(server, mock, :chain_of_thought)
    assert {:ok, "4"} = Request.await(handle)
    rec = record(server, handle)
    assert rec.status == :completed and rec.meta.termination_reason == :success
    assert rec.meta.reasoning.steps == [%{number: 1, content: "Add."}]
    assert rec.meta.reasoning.conclusion == "4"
    assert %{input_tokens: 10, output_tokens: 5} = rec.meta.usage
    assert {:ok, %{live: nil, details: %{active_request_id: nil}}} = Orchestration.snapshot(server)
    assert_script_done(mock)
  end

  test "the shared usage merge keeps nested provider counters and metadata", %{jido: jido} do
    first = %{
      input_tokens: 10,
      output_tokens: 5,
      total_cost: 0.001,
      add_reasoning_to_cost: false,
      cost: %{total: 0.001, input_cost: 0.0008, line_items: [%{id: "first"}]},
      tool_usage: %{calls: 1}
    }

    second = %{
      input_tokens: 7,
      output_tokens: 3,
      total_cost: 0.002,
      add_reasoning_to_cost: true,
      cost: %{total: 0.002, input_cost: 0.0015, line_items: [%{id: "second"}]},
      tool_usage: %{calls: 2}
    }

    assert Jido.AI.Usage.merge(first, second) == %{
             input_tokens: 17,
             output_tokens: 8,
             total_cost: 0.003,
             add_reasoning_to_cost: true,
             cost: %{total: 0.003, input_cost: 0.0023, line_items: [%{id: "second"}]},
             tool_usage: %{calls: 3}
           }

    # The real two-call repair path must use the same accumulator.
    mock =
      mock([
        %{reply: response("invalid", %{prompt_tokens: 10, completion_tokens: 5, total_tokens: 15})},
        %{reply: response(~s({"answer": 4}), %{prompt_tokens: 7, completion_tokens: 3, total_tokens: 10})}
      ])

    server = start_reasoning(jido, :chain_of_thought, output: [schema: Zoi.object(%{answer: Zoi.integer()})])
    assert {:ok, handle} = request(server, mock, :chain_of_thought)
    assert {:ok, %{answer: 4}} = Request.await(handle)
    assert record(server, handle).meta.model_calls == 2
    assert %{input_tokens: 17, output_tokens: 8, total_tokens: 25} = record(server, handle).meta.usage
    assert_script_done(mock)
  end

  test "streamed deltas preserve request run call and sequence IDs", %{jido: jido} do
    mock =
      mock([%{reply: {:stream, [%{content: "Step 1: Add."}, {:wait, :held}, %{content: "\nConclusion: 4"}], "stop"}}])

    server = start_reasoning(jido, :chain_of_thought, streaming: true)
    assert {:ok, handle} = request(server, mock, :chain_of_thought)
    assert_receive {:mock_llm_waiting, ^mock, :held, _}, 2_000
    assert_receive {:jido_ai_request_event, %{kind: :llm_delta} = delta}, 1_000
    assert delta.data.delta == "Step 1: Add." and delta.data.chunk_type == :content
    assert delta.request_id == handle.id and delta.run_id == record(server, handle).run_id
    assert delta.method == :chain_of_thought
    assert_receive {:signal, %{type: "ai.llm.delta", data: data}}, 1_000
    assert data.call_id == delta.llm_call_id and is_binary(data.call_id)
    assert data.seq == delta.seq and data.run_id == delta.run_id and data.request_id == handle.id
    assert data.delta == delta.data.delta and data.chunk_type == :content
    assert :ok = MockLLM.release(mock, :held)
    assert {:ok, "4"} = Request.await(handle)
    all = Enum.sort_by([delta | events(handle)], & &1.seq)
    assert Enum.map(all, & &1.seq) == Enum.to_list(1..length(all))
    assert List.last(all).kind == :request_completed
    assert_script_done(mock)
  end

  test "complete content parts reach both streams and the stored multimodal result", %{jido: jido} do
    image = ContentPart.image(<<1, 2, 3>>, "image/png")
    delta = %{images: [%{type: "image_url", image_url: %{url: "data:image/png;base64,AQID"}}]}
    mock = mock([%{reply: {:stream, [delta, {:wait, :held}], "stop"}}])

    server =
      start_reasoning(jido, :chain_of_thought,
        streaming: true,
        observability: %{stream_content: true, store_content: true}
      )

    assert {:ok, handle} = request(server, mock, :chain_of_thought)
    assert_receive {:mock_llm_waiting, ^mock, :held, _}, 2_000

    assert_receive {:jido_ai_request_event, %{kind: :llm_delta, data: %{chunk_type: :content_part, delta: ^image}}},
                   1_000

    assert_receive {:signal, %{type: "ai.llm.delta", data: %{chunk_type: :content_part, delta: ^image}}}, 1_000
    assert {:ok, active} = Orchestration.snapshot(server)
    assert active.details.streaming_text == ""
    assert :ok = MockLLM.release(mock, :held)
    assert {:ok, [^image]} = Request.await(handle)
    assert record(server, handle).result == [image]
    assert ChainOfThought.get_steps(Server.agent(server)) == []
    assert ChainOfThought.get_raw_response(Server.agent(server)) == ""
    assert :ok = Jido.Action.validate_static_data(Server.agent(server).state)
    assert_script_done(mock)
  end

  test "provider failure keeps the error and releases active work", %{jido: jido} do
    mock = mock([%{reply: {:error, 429, "Rate limited"}}])
    server = start_reasoning(jido, :chain_of_thought)
    assert {:ok, handle} = request(server, mock, :chain_of_thought)
    assert {:error, error} = Request.await(handle)
    assert error.details.status == 429 and error.message =~ "Rate limited"
    assert record(server, handle).status == :failed and record(server, handle).error == error

    assert {:ok, %{live: nil, details: %{active_request_id: nil, phase: :request_failed}}} =
             Orchestration.snapshot(server)

    assert_script_done(mock)
  end

  test "cancellation keeps its reason and closes the provider connection", %{jido: jido} do
    mock = mock([%{reply: {:wait, :held, {:text, "unused"}}}])
    server = start_reasoning(jido, :chain_of_thought)
    assert {:ok, handle} = request(server, mock, :chain_of_thought)
    assert_receive {:mock_llm_waiting, ^mock, :held, provider}, 2_000
    monitor = Process.monitor(provider)
    assert :ok = Orchestration.cancel(handle, reason: :user_cancelled)
    assert {:error, {:cancelled, :user_cancelled}} = Request.await(handle)
    assert record(server, handle).error == {:cancelled, :user_cancelled}
    assert_receive {:DOWN, ^monitor, :process, ^provider, _}, 2_000

    assert {:ok, %{live: nil, details: %{active_request_id: nil, cancel_reason: :user_cancelled}}} =
             Orchestration.snapshot(server)

    eventually(fn -> MockLLM.report(mock).waiting == [] end)
    assert_script_done(mock)
  end

  test "rejection metadata identifies only the refused request", %{jido: jido} do
    mock = mock([%{reply: {:wait, :held, {:text, "Conclusion: First"}}}])
    server = start_reasoning(jido, :chain_of_thought)
    assert {:ok, first} = request(server, mock, :chain_of_thought)
    assert_receive {:mock_llm_waiting, ^mock, :held, _}, 2_000
    assert {:error, :busy} = request(server, mock, :chain_of_thought, "Second", request_id: "second")

    assert_receive {:jido_ai_request_event,
                    %{request_id: "second", kind: :request_failed, method: :chain_of_thought, data: %{error: :busy}}}

    assert record(server, first).status == :pending
    refute Map.has_key?(Server.agent(server).state.requests, "second")
    assert :ok = MockLLM.release(mock, :held)
    assert {:ok, "First"} = Request.await(first)
    assert_script_done(mock)
  end

  test "a worker crash fails its request and permits a later request", %{jido: jido} do
    mock = mock([%{reply: {:wait, :held, {:text, "unused"}}}, %{reply: {:text, "Conclusion: Next"}}])
    server = start_reasoning(jido, :chain_of_thought)
    assert {:ok, first} = request(server, mock, :chain_of_thought)
    assert_receive {:mock_llm_waiting, ^mock, :held, provider}, 2_000
    monitor = Process.monitor(provider)
    assert {:ok, view} = Orchestration.snapshot(server)
    Process.exit(view.live.worker_pid, :kill)
    assert {:error, :worker_crash} = Request.await(first)
    assert record(server, first).error == :worker_crash
    assert_receive {:DOWN, ^monitor, :process, ^provider, _}, 2_000
    assert {:ok, %{live: nil, details: %{active_request_id: nil}}} = Orchestration.snapshot(server)
    assert {:ok, next} = request(server, mock, :chain_of_thought, "Next")
    assert {:ok, "Next"} = Request.await(next)
    eventually(fn -> MockLLM.report(mock).waiting == [] end)
    assert_script_done(mock)
  end

  test "busy admission consumes no extra model call", %{jido: jido} do
    mock = mock([%{reply: {:wait, :held, {:text, "Conclusion: First"}}}])
    server = start_reasoning(jido, :chain_of_thought)
    assert {:ok, first} = request(server, mock, :chain_of_thought)
    assert_receive {:mock_llm_waiting, ^mock, :held, _}, 2_000
    assert {:error, :busy} = request(server, mock, :chain_of_thought, "Second")
    assert Map.keys(Server.agent(server).state.requests) == [first.id]
    assert length(MockLLM.report(mock).requests) == 1
    assert :ok = MockLLM.release(mock, :held)
    assert {:ok, "First"} = Request.await(first)
    assert_script_done(mock)
  end

  test "the trace keeps its first 2000 events and records overflow through completion", %{jido: jido} do
    mock = mock([%{reply: {:wait, :held, {:text, "Conclusion: Done"}}}])
    server = start_reasoning(jido, :chain_of_thought)
    assert {:ok, handle} = request(server, mock, :chain_of_thought)
    assert_receive {:mock_llm_waiting, ^mock, :held, _}, 2_000
    assert {:ok, view} = Orchestration.snapshot(server)

    for n <- 1..2_010 do
      assert :ok =
               GenServer.call(
                 owner(server),
                 {:event, handle.id, view.request.run_id, :llm_delta, %{delta: "x", chunk_type: :content, n: n}}
               )
    end

    assert {:ok, active} = Orchestration.snapshot(server)
    assert active.details.trace.truncated?
    assert Enum.map(active.details.trace.events, & &1.seq) == Enum.to_list(1..2_000)
    assert active.details.trace.seq == 2_012
    assert :ok = MockLLM.release(mock, :held)
    assert {:ok, "Done"} = Request.await(handle)
    assert {:ok, done} = Orchestration.snapshot(server)
    assert done.details.trace.events == active.details.trace.events
    assert done.details.trace.truncated? and done.details.trace.seq > active.details.trace.seq
    assert done.request.status == :completed
    assert_script_done(mock)
  end

  for {getter, text, expected} <- [
        {:get_steps, "Step 1: first\nConclusion: answer", [%{number: 1, content: "first"}]},
        {:get_conclusion, "Conclusion: answer", "answer"},
        {:get_raw_response, "raw", "raw"}
      ] do
    test "#{getter}/1 reads the committed model result", %{jido: jido} do
      mock = mock([%{reply: {:text, unquote(text)}}])
      server = start_reasoning(jido, :chain_of_thought)
      assert {:ok, handle} = request(server, mock, :chain_of_thought)
      assert {:ok, _} = Request.await(handle)
      assert apply(ChainOfThought, unquote(getter), [Server.agent(server)]) == unquote(Macro.escape(expected))
      assert_script_done(mock)
    end
  end
end
