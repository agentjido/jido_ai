defmodule Jido.AI.Execution.StateTest do
  use ExUnit.Case, async: true
  alias Jido.AI.Execution.State

  defp input do
    profile = Jido.AI.Profile.new!(%{id: :assistant, model: "openai:gpt-4o-mini", result: %{into: :answer}})

    %{
      profile: profile,
      effect_plan: Jido.AI.Effects.Candidate.new(%{answer: ""}),
      model: "openai:gpt-4o-mini",
      options: [],
      messages: ReqLLM.Context.new([]),
      output: nil,
      deadline: System.monotonic_time(:millisecond) + 1000,
      history_delta: []
    }
  end

  test "construction defines common state without adding method or phase fields" do
    assert {:ok, state} = State.new(input())
    assert state.iterations == 0
    assert state.model_calls == 0
    assert state.tool_calls == 0
    assert state.repairs == 0
    assert state.usage == %{}
    assert is_binary(state.request_id)
    assert is_binary(state.run_id)

    for key <- [:response, :repair_result, :tree_search, :graph_search, :recursive, :checkpoint_phase] do
      refute Map.has_key?(state, key)
    end

    assert {:ok, ^state} = State.validate(state)
  end

  test "runtime collaborators remain in memory and are not encoded or copied to a Thread" do
    callback = fn value -> value end
    values = %{input() | options: [callback: callback]}
    assert {:ok, state} = State.new(values)
    assert state.options[:callback] == callback
    assert state.messages == values.messages
    refute Map.has_key?(state, :session)
    refute Map.has_key?(state, :thread)
  end

  test "unknown fields and invalid counters are rejected" do
    assert {:ok, state} = State.new(input())
    assert {:error, _} = State.validate(Map.put(state, :second_conversation, []))
    assert {:error, _} = State.validate(%{state | model_calls: -1})
    assert {:error, _} = State.validate(Map.delete(state, :deadline))
    assert {:error, _} = State.validate(Map.put(state, :repair_result, :invalid))
    assert {:error, _} = State.validate(Map.put(state, :checkpoint_phase, :unknown))
  end

  test "the model Action rejects malformed state before executing model work" do
    assert {:ok, state} = State.new(input())
    assert {:error, _} = Jido.Exec.run(Jido.AI.Execution.CallModel, %{state | model_calls: -1}, %{})
  end

  test "repairs and resume positions share one iteration rule" do
    state = %{iterations: 3, repairs: 0}
    assert State.model_iteration(state) == 4
    assert State.model_iteration(%{state | repairs: 1}) == 3
    assert State.model_iteration(Map.put(state, :checkpoint_phase, :after_llm)) == 3
    assert State.iteration(state, :after_tools) == 4
    assert State.iteration(state, :terminal) == 3
    assert State.iteration(Map.put(state, :termination_reason, :max_iterations), :terminal) == 4
  end
end
