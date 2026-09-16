defmodule Jido.AI.Orchestration.UnifiedLifecycleTest do
  use ExUnit.Case, async: false
  alias Jido.AI.{Profile, Request}
  alias Jido.AI.Test.MockLLM

  defmodule Assistant do
    use Jido.AI.Agent, name: "unified_lifecycle"

    agent do
      schema Zoi.object(%{answer: Zoi.string() |> Zoi.default("")})

      ai :assistant do
        model MockLLM.model()

        controls do
          timeout 5_000
        end

        result into: :answer
      end
    end

    routes do
      signal_source "/test/unified"

      route "test.ask", ai: :assistant do
        define :admit, args: [:query]
      end
    end
  end

  setup do
    previous = Application.fetch_env(:jido_ai, :max_retained_requests)
    Application.put_env(:jido_ai, :max_retained_requests, 1)

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:jido_ai, :max_retained_requests, value)
        :error -> Application.delete_env(:jido_ai, :max_retained_requests)
      end
    end)

    jido = :"unified_lifecycle_#{System.unique_integer([:positive])}"
    start_supervised!({Jido, name: jido})
    {:ok, server} = Jido.start_agent(jido, Assistant)
    {:ok, server: server}
  end

  test "a default Profile returns a handle and leaves AgentServer responsive", %{server: server} do
    mock = start_supervised!({MockLLM, observer: self(), script: [%{reply: {:wait, :held, {:text, "Done"}}}]})
    context = %{ai: %{assistant: %{options: MockLLM.options(mock)}}}
    {:ok, request} = Assistant.ask(server, "Work", context: context)
    assert %Request.Handle{} = request
    assert_receive {:mock_llm_waiting, ^mock, :held, _}, 5_000

    agent = Jido.AgentServer.agent(server)
    assert agent.state.answer == ""
    assert agent.state.requests[request.id].status == :pending
    refute Map.has_key?(agent.state, :messages)
    assert {:error, :busy} = Assistant.ask(server, "Second", context: context)
    assert {:error, :timeout} = Assistant.await(request, timeout: 0)
    assert :ok = MockLLM.release(mock, :held)
    assert {:ok, "Done"} = Assistant.await(request)
    assert %{remaining: [], unexpected: []} = MockLLM.report(mock)
  end

  test "core helpers admit, AI helpers wait, and retention does not create another Coordinator", %{server: server} do
    mock = start_supervised!({MockLLM, script: [%{reply: {:text, "First"}}, %{reply: {:text, "Second"}}]})
    context = %{ai: %{assistant: %{options: MockLLM.options(mock)}}}
    owner = Jido.AgentServer.children(server)[{:plugin, Jido.AI.Orchestration.Plugin}].pid

    {:ok, admitted} = Assistant.admit(server, "First", context: context)
    assert [{id, %{status: :pending}}] = Map.to_list(admitted.state.requests)
    assert admitted.state.answer == ""
    assert {:ok, "First"} = Request.await(Request.Handle.new(id, server, "First"))
    assert {:ok, "Second"} = Assistant.ask_sync(server, "Second", context: context)
    records = Jido.AgentServer.agent(server).state.requests
    assert [{_, %{status: :completed, result: "Second"}}] = Map.to_list(records)
    refute Map.has_key?(records, id)
    assert Jido.AgentServer.children(server)[{:plugin, Jido.AI.Orchestration.Plugin}].pid == owner
    assert %{remaining: [], unexpected: []} = MockLLM.report(mock)
  end

  test "removed switches fail validation instead of selecting a second lifecycle" do
    for options <- [
          %{},
          %{mode: :turn},
          %{mode: :session},
          %{on_busy: :reject},
          %{max_requests: 1},
          %{streaming: true},
          %{steering: true},
          %{max_retained_requests: 1}
        ] do
      assert {:error, %Jido.AI.Error.Validation.Invalid{field: "profile"}} =
               Profile.new(id: :assistant, result: %{into: :answer}, requests: options)
    end
  end

  test "the same Agent can buffer, stream, then buffer without changing its Profile", %{server: server} do
    mock = start_supervised!({MockLLM, script: Enum.map(["First", "Streamed", "Last"], &%{reply: {:text, &1}})})
    context = %{ai: %{assistant: %{options: MockLLM.options(mock)}}}
    before = Assistant.ai_profile(:assistant)
    refute Map.has_key?(before, :requests)

    assert {:ok, "First"} = Assistant.ask_sync(server, "First", context: context)
    # ask_stream owns this choice, even if a caller passes a conflicting option.
    assert {:ok, %{request: request, events: events}} =
             Assistant.ask_stream(server, "Second", context: context, stream: false)

    collected = Enum.to_list(events)
    assert Enum.any?(collected, &(&1.kind == :llm_delta and &1.data.delta != ""))
    assert List.last(collected).kind == :request_completed
    assert {:ok, "Streamed"} = Assistant.await(request)
    assert {:ok, view} = Jido.AI.Orchestration.snapshot(server)
    assert view.details.streaming
    assert view.request.streaming and view.request.streamed
    refute Map.has_key?(view.details.config, :streaming)

    assert {:ok, "Last"} = Assistant.ask_sync(server, "Third", context: context)
    assert Assistant.ai_profile(:assistant) == before
    assert {:ok, ^before} = Jido.AI.Configuration.profile(Jido.AgentServer.agent(server))
    assert Enum.map(MockLLM.report(mock).requests, & &1.body["stream"]) == [false, true, false]
    assert %{remaining: [], unexpected: []} = MockLLM.report(mock)
  end

  test "event subscription can use buffered model calls", %{server: server} do
    mock = start_supervised!({MockLLM, script: [%{reply: {:text, "Done"}}]})
    context = %{ai: %{assistant: %{options: MockLLM.options(mock)}}}
    assert {:ok, request} = Assistant.ask(server, "Work", context: context, stream_to: self(), stream: false)
    events = request |> Request.Stream.events() |> Enum.to_list()
    assert hd(events).kind == :request_started
    assert List.last(events).kind == :request_completed
    refute Enum.any?(events, &(&1.kind == :llm_delta))
    assert {:ok, "Done"} = Assistant.await(request)
    assert %{streamed: true, streaming: false} = Jido.AgentServer.agent(server).state.requests[request.id]
    assert [%{body: %{"stream" => false}}] = MockLLM.report(mock).requests
  end

  test "invalid stream choices fail before admission", %{server: server} do
    for invalid <- [nil, :yes, "true", 1] do
      assert {:error, %Jido.AI.Error.Validation.Invalid{field: "request.stream"}} =
               Assistant.ask(server, "Work", stream: invalid)
    end

    assert Jido.AgentServer.agent(server).state.requests == %{}
  end

  test "retention is fixed at Coordinator startup and cannot come from caller context", %{server: server} do
    Application.put_env(:jido_ai, :max_retained_requests, 9)
    mock = start_supervised!({MockLLM, script: [%{reply: {:text, "One"}}, %{reply: {:text, "Two"}}]})
    context = %{ai: %{assistant: %{options: MockLLM.options(mock)}}, jido_ai_max_retained_requests: 999}
    assert {:ok, "One"} = Assistant.ask_sync(server, "First", context: context)
    assert {:ok, "Two"} = Assistant.ask_sync(server, "Second", context: context)

    assert [{_, %{result: "Two", max_retained_requests: 1}}] =
             Map.to_list(Jido.AgentServer.agent(server).state.requests)
  end

  test "invalid host retention settings fail before Coordinator resources start" do
    for invalid <- [0, -1, false, "100"] do
      Application.put_env(:jido_ai, :max_retained_requests, invalid)

      assert {:error, %Jido.AI.Error.Validation.Invalid{field: "max_retained_requests"}} =
               GenServer.start(Jido.AI.Orchestration.Coordinator, %{})
    end
  end
end
