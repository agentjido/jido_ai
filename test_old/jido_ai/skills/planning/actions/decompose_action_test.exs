defmodule Jido.AI.Actions.Planning.DecomposeTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Jido.AI.Actions.Planning.Decompose, as: Action
  alias Jido.AI.TestSupport.FakeReqLLM

  setup :set_mimic_from_context
  setup :stub_req_llm

  defp stub_req_llm(context), do: FakeReqLLM.setup_stubs(context)

  test "the public schema remains static and supplies the Action generation defaults" do
    assert :ok = Jido.Action.validate_static_data(Action.schema())
    assert {:ok, params} = Action.validate_params(%{goal: "Release"})
    assert params.max_tokens == 4096 and params.temperature == 0.6
  end

  test "invalid required inputs fail before model resolution" do
    assert {:error, _} = Action.run(%{}, %{})
    assert {:error, _} = Jido.Exec.run(Action, %{}, %{})
  end

  test "the catalog retains the Action name category tags and version" do
    assert Action.name() == "planning_decompose"
    assert Action.category() == "ai" and Action.vsn() == "1.0.0"
    assert "planning" in Action.tags()
  end

  test "extracts the bullet-numbered sub-goals requested by its prompt" do
    assert {:ok, params} = Action.validate_params(%{goal: "Release"})
    assert {:ok, result} = Action.run(params, %{})

    assert result.sub_goals == [
             "Define requirements",
             "Build MVP",
             "Set milestones",
             "Release plan"
           ]
  end
end
