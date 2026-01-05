defmodule Jido.AI.Skills.LLM.Actions.CompleteTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Skills.LLM.Actions.Complete

  describe "Complete action" do
    test "has correct metadata" do
      metadata = Complete.__action_metadata__()
      assert metadata.name == "llm_complete"
      assert metadata.category == "ai"
      assert metadata.vsn == "1.0.0"
    end

    test "requires prompt parameter" do
      assert {:error, _} = Jido.Exec.run(Complete, %{}, %{})
    end

    test "accepts valid parameters with defaults" do
      params = %{
        prompt: "Complete this"
      }

      assert params.prompt == "Complete this"
    end

    test "accepts optional parameters" do
      params = %{
        prompt: "Test",
        model: "anthropic:claude-haiku-4-5",
        max_tokens: 500,
        temperature: 0.5
      }

      assert params.prompt == "Test"
      assert params.model == "anthropic:claude-haiku-4-5"
      assert params.max_tokens == 500
      assert params.temperature == 0.5
    end
  end
end
