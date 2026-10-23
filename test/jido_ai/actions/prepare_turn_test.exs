defmodule Jido.AI.Actions.PrepareTurnTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Actions.PrepareTurn

  test "uses the Session state key by default" do
    request = Jido.Signal.new!("test.prepare_turn", %{}, source: "/test")
    session = Jido.Session.new!()
    context = %{signal: request, agent_state: %{session: session}}

    assert {:ok, %{state_key: :session}} = PrepareTurn.validate_params(%{})

    assert {:ok, %{state_key: :session, turn_state: ^session}} =
             Jido.Exec.run(PrepareTurn, %{}, context)
  end

  test "accepts an explicit Thread state key" do
    request = Jido.Signal.new!("test.prepare_turn", %{}, source: "/test")
    thread = Jido.Thread.new!()
    context = %{signal: request, agent_state: %{history: thread}}

    assert {:ok, %{state_key: :history, turn_state: ^thread}} =
             Jido.Exec.run(PrepareTurn, %{state_key: :history}, context)
  end

  test "rejects an unnamed state key at the Action schema boundary" do
    assert {:error, _issues} = PrepareTurn.validate_params(%{state_key: true})
  end

  test "rejects a closed Session" do
    request = Jido.Signal.new!("test.prepare_turn", %{}, source: "/test")
    {:ok, session} = Jido.Session.new!() |> Jido.Session.close()

    assert PrepareTurn.run(
             %{state_key: :session},
             %{signal: request, agent_state: %{session: session}}
           ) == {:error, :session_closed}
  end

  test "rejects missing, unsupported, and invalid turn state" do
    request = Jido.Signal.new!("test.prepare_turn", %{}, source: "/test")

    assert PrepareTurn.run(
             %{state_key: :session},
             %{signal: request, agent_state: %{}}
           ) == {:error, {:missing_turn_state, :session}}

    assert PrepareTurn.run(
             %{state_key: :session},
             %{signal: request, agent_state: %{session: %{}}}
           ) == {:error, {:unsupported_turn_state, %{}}}

    invalid_thread = %{Jido.Thread.new!() | rev: 1}

    assert PrepareTurn.run(
             %{state_key: :session},
             %{signal: request, agent_state: %{session: invalid_thread}}
           ) == {:error, {:invalid_turn_state, :invalid_thread_revision}}
  end
end
