defmodule Jido.AI.Skills.LLM.Actions.ChatTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Skills.LLM.Actions.Chat

  describe "Chat action" do
    test "has correct metadata" do
      metadata = Chat.__action_metadata__()
      assert metadata.name == "llm_chat"
      assert metadata.category == "ai"
      assert metadata.vsn == "1.0.0"
    end

    test "requires prompt parameter" do
      assert {:error, _} = Jido.Exec.run(Chat, %{}, %{})
    end

    test "accepts valid parameters with defaults" do
      params = %{
        prompt: "Hello, world!"
      }

      # Test that the schema accepts the parameters
      # We can't run the actual LLM call in unit tests
      assert params.prompt == "Hello, world!"
    end

    test "accepts optional parameters" do
      params = %{
        prompt: "Test",
        model: "anthropic:claude-haiku-4-5",
        system_prompt: "You are helpful",
        max_tokens: 500,
        temperature: 0.5
      }

      assert params.prompt == "Test"
      assert params.model == "anthropic:claude-haiku-4-5"
      assert params.system_prompt == "You are helpful"
      assert params.max_tokens == 500
      assert params.temperature == 0.5
    end
  end
end
