defmodule Jido.AI.Reasoning.ReAct.PendingInputTest do
  use ExUnit.Case, async: true

  alias Jido.AI.PendingInputServer
  alias Jido.AI.Reasoning.ReAct.PendingInput

  test "starts and stops its queue" do
    assert {:ok, server} = PendingInput.start("request")
    assert Process.alive?(server)

    state = PendingInput.stop(%{pending_input_server: server, marker: true})
    refute Process.alive?(server)
    assert state == %{pending_input_server: nil, marker: true}

    assert PendingInput.stop(%{marker: true}) == %{marker: true, pending_input_server: nil}
  end

  test "reports whether a request accepts queued input" do
    for status <- [:awaiting_llm, :awaiting_tool, :completed] do
      assert PendingInput.open?(%{active_request_id: "request", status: status})
    end

    refute PendingInput.open?(%{active_request_id: nil, status: :awaiting_llm})
    refute PendingInput.open?(%{active_request_id: "request", status: :idle})
  end

  test "queues steer and inject input with optional data" do
    {:ok, server} = PendingInput.start("request")
    on_exit(fn -> PendingInputServer.stop(server) end)

    state = %{
      active_request_id: "request",
      status: :awaiting_llm,
      pending_input_server: server
    }

    assert {:ok, state} =
             PendingInput.accept_control(
               state,
               %{
                 content: "  refine this  ",
                 source: "/test",
                 extra_refs: %{origin: "suite"},
                 expected_request_id: "request"
               },
               :steer
             )

    assert state.last_pending_input_control.kind == :steer
    assert state.last_pending_input_control.status == :queued
    assert state.last_pending_input_control.request_id == "request"
    assert is_integer(state.last_pending_input_control.at_ms)

    assert [%{content: "refine this", source: "/test", refs: %{origin: "suite"}}] =
             PendingInputServer.drain(server)

    assert {:ok, state} =
             PendingInput.accept_control(state, %{content: "next", extra_refs: :invalid}, :inject)

    assert state.last_pending_input_control.kind == :inject
    assert [%{content: "next", refs: nil}] = PendingInputServer.drain(server)
  end

  test "records each rejection reason" do
    {:ok, live_server} = PendingInput.start("request")
    on_exit(fn -> PendingInputServer.stop(live_server) end)

    base = %{
      active_request_id: "request",
      status: :awaiting_tool,
      pending_input_server: live_server
    }

    assert {:error, mismatch} =
             PendingInput.accept_control(
               base,
               %{content: "input", expected_request_id: "other"},
               :steer
             )

    assert mismatch.last_pending_input_control.reason == :request_mismatch

    assert {:error, idle} =
             PendingInput.accept_control(%{base | status: :idle}, %{content: "input"}, :inject)

    assert idle.last_pending_input_control.reason == :idle

    assert {:error, unavailable} =
             PendingInput.accept_control(
               %{base | pending_input_server: nil},
               %{content: "input"},
               :steer
             )

    assert unavailable.last_pending_input_control.reason == :pending_input_unavailable

    {:ok, dead_server} = PendingInput.start("request")
    PendingInputServer.stop(dead_server)

    assert {:error, unavailable} =
             PendingInput.accept_control(
               %{base | pending_input_server: dead_server},
               %{content: "input"},
               :steer
             )

    assert unavailable.last_pending_input_control.reason == :pending_input_unavailable
  end
end
