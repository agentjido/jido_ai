defmodule Jido.AI.Actions.Reasoning.RunStrategyFastTest do
  @moduledoc "Successful callable CoT completion for the fast gate."
  use Jido.AI.Test.CallableReasoningCase, async: false

  alias Jido.AI.Actions.Reasoning.RunStrategy

  @moduletag :stable_smoke
  @moduletag :unit

  test "CoT completes through the isolated runtime and HTTP transport", %{jido: jido} do
    assert {{:ok, payload}, [_request], nil} =
             call(jido, callable_profile(:chain_of_thought), "Explain 2 + 2", script(:cot), 1)

    assert_success(payload, :cot, :chain_of_thought, 1, :success)
    assert payload.output == "Four"
  end

  test "rejects invalid strategy request in fast gate" do
    assert {:error, :reasoning_profile_not_bound} = RunStrategy.run(%{prompt: "Missing Profile"}, %{})
    assert {:error, :invalid_strategy_request} = RunStrategy.run(%{strategy: :cot}, %{})
  end
end
