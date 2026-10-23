defmodule Jido.AI.TurnTest do
  use ExUnit.Case, async: true

  alias Jido.Agent.Directive.Reply
  alias Jido.AI.{Event, Result, Turn}

  defmodule Ask do
    @moduledoc false

    use Jido.SignalAction,
      name: "turn_test_ask",
      description: "Ask one test question",
      vsn: 1,
      input: [
        type: "test.turn.ask",
        default_source: "/test/turn/client",
        schema: Zoi.object(%{question: Zoi.string()})
      ],
      output: [
        type: "test.turn.answered",
        default_source: "/test/turn",
        schema: Zoi.object(%{answer: Zoi.string()})
      ]

    @impl Jido.Action
    def run(%{question: question}, _context), do: {:ok, %{answer: question}}
  end

  test "completes a correlated turn in Thread Agent state" do
    request = Ask.new!(%{question: "Ready?"})
    thread = Jido.Thread.new!()

    assert {:ok, state, [%Reply{signal: reply}]} =
             Turn.complete(
               %{signal: request, agent_state: %{thread: thread, count: 1}},
               Ask,
               %{answer: "Ready"},
               state_key: :thread
             )

    assert state.count == 1
    assert state.thread.signals == [request, reply]
    assert state.thread.rev == 2
    assert reply.data == %{answer: "Ready"}
    assert Jido.Signal.get_context(reply, "jidocausationid") == request.id
    assert thread.signals == []
    assert thread.rev == 0
  end

  test "prepares a Thread or open Session without changing it" do
    request = Ask.new!(%{question: "Ready?"})
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
    request = Ask.new!(%{question: "Ready?"})
    session = Jido.Session.new!()

    assert {:ok, state, [%Reply{signal: reply}]} =
             Turn.complete(
               %{signal: request, agent_state: %{session: session}},
               Ask,
               %{answer: "Ready"},
               state_key: :session
             )

    assert state.session.thread.signals == [request, reply]
    assert state.session.thread.rev == 2
    assert session.thread.signals == []
    assert session.thread.rev == 0
  end

  test "commits only a completed AI result" do
    request = Ask.new!(%{question: "Ready?"})
    session = Jido.Session.new!()
    context = %{signal: request, agent_state: %{session: session}}
    identity = %{request_id: "request-1", run_id: "run-1"}

    completed =
      Result.completed(identity, %{answer: "Ready"}, %{model_calls: 1}, [
        Event.new(identity, :request_started, %{}, sequence: 1),
        Event.new(identity, :request_completed, %{}, sequence: 2)
      ])

    assert {:ok, state, [%Reply{signal: reply}]} =
             Turn.complete(context, Ask, completed, state_key: :session)

    assert reply.data == %{answer: "Ready"}
    assert state.session.thread.rev == 2
    assert session.thread.rev == 0

    failed =
      Result.failed(identity, :provider_unavailable, [
        Event.new(identity, :request_started, %{}, sequence: 1),
        Event.new(identity, :request_failed, %{}, sequence: 2)
      ])

    assert Turn.complete(context, Ask, failed, state_key: :session) ==
             {:error, {:turn_not_completed, :failed}}

    assert session.thread.rev == 0

    invalid = %{completed | events: [], trace: []}

    assert Turn.complete(context, Ask, invalid, state_key: :session) ==
             {:error, {:invalid_ai_result, :invalid_result_events}}

    assert session.thread.rev == 0
  end

  test "completes a reply without changing Agent state" do
    request = Ask.new!(%{question: "Ready?"})
    agent_state = %{count: 1}

    assert {:ok, ^agent_state, [%Reply{signal: reply}]} =
             Turn.complete_reply(
               %{signal: request, agent_state: agent_state},
               Ask,
               %{answer: "Ready"}
             )

    assert reply.data == %{answer: "Ready"}
    assert Jido.Signal.get_context(reply, "jidocausationid") == request.id
  end

  test "rejects invalid context, reply Actions, options, and state" do
    request = Ask.new!(%{question: "Ready?"})
    context = %{signal: request, agent_state: %{value: %{}}}

    assert Turn.complete(%{}, Ask, %{answer: "Ready"}, state_key: :value) ==
             {:error, :invalid_turn_context}

    assert Turn.complete(context, String, %{answer: "Ready"}, state_key: :value) ==
             {:error, :invalid_reply_action}

    assert Turn.complete(context, Ask, %{answer: "Ready"}, state_key: :missing) ==
             {:error, {:missing_turn_state, :missing}}

    assert Turn.complete(context, Ask, %{answer: "Ready"}, state_key: :value) ==
             {:error, {:unsupported_turn_state, %{}}}

    assert Turn.complete(context, Ask, %{answer: "Ready"}, []) ==
             {:error, {:invalid_turn_options, []}}
  end

  test "rejects a closed Session before completing a turn" do
    request = Ask.new!(%{question: "Ready?"})
    {:ok, session} = Jido.Session.new!() |> Jido.Session.close()
    context = %{signal: request, agent_state: %{session: session}}

    assert Turn.prepare(context, state_key: :session) == {:error, :session_closed}

    assert Turn.complete(context, Ask, %{answer: "Ready"}, state_key: :session) ==
             {:error, :session_closed}

    assert session.thread.rev == 0
  end

  test "an invalid reply leaves the original Thread unchanged" do
    request = Ask.new!(%{question: "Ready?"})
    thread = Jido.Thread.new!()
    context = %{signal: request, agent_state: %{thread: thread}}

    assert {:error, _issues} =
             Turn.complete(context, Ask, %{answer: 42}, state_key: :thread)

    assert thread.signals == []
    assert thread.rev == 0
  end
end
