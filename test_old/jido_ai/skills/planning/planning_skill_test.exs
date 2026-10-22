defmodule Jido.AI.Plugins.PlanningTest do
  use ExUnit.Case, async: true
  alias Jido.AI.Plugins.Planning

  test "core state creation and empty restore use the declared Planning defaults" do
    config = [default_model: "openai:gpt-4o", default_max_tokens: 700, default_temperature: 0.2]
    {:planning, schema} = Planning.Agent.state_spec(config)
    assert {:ok, state} = Zoi.parse(schema, %{})
    assert state.default_model == "openai:gpt-4o"
    assert state.default_max_tokens == 700 and state.default_temperature == 0.2

    agent =
      Jido.Agent.new!(%{
        name: "planning_defaults",
        schema: Zoi.object(%{}),
        plugins: [{Planning, config}]
      })
      |> Jido.Agent.instantiate!()

    assert agent.state.planning == state
  end

  test "invalid and duplicate configuration fails core definition validation" do
    for config <- [
          [default_max_tokens: 0],
          [default_temperature: false],
          [into: nil],
          [typo: 1],
          [default_max_tokens: 1, default_max_tokens: 2]
        ] do
      assert {:error, _} =
               Jido.Agent.new(%{
                 name: "invalid_planning",
                 schema: Zoi.object(%{}),
                 plugins: [{Planning, config}]
               })
    end
  end

  test "the callable catalog and explicit route helper retain each Planning operation" do
    assert Planning.actions() == [
             Jido.AI.Actions.Planning.Plan,
             Jido.AI.Actions.Planning.Decompose,
             Jido.AI.Actions.Planning.Prioritize
           ]

    assert Planning.signal_patterns() == [
             "planning.plan",
             "planning.decompose",
             "planning.prioritize"
           ]

    assert Enum.map(Planning.signal_routes([]), &elem(&1, 0)) == Planning.signal_patterns()

    assert Enum.all?(
             Planning.signal_routes([]),
             &(elem(&1, 1) == Jido.AI.Actions.Planning.RunCapability)
           )
  end
end
