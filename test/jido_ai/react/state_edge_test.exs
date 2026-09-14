defmodule Jido.AI.Reasoning.ReAct.StateEdgeTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Reasoning.ReAct.{PendingToolCall, State}

  test "exposes its schema and updates runtime fields" do
    assert %Zoi.Types.Struct{} = State.schema()

    state = State.new("hello", nil, request_id: "req", run_id: "run")
    {state, 1} = State.bump_seq(state)
    assert State.adopt_seq(state, 1) == state

    state = State.adopt_seq(state, 4)
    assert state.seq == 4

    pending = [%PendingToolCall{id: "call", name: "echo"}]

    state =
      state
      |> State.inc_iteration()
      |> State.put_status(:awaiting_tools)
      |> State.put_llm_call_id("llm-call")
      |> State.put_llm_response_id("response")
      |> State.put_pending_tools(pending)
      |> State.put_output(%{schema: "answer"})

    assert state.iteration == 2
    assert state.llm_call_id == "llm-call"
    assert state.llm_response_id == "response"
    assert state.pending_tool_calls == pending
    assert state.output == %{schema: "answer"}
    assert State.duration_ms(state) >= 0

    assert State.merge_usage(state, nil) == state
    assert State.merge_usage(state, :invalid) == state
  end

  test "restores string statuses and mixed pending call values" do
    checkpoint =
      State.new("hello", nil, request_id: "req", run_id: "run")
      |> State.minimal_checkpoint_map()
      |> Map.put(:status, "completed")
      |> Map.put(:pending_tool_calls, [%{id: "call", name: "echo"}, :invalid])

    assert {:ok, restored} = State.from_checkpoint_map(checkpoint)
    assert restored.status == :completed

    assert Enum.map(restored.pending_tool_calls, &{&1.id, &1.name}) == [
             {"call", "echo"},
             {"", ""}
           ]
  end

  test "normalizes a non-list pending call value" do
    checkpoint =
      State.new("hello", nil, request_id: "req", run_id: "run")
      |> State.minimal_checkpoint_map()
      |> Map.put(:pending_tool_calls, :invalid)

    assert {:ok, %{pending_tool_calls: []}} = State.from_checkpoint_map(checkpoint)
  end

  test "rejects malformed checkpoint shapes and required fields" do
    assert {:error, :invalid_checkpoint_state} = State.from_checkpoint_map(:invalid)
    assert {:error, {:missing_field, :version}} = State.from_checkpoint_map(%{})
    assert {:error, :checkpoint_version_mismatch} = State.from_checkpoint_map(%{version: 2})
    assert {:error, {:missing_field, :run_id}} = State.from_checkpoint_map(%{version: 3})

    base = %{version: 3, run_id: "run", request_id: "req", context: Jido.AI.Context.new()}

    assert {:error, :invalid_status} = State.from_checkpoint_map(Map.put(base, :status, :unknown))
    assert {:error, :invalid_status} = State.from_checkpoint_map(Map.put(base, :status, "unknown"))
    assert {:error, :invalid_context} = State.from_checkpoint_map(Map.put(base, :context, :invalid))

    assert {:error, {:invalid_checkpoint_state, _}} =
             State.from_checkpoint_map(Map.put(base, :iteration, "invalid"))
  end
end
