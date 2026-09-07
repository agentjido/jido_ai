defmodule Jido.AI.Reasoning.StateOpsHelpersTest do
  use ExUnit.Case, async: true
  alias Jido.AI.Effects
  alias Jido.AI.Test.StateMigration.Agent, as: TestAgent
  alias Jido.Agent.Directive

  # The old constructor cases are mapped in docs/v3-spike/state-test-transfer.md.
  defp apply_state(agent, next, extra \\ []) do
    Effects.apply_result(agent, {:ok, :changed, [Effects.state(next) | extra]}, %{
      allow: [Effects.State, Directive.Emit]
    })
  end

  test "complete state updates preserve unrelated fields and leave the source immutable" do
    agent = TestAgent.new!(state: %{data: %{keep: "value"}})
    next = %{agent.state | count: 1, data: Map.merge(agent.state.data, %{status: :running, iteration: 1})}
    assert {changed, [], %{allowed_count: 1}, {:ok, :changed, _}} = apply_state(agent, next)
    assert changed.state.count == 1
    assert changed.state.data == %{keep: "value", status: :running, iteration: 1}
    assert changed.state.label == "initial"
    assert agent.state.count == 0 and agent.state.data == %{keep: "value"}
    assert changed.state.requests == agent.state.requests
  end

  test "nested edits preserve siblings and explicit merges replace only selected values" do
    agent = TestAgent.new!(state: %{data: %{config: %{model: "old", tools: [], limits: %{tokens: 20, calls: 3}}}})

    next =
      agent.state
      |> put_in([:data, :config, :model], "openai:gpt-4")
      |> update_in([:data, :config, :limits], &Map.merge(&1, %{tokens: 40}))

    assert {changed, [], _, {:ok, :changed, _}} = apply_state(agent, next)
    assert changed.state.data.config == %{model: "openai:gpt-4", tools: [], limits: %{tokens: 40, calls: 3}}
    assert agent.state.data.config.limits.tokens == 20
  end

  test "a new nested path is explicit and retains unrelated Agent fields" do
    agent = TestAgent.new!()

    next =
      put_in(
        agent.state,
        [Access.key(:data, %{}), Access.key(:config, %{}), Access.key(:tools, [])],
        [Jido.AI.Test.StateMigration.Double]
      )

    assert {changed, [], _, {:ok, :changed, _}} = apply_state(agent, next)
    assert changed.state.data == %{config: %{tools: [Jido.AI.Test.StateMigration.Double]}}
    assert changed.state.label == "initial" and changed.state.count == 0
    assert agent.state.data == %{}
  end

  for {label, before, after_value} <- [
        {"prepend", [%{role: :assistant, content: "Hi"}],
         [%{role: :user, content: "Hello"}, %{role: :assistant, content: "Hi"}]},
        {"append", [%{role: :user, content: "Hello"}],
         [%{role: :user, content: "Hello"}, %{role: :assistant, content: "Hi"}]},
        {"replace", [%{role: :user, content: "Old"}], [%{role: :user, content: "Hello"}]},
        {"empty", [], [%{role: :user, content: "Hello"}]}
      ] do
    test "candidate lists keep #{label} order without a hidden merge" do
      before = unquote(Macro.escape(before))
      expected = unquote(Macro.escape(after_value))
      agent = TestAgent.new!(state: %{data: %{conversation: before, keep: true}})
      next = put_in(agent.state, [:data, :conversation], expected)
      assert {changed, [], _, {:ok, :changed, _}} = apply_state(agent, next)
      assert changed.state.data == %{conversation: expected, keep: true}
      assert agent.state.data.conversation == before
    end
  end

  test "deletion removes selected temporary keys and keeps unrelated data" do
    agent = TestAgent.new!(state: %{data: %{temp: 1, cache: 2, ephemeral: 3, keep: "this"}})
    next = %{agent.state | data: Map.drop(agent.state.data, [:temp, :cache, :ephemeral])}
    assert {changed, [], _, {:ok, :changed, _}} = apply_state(agent, next)
    assert changed.state.data == %{keep: "this"}
    assert agent.state.data == %{temp: 1, cache: 2, ephemeral: 3, keep: "this"}
  end

  test "nested deletion removes one pending ID and an absent key is harmless" do
    agent = TestAgent.new!(state: %{data: %{pending: %{"one" => %{name: "first"}, "two" => %{name: "second"}}}})
    next = update_in(agent.state, [:data, :pending], &Map.drop(&1, ["one", "absent"]))
    assert {changed, [], _, {:ok, :changed, _}} = apply_state(agent, next)
    assert changed.state.data.pending == %{"two" => %{name: "second"}}
    assert map_size(agent.state.data.pending) == 2
  end

  test "an explicit domain reset removes old values and retains Plugin state" do
    agent = TestAgent.new!(state: %{count: 5, data: %{old: "data", more: "stuff"}})

    reset = %{
      status: :idle,
      iteration: 0,
      conversation: [],
      pending_tool_calls: [],
      final_answer: nil,
      current_llm_call_id: nil,
      termination_reason: nil
    }

    assert {changed, [], _, {:ok, :changed, _}} = apply_state(agent, %{agent.state | count: 0, data: reset})
    assert changed.state.data == reset and changed.state.count == 0
    refute Map.has_key?(changed.state.data, :old)
    refute Map.has_key?(changed.state.data, :more)
    assert changed.state.requests == agent.state.requests
  end

  test "ordered map changes form one complete state candidate" do
    agent = TestAgent.new!()

    next =
      agent.state
      |> put_in([:data, :status], :running)
      |> put_in([:data, :count], 5)
      |> put_in([:data, :status], :completed)

    assert {changed, [], _, {:ok, :changed, _}} = apply_state(agent, next)
    assert changed.state.data == %{status: :completed, count: 5}
    assert agent.state.data == %{}
  end

  test "disjoint state proposals and pending directives assemble without dispatch" do
    agent = TestAgent.new!()
    signal = Jido.Signal.new!("state.done", %{}, source: "/test")
    emit = %Directive.Emit{signal: signal, dispatch: {:pid, target: self()}}

    result =
      {:ok, :done, [Effects.state(%{agent.state | count: 2}), Effects.state(%{agent.state | label: "changed"}), emit]}

    assert {changed, [^emit], %{allowed_count: 3}, {:ok, :done, _}} =
             Effects.apply_result(agent, result, %{mode: :allow_all})

    assert changed.state.count == 2 and changed.state.label == "changed"
    assert agent.state.count == 0
    refute_receive {:signal, _}, 20
  end

  test "conflicting proposals reject the entire candidate and its directives" do
    agent = TestAgent.new!()
    emit = %Directive.Emit{signal: Jido.Signal.new!("state.done", %{}, source: "/test")}
    result = {:ok, :done, [Effects.state(%{agent.state | count: 1}), emit, Effects.state(%{agent.state | count: 2})]}

    assert {^agent, [], _, {:error, {:tool_state_conflict, [:count]}, []}} =
             Effects.apply_result(agent, result, %{mode: :allow_all})
  end

  test "empty effects and an unchanged candidate preserve the Agent" do
    agent = TestAgent.new!()
    assert {^agent, [], %{received_count: 0}, {:ok, :done, []}} = Effects.apply_result(agent, {:ok, :done, []}, nil)
    assert {^agent, [], _, {:ok, :changed, _}} = apply_state(agent, agent.state)
  end

  test "a complete proposal cannot replace Plugin-owned request records" do
    agent = TestAgent.new!()
    next = %{agent.state | requests: %{"forged" => %{status: :completed}}}
    assert {^agent, [], _, {:error, _, []}} = apply_state(agent, next)
  end

  test "schema errors reject state and all pending work" do
    agent = TestAgent.new!()
    emit = %Directive.Emit{signal: Jido.Signal.new!("state.done", %{}, source: "/test")}
    assert {^agent, [], _, {:error, _, []}} = apply_state(agent, %{agent.state | count: "not an integer"}, [emit])
  end

  test "unportable data cannot enter a state candidate" do
    agent = TestAgent.new!()

    for value <- [self(), make_ref(), fn -> :live end] do
      assert {^agent, [], _, {:error, _, []}} = apply_state(agent, %{agent.state | data: %{resource: value}})
    end
  end

  for {label, value} <- [
        {"zero", 0},
        {"counter", 5},
        {"status", :awaiting_llm},
        {"answer", "42"},
        {"false", false},
        {"cleared", nil},
        {"tools", [%{id: "call_1", name: "search"}]},
        {"usage", %{input_tokens: 10, output_tokens: 20}}
      ] do
    test "candidate values retain the #{label} type and value" do
      value = unquote(Macro.escape(value))
      agent = TestAgent.new!()
      assert {changed, [], _, {:ok, :changed, _}} = apply_state(agent, %{agent.state | data: %{value: value}})
      assert changed.state.data.value === value
      assert :ok = Jido.Action.validate_static_data(changed.state)
    end
  end
end
