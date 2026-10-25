defmodule Jido.AI.TurnTest do
  use ExUnit.Case, async: true

  alias Jido.AI.{Event, Result, Turn}

  defmodule Ask do
    @moduledoc false

    use Jido.Action,
      name: "turn_test_ask",
      description: "Ask one test question",
      schema: Zoi.object(%{question: Zoi.string()}),
      output_schema: Zoi.object(%{answer: Zoi.string()})

    @impl Jido.Action
    def run(%{question: question}, _context), do: {:ok, %{answer: question}}
  end

  defmodule TurnOutput do
    use Jido.Action,
      name: "turn_test_output",
      schema: Ask.schema(),
      output_schema:
        Zoi.object(%{
          state: Zoi.map(),
          reply: Ask.output_schema()
        })

    @impl Jido.Action
    def run(_params, _context), do: {:error, :not_used}
  end

  defmodule RoutedAgent do
    use Jido.Agent, name: "turn_test_agent"

    routes do
      signal_source "/test/turn"

      route "test.turn.ask", TurnOutput, as: :ask do
        state(from: output(:state))
        reply("test.turn.answered", from: output(:reply))
      end
    end
  end

  @route {RoutedAgent, "test.turn.ask"}

  test "completes a correlated turn in Thread Agent state" do
    request = RoutedAgent.ask_signal!(%{question: "Ready?"})
    thread = Jido.Thread.new!()

    assert {:ok, %{state: state, reply: %{answer: "Ready"}}} =
             Turn.complete(
               %{signal: request, agent_state: %{thread: thread, count: 1}},
               @route,
               %{answer: "Ready"},
               state_key: :thread
             )

    reply = List.last(state.thread.signals)
    assert state.count == 1
    assert state.thread.signals == [request, reply]
    assert state.thread.rev == 2
    assert reply.data == %{answer: "Ready"}
    assert Jido.Signal.get_context(reply, "jidocausationid") == request.id
    assert thread.signals == []
    assert thread.rev == 0
  end

  test "prepares a Thread or open Session without changing it" do
    request = RoutedAgent.ask_signal!(%{question: "Ready?"})
    thread = Jido.Thread.new!()
    session = Jido.Session.new!()

    assert {:ok, %{state_key: :thread, turn_state: ^thread}} =
             Turn.prepare(%{signal: request, agent_state: %{thread: thread}}, state_key: :thread)

    assert {:ok, %{state_key: :session, turn_state: ^session}} =
             Turn.prepare(%{signal: request, agent_state: %{session: session}}, state_key: :session)

    assert thread.rev == 0
    assert session.thread.rev == 0
  end

  test "completes a correlated turn in Session Agent state" do
    request = RoutedAgent.ask_signal!(%{question: "Ready?"})
    session = Jido.Session.new!()

    assert {:ok, %{state: state, reply: %{answer: "Ready"}}} =
             Turn.complete(
               %{signal: request, agent_state: %{session: session}},
               @route,
               %{answer: "Ready"},
               state_key: :session
             )

    reply = List.last(state.session.thread.signals)
    assert state.session.thread.signals == [request, reply]
    assert state.session.thread.rev == 2
    assert session.thread.signals == []
    assert session.thread.rev == 0
  end

  test "commits only a completed AI result" do
    request = RoutedAgent.ask_signal!(%{question: "Ready?"})
    session = Jido.Session.new!()
    context = %{signal: request, agent_state: %{session: session}}
    identity = %{request_id: "request-1", run_id: "run-1"}

    completed =
      Result.completed(identity, %{answer: "Ready"}, %{model_calls: 1}, [
        Event.new(identity, :request_started, %{}, sequence: 1),
        Event.new(identity, :request_completed, %{}, sequence: 2)
      ])

    assert {:ok, %{state: state, reply: %{answer: "Ready"}}} =
             Turn.complete(context, @route, completed, state_key: :session)

    reply = List.last(state.session.thread.signals)
    assert reply.data == %{answer: "Ready"}
    assert state.session.thread.rev == 2
    assert session.thread.rev == 0

    failed =
      Result.failed(identity, :provider_unavailable, [
        Event.new(identity, :request_started, %{}, sequence: 1),
        Event.new(identity, :request_failed, %{}, sequence: 2)
      ])

    assert Turn.complete(context, @route, failed, state_key: :session) ==
             {:error, {:turn_not_completed, :failed}}

    assert session.thread.rev == 0

    invalid = %{completed | events: [], trace: []}

    assert Turn.complete(context, @route, invalid, state_key: :session) ==
             {:error, {:invalid_ai_result, :invalid_result_events}}

    assert session.thread.rev == 0
  end

  test "completes a reply without changing Agent state" do
    request = RoutedAgent.ask_signal!(%{question: "Ready?"})
    agent_state = %{count: 1}

    assert {:ok, %{reply: %{answer: "Ready"}}} =
             Turn.complete_reply(
               %{signal: request, agent_state: agent_state},
               @route,
               %{answer: "Ready"}
             )
  end

  test "rejects invalid context, reply Actions, options, and state" do
    request = RoutedAgent.ask_signal!(%{question: "Ready?"})
    context = %{signal: request, agent_state: %{value: %{}}}

    assert Turn.complete(%{}, @route, %{answer: "Ready"}, state_key: :value) ==
             {:error, :invalid_turn_context}

    assert Turn.complete(context, String, %{answer: "Ready"}, state_key: :value) ==
             {:error, :invalid_reply_route}

    assert Turn.complete(context, @route, %{answer: "Ready"}, state_key: :missing) ==
             {:error, {:missing_turn_state, :missing}}

    assert Turn.complete(context, @route, %{answer: "Ready"}, state_key: :value) ==
             {:error, {:unsupported_turn_state, %{}}}

    assert Turn.complete(context, @route, %{answer: "Ready"}, []) ==
             {:error, {:invalid_turn_options, []}}
  end

  test "rejects a closed Session before completing a turn" do
    request = RoutedAgent.ask_signal!(%{question: "Ready?"})
    {:ok, session} = Jido.Session.new!() |> Jido.Session.close()
    context = %{signal: request, agent_state: %{session: session}}

    assert Turn.prepare(context, state_key: :session) == {:error, :session_closed}

    assert Turn.complete(context, @route, %{answer: "Ready"}, state_key: :session) ==
             {:error, :session_closed}

    assert session.thread.rev == 0
  end

  test "an invalid reply leaves the original Thread unchanged" do
    request = RoutedAgent.ask_signal!(%{question: "Ready?"})
    thread = Jido.Thread.new!()
    context = %{signal: request, agent_state: %{thread: thread}}

    assert {:error, _issues} =
             Turn.complete(context, @route, %{answer: 42}, state_key: :thread)

    assert thread.signals == []
    assert thread.rev == 0
  end
end
