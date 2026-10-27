defmodule Jido.AI.PolicyTest do
  use ExUnit.Case, async: true

  alias Jido.AI.{Budget, ToolResult, Toolset, Usage}
  alias Jido.AITest.Tools

  test "tool selection can only narrow the Agent allowlist" do
    actions = [Tools.Add, Tools.Multiply]

    assert {:ok, selection} =
             Toolset.select(actions, %{
               visible: ["multiply", "add"],
               hidden: ["multiply"],
               review: ["add"],
               requirement: :required,
               reason: "only addition is approved"
             })

    assert selection.actions == [Tools.Add]
    assert selection.visible == ["add"]
    assert selection.hidden == ["multiply"]
    assert selection.review == ["add"]
    assert selection.requirement == :required

    assert {:error, {:unknown_tool, "delete_everything"}} =
             Toolset.select(actions, %{visible: ["delete_everything"]})
  end

  test "semantic tool requirements lower without provider policy in request data" do
    actions = [Tools.Add]

    assert Toolset.provider_tool_choice(:optional, 0, actions) == nil
    assert Toolset.provider_tool_choice(:required, 0, actions) == :required
    assert Toolset.provider_tool_choice(:required, 1, actions) == :auto
    assert Toolset.provider_tool_choice(:per_turn, 1, actions) == :required
    assert Toolset.provider_tool_choice(:disabled, 0, actions) == :none

    refute Toolset.requirement_satisfied?(:required, 0, actions)
    assert Toolset.requirement_satisfied?(:required, 1, actions)
  end

  test "tool results keep the local value separate from bounded model content" do
    local_value = %{content: String.duplicate("private", 100)}
    result = ToolResult.normalize(%{status: :ok, value: local_value}, 256)

    assert result.value == local_value
    assert result.model_content["status"] == "truncated"
    assert result.metadata.truncated
    refute inspect(result.model_content) =~ String.duplicate("private", 10)
  end

  test "budgets check elapsed time, tokens, and provider-reported cost" do
    turn = %{
      started_at_ms: 1_000,
      model_calls: 0,
      max_model_calls: 3,
      max_elapsed_ms: 500,
      max_input_tokens: 100,
      max_output_tokens: 100,
      max_total_tokens: 150,
      max_total_cost: 0.25,
      usage: Usage.add(Usage.zero(), %{input_tokens: 80, output_tokens: 20, total_cost: 0.2})
    }

    assert :ok = Budget.before_model(turn, 1_400)

    assert {:error, :elapsed_ms, "maximum elapsed time reached"} =
             Budget.before_model(turn, 1_500)

    costly = put_in(turn, [:usage, :total_cost], 0.25)

    assert {:error, :total_cost, "maximum total cost reached"} =
             Budget.resources(costly, 1_400)

    assert turn.usage.total_cost == 0.2
  end
end
