defmodule Jido.AI.Effects.ApplierTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Effects.Applier
  alias Jido.Agent.Directive
  alias Jido.AI.Effects.State

  defmodule EffectsApplierAgent do
    use Jido.Agent,
      name: "effects_applier_agent",
      schema: Zoi.object(%{status: Zoi.atom() |> Zoi.default(:idle)})
  end

  test "normalize_result supports both 2-tuple and 3-tuple envelopes" do
    assert Applier.normalize_result({:ok, :value}) == {:ok, :value, []}

    assert Applier.normalize_result({:ok, :value, [%State{state: %{a: 1}}]}) ==
             {:ok, :value, [%State{state: %{a: 1}}]}

    assert Applier.normalize_result({:error, :boom}) == {:error, :boom, []}
  end

  test "filter_result drops disallowed effects and reports stats" do
    emit = %Directive.Emit{signal: %{type: "ai.test"}}
    state_op = %State{state: %{count: 1}}

    {filtered_result, stats} =
      Applier.filter_result(
        {:ok, :done, [state_op, emit]},
        %{mode: :allow_list, allow: [State]}
      )

    assert filtered_result == {:ok, :done, [state_op]}
    assert stats.received_count == 2
    assert stats.allowed_count == 1
    assert stats.dropped_count == 1
    assert stats.dropped_effects == [emit]
  end

  test "apply_result assembles complete agent state and returns directives from allowed effects" do
    agent = EffectsApplierAgent.new!()
    emit = %Directive.Emit{signal: Jido.Signal.new!("ai.done", %{}, %{source: "/effects/test"})}
    state_op = %State{state: %{status: :complete}}

    {updated_agent, directives, stats, filtered_result} =
      Applier.apply_result(
        agent,
        {:ok, :done, [state_op, emit]},
        %{mode: :allow_list, allow: [State, Directive.Emit]}
      )

    assert updated_agent.state.status == :complete
    assert [%Directive.Emit{signal: %{type: "ai.done"}}] = directives
    assert stats.allowed_count == 2
    assert filtered_result == {:ok, :done, [state_op, emit]}
  end

  test "apply_result handles invalid envelopes safely" do
    agent = EffectsApplierAgent.new!()

    {updated_agent, directives, stats, filtered_result} =
      Applier.apply_result(agent, :bad_result, %{mode: :allow_all})

    assert updated_agent == agent
    assert directives == []
    assert stats.received_count == 0
    assert stats.allowed_count == 0
    assert stats.dropped_count == 0
    assert filtered_result == {:error, {:invalid_result_envelope, ":bad_result"}, []}
  end
end
