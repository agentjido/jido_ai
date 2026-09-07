defmodule JidoAI.Examples.PublicAgentTest do
  use JidoAI.Examples.Case
  alias JidoAI.Examples.PublicAgent.{Agent, StreamAgent, ObjectAgent}

  setup do
    old = Application.fetch_env(:jido_ai, :model_aliases)
    Application.put_env(:jido_ai, :model_aliases, %{example: MockLLM.model()})

    on_exit(fn ->
      case old do
        {:ok, value} -> Application.put_env(:jido_ai, :model_aliases, value)
        :error -> Application.delete_env(:jido_ai, :model_aliases)
      end
    end)

    :ok
  end

  test "the public macro builds a core definition and exports request helpers" do
    assert %Jido.Agent{id: nil, state: nil} = Agent.agent()
    assert {:ok, %Jido.Agent{state: state}} = Agent.new()
    refute Map.has_key?(state, :__strategy__)
    assert Enum.count(Agent.plugins(), &(elem(&1, 0) == Jido.AI.Session.Plugin)) == 1

    for {name, arity} <- [
          ask: 2,
          ask: 3,
          ask_stream: 2,
          ask_stream: 3,
          await: 1,
          await: 2,
          ask_sync: 2,
          ask_sync: 3,
          cancel: 1,
          cancel: 2,
          steer: 2,
          steer: 3,
          inject: 2,
          inject: 3
        ] do
      assert function_exported?(Agent, name, arity)
    end

    assert {Jido.AI.Session.Start, %{profile_id: :assistant}} =
             Enum.find(Agent.routes(), &(&1.path == "ai.react.query")).target
  end

  @tag api_case: "API/request-handles"
  test "ask and await keep handles and convenience fields after a committed result", %{jido: jido} do
    {mock, context} = mock([%{reply: {:wait, :answer, {:text, "Done"}}}])
    server = start_agent(jido, Agent.new!())

    assert {:ok, %Jido.AI.Request.Handle{} = request} =
             Agent.ask(server, "Work", context: context)

    assert_receive {:mock_llm_waiting, ^mock, :answer, _}, 2_000
    id = request.id

    assert %{
             state: %{last_request_id: ^id, last_query: "Work", last_answer: "", completed: false}
           } = Server.agent(server)

    assert :ok = MockLLM.release(mock, :answer)
    assert {:ok, "Done"} = Agent.await(request)

    assert %{state: %{last_answer: "Done", last_result: "Done", completed: true} = state} =
             Server.agent(server)

    assert :ok = Jido.Action.validate_static_data(state)
    assert [request] = MockLLM.report(mock).requests
    assert request.body["temperature"] == 0.1

    assert hd(request.body["messages"]) == %{
             "role" => "system",
             "content" => "Use the case facts and the available tools."
           }

    assert_script_done(mock)
  end

  test "ask_sync retains typed results and the old text convenience field", %{jido: jido} do
    {mock, context} = mock([%{reply: {:object, %{answer: "Typed"}}}])
    server = start_agent(jido, ObjectAgent.new!())

    assert {:ok, %{answer: "Typed"} = value} =
             ObjectAgent.ask_sync(server, "Extract", context: context)

    assert %{state: %{last_result: ^value, last_answer: text, completed: true}} =
             Server.agent(server)

    assert text == inspect(value)
    assert_script_done(mock)
  end

  @tag history_case: "HIST-07/public-stream"
  test "ask_stream keeps the public map shape and one ordered terminal event", %{jido: jido} do
    {mock, context} = mock([%{reply: {:text, ["First", " second"]}}])
    server = start_agent(jido, StreamAgent.new!())

    assert {:ok, %{request: request, events: events}} =
             StreamAgent.ask_stream(server, "Stream", context: context)

    events = Enum.to_list(events)
    assert {:ok, "First second"} = StreamAgent.await(request)
    assert Enum.map(events, & &1.seq) == Enum.to_list(1..length(events))
    assert Enum.count(events, &Jido.AI.Request.Stream.terminal_kind?(&1.kind)) == 1
    assert Enum.any?(events, &(&1.kind == :llm_delta))
    assert List.last(events).kind == :request_completed
    assert_script_done(mock)
  end

  @tag history_case: "HIST-21/public-helpers"
  test "public steering returns the committed Agent and keeps input order and source", %{
    jido: jido
  } do
    {mock, context} =
      mock([
        %{reply: {:wait, :answer, {:text, "Intermediate"}}},
        %{reply: {:text, "Final"}}
      ])

    server = start_agent(jido, Agent.new!())
    assert {:error, {:rejected, :idle}} = Agent.steer(server, "Too soon")
    {:ok, request} = Agent.ask(server, "Work", context: context)
    assert_receive {:mock_llm_waiting, ^mock, :answer, _}, 2_000

    assert {:ok, %Jido.Agent{} = first} =
             Agent.steer(server, "First", expected_request_id: request.id)

    assert first.state.requests[request.id].last_control.status == :queued
    assert {:ok, %Jido.Agent{}} = Agent.inject(server, "Second", extra_refs: %{peer: "reviewer"})

    assert {:error, {:rejected, :request_mismatch}} =
             Agent.inject(server, "Wrong", expected_request_id: "other")

    assert :ok = MockLLM.release(mock, :answer)
    assert {:ok, "Final"} = Agent.await(request)
    [_, followup] = MockLLM.report(mock).requests

    assert Enum.map(Enum.take(followup.body["messages"], -2), & &1["content"]) == [
             "First",
             "Second"
           ]

    entries = Server.agent(server).state.messages

    assert Enum.any?(
             entries,
             &(get_in(&1, [:refs, :source]) == "/ai/react/agent" &&
                 get_in(&1, [:refs, :peer]) == "reviewer")
           )

    assert_script_done(mock)
  end

  test "public cancel keeps reason, terminal kind and request ID isolation", %{jido: jido} do
    {mock, context} =
      mock([
        %{reply: {:wait, :first, {:text, "Too late"}}},
        %{reply: {:wait, :second, {:text, "Next"}}}
      ])

    server = start_agent(jido, Agent.new!())
    {:ok, %{request: first, events: events}} = Agent.ask_stream(server, "First", context: context)
    assert_receive {:mock_llm_waiting, ^mock, :first, _}, 2_000
    assert :ok = Agent.cancel(server, reason: :changed_plan)
    assert {:error, {:cancelled, :changed_plan}} = Agent.await(first)

    assert %{kind: :request_cancelled, data: %{reason: :changed_plan}} =
             events |> Enum.to_list() |> List.last()

    assert Server.agent(server).state.completed
    MockLLM.release(mock, :first)
    {:ok, second} = Agent.ask(server, "Second", context: context)
    assert_receive {:mock_llm_waiting, ^mock, :second, _}, 2_000
    assert :ok = Agent.cancel(server, request_id: first.id)
    assert Server.agent(server).state.requests[second.id].status == :pending
    MockLLM.release(mock, :second)
    assert {:ok, "Next"} = Agent.await(second)
    assert_script_done(mock)
  end

  test "tools get merged context and the pre-admission snapshot through a bounded retry", %{
    jido: jido
  } do
    {mock, context} =
      mock([
        %{reply: {:tools, [%{id: "probe", name: "public_probe", arguments: %{value: 7}}]}},
        %{reply: {:text, "Used tool"}}
      ])

    counter = start_supervised!({Elixir.Agent, fn -> 0 end})
    server = start_agent(jido, Agent.new!())

    assert {:ok, "Used tool"} =
             Agent.ask_sync(server, "Probe",
               context: context,
               tool_context: %{
                 tenant: "request",
                 counter: counter,
                 fail_once: true,
                 state: %{last_query: "forged"},
                 jido_ai_input_source: "/forged",
                 jido_ai_legacy_agent_profile: nil
               }
             )

    assert_receive {:public_probe, 1, "request", ""}
    assert_receive {:public_probe, 2, "request", ""}
    assert Elixir.Agent.get(counter, & &1) == 2
    [_, followup] = MockLLM.report(mock).requests
    tool = Enum.find(followup.body["messages"], &(&1["role"] == "tool"))

    assert Jason.decode!(tool["content"]) == %{
             "ok" => true,
             "result" => %{"value" => 7, "tenant" => "request"}
           }

    refute Enum.any?(
             Server.agent(server).state.messages,
             &(get_in(&1, [:refs, :source]) == "/forged")
           )

    assert Server.agent(server).state.completed
    assert_script_done(mock)
  end

  test "tool retry limits and nonretryable errors stop further attempts", %{jido: jido} do
    for {retryable, expected} <- [{true, 2}, {false, 1}] do
      {mock, context} =
        mock([
          %{reply: {:tools, [%{id: "probe", name: "public_probe", arguments: %{value: 7}}]}},
          %{reply: {:text, "Tool failed"}}
        ])

      {:ok, counter} = Elixir.Agent.start_link(fn -> 0 end)

      try do
        server = start_agent(jido, Agent.new!())

        assert {:ok, "Tool failed"} =
                 Agent.ask_sync(server, "Fail",
                   context: context,
                   tool_context: %{counter: counter, fail_always: true, retryable: retryable}
                 )

        assert Elixir.Agent.get(counter, & &1) == expected
        [_, followup] = MockLLM.report(mock).requests
        tool = Enum.find(followup.body["messages"], &(&1["role"] == "tool"))

        assert %{"ok" => false, "error" => %{"retryable?" => ^retryable}} =
                 Jason.decode!(tool["content"])

        state = Server.agent(server).state

        assert [%{meta: %{tool_results: [%{attempts: ^expected, status: :error}]}}] =
                 Map.values(state.requests)

        assert state.completed
        assert_script_done(mock)
      after
        Elixir.Agent.stop(counter)
      end

      stop_supervised(MockLLM)
    end
  end

  @tag history_case: "HIST-01/stream-headers"
  test "public request options keep generation precedence and actual HTTP headers", %{jido: jido} do
    {mock, context} = mock([%{reply: {:text, "Options"}}])
    server = start_agent(jido, Agent.new!())

    assert {:ok, "Options"} =
             Agent.ask_sync(server, "Work",
               context: context,
               llm_opts: [temperature: 0.4],
               req_http_options: [retry: false, headers: [{"X-Public-Case", "request"}]]
             )

    assert [request] = MockLLM.report(mock).requests
    assert request.body["temperature"] == 0.4
    assert request.headers["x-public-case"] == "request"
    assert_script_done(mock)
  end

  test "completed public Agent state uses the core checkpoint round trip", %{jido: jido} do
    {mock, context} = mock([%{reply: {:text, "Saved"}}])
    server = start_agent(jido, StreamAgent.new!())
    assert {:ok, "Saved"} = StreamAgent.ask_sync(server, "Save", context: context)
    agent = Server.agent(server)
    assert {:ok, checkpoint} = StreamAgent.checkpoint(agent, %{})
    assert :ok = Jido.Action.validate_static_data(checkpoint)
    assert {:ok, restored} = StreamAgent.restore(checkpoint, %{})
    assert restored.state == agent.state
    assert restored.id == agent.id
    assert_script_done(mock)
  end

  test "unsupported options, callbacks and unsafe literal input fail at compile time" do
    for {extra, error, message} <- [
          {"skills: []", ArgumentError, ~r/not yet ported/},
          {"tool_context: System.get_env()", CompileError, ~r/Unsafe construct/},
          {"system_prompt: System.get_env(\"MISSING\")", CompileError, ~r/system_prompt requires/}
        ] do
      name = "PublicInvalid#{System.unique_integer([:positive])}"

      assert_raise error, message, fn ->
        Code.compile_string(
          "defmodule #{name} do\nuse Jido.AI.Agent, name: \"invalid\", tools: [], #{extra}\nend"
        )
      end
    end

    name = "PublicCallback#{System.unique_integer([:positive])}"

    assert_raise CompileError, ~r/callbacks are not yet ported/, fn ->
      Code.compile_string(
        "defmodule #{name} do\nuse Jido.AI.Agent, name: \"invalid\", tools: []\ndef on_before_cmd(call, _), do: {:ok, call}\nend"
      )
    end
  end
end
