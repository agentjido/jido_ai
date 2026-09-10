defmodule Jido.AI.CapabilityTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Capability

  defmodule Action do
    use Jido.Action, name: "capability_test_action", schema: Zoi.object(%{value: Zoi.string()})
    def run(%{value: value}, context), do: {:ok, %{value: value, provided: context.provided_params}}
  end

  test "binds a capability to command context" do
    command = %{agent: %{schema: Zoi.object(%{result: Zoi.any()})}, context: %{existing: true}}

    assert {:ok, bound} = Capability.bind(command, :capability, %{mode: :test})
    assert bound.context == %{existing: true, capability: %{mode: :test}}
  end

  test "validates command result targets against the Agent schema" do
    command = %{agent: %{schema: Zoi.object(%{result: Zoi.any()})}, context: %{}}

    assert {:ok, bound} = Capability.bind(command, :capability, nil)
    assert bound.context.capability == nil

    assert {:ok, bound} =
             Capability.bind(command, :capability, %{into: :result, defaults: %{}})

    assert bound.context.capability.into == :result

    assert {:error, error} =
             Capability.bind(command, :capability, %{into: :missing, defaults: %{}})

    assert error.message == "Capability result must select a declared domain field"
    assert error.details.into == :missing

    invalid_schema = put_in(command, [:agent, :schema], Zoi.string())
    assert {:error, _error} = Capability.bind(invalid_schema, :capability, %{into: :result})
  end

  test "runs an Action in the capability scope and stores its result" do
    context = %{agent_state: %{result: nil}, caller: :test}
    binding = %{key: :demo, defaults: %{enabled: true}, into: :result}

    assert {:ok, state} = Capability.run(Action, %{value: "done"}, context, binding)
    assert state.result == %{value: "done", provided: [:value]}
  end
end
