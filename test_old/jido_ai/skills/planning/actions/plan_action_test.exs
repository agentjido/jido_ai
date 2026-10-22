defmodule Jido.AI.Actions.Planning.PlanTest do
  use ExUnit.Case, async: true
  alias Jido.AI.Actions.Planning.Plan, as: Action

  test "the public schema remains static and supplies the Action generation defaults" do
    assert :ok = Jido.Action.validate_static_data(Action.schema())
    assert {:ok, params} = Action.validate_params(%{goal: "Release"})
    assert params.max_tokens == 4096 and params.temperature == 0.7
  end

  test "invalid required inputs fail before model resolution" do
    assert {:error, _} = Action.run(%{}, %{})
    assert {:error, _} = Jido.Exec.run(Action, %{}, %{})
  end

  test "the catalog retains the Action name category tags and version" do
    assert Action.name() == "planning_plan"
    assert Action.category() == "ai" and Action.vsn() == "1.0.0"
    assert "planning" in Action.tags()
  end
end
