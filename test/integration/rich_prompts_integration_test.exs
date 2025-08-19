defmodule Jido.AI.RichPromptsIntegrationTest do
  use ExUnit.Case, async: true

  import Jido.AI.Messages

  alias Jido.AI.Message

  describe "message validation" do
    test "validates conversation with different message types" do
      messages = [
        system("You are helpful"),
        user("Hello"),
        assistant("Hi there"),
        tool_result("call_1", "search", %{results: ["item1", "item2"]})
      ]

      assert validate_messages(messages) == :ok
      assert Enum.all?(messages, &Message.valid?/1)
    end

    test "catches invalid messages in conversation" do
      invalid_messages = [
        user("Hello"),
        # Not a Message struct
        %{invalid: "message"},
        assistant("Hi")
      ]

      assert {:error, reason} = validate_messages(invalid_messages)
      assert String.contains?(reason, "Message at index 1")
    end
  end
end
