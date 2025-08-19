defmodule Jido.AI.MessageTest do
  use ExUnit.Case, async: true

  import Jido.AI.Messages

  alias Jido.AI.{Message, ContentPart}

  describe "message creation helpers" do
    test "creates user message with string content" do
      message = user("Hello")

      assert message.role == :user
      assert message.content == "Hello"
      assert Message.valid?(message)
    end

    test "creates user message with content parts" do
      parts = [
        ContentPart.text("Hello"),
        ContentPart.image_url("https://example.com/image.jpg")
      ]

      message = user(parts)

      assert message.role == :user
      assert message.content == parts
      assert Message.valid?(message)
    end

    test "creates assistant message" do
      message = assistant("Hello back")

      assert message.role == :assistant
      assert message.content == "Hello back"
      assert Message.valid?(message)
    end

    test "creates system message" do
      message = system("You are helpful")

      assert message.role == :system
      assert message.content == "You are helpful"
      assert Message.valid?(message)
    end

    test "creates tool result message" do
      message = tool_result("call_123", "test_tool", %{result: "success"})

      assert message.role == :tool
      assert message.tool_call_id == "call_123"
      assert Message.valid?(message)
    end
  end

  describe "backward compatibility" do
    test "handles text-only messages" do
      messages = [
        user("Hello"),
        assistant("Hi there")
      ]

      assert Enum.all?(messages, &Message.valid?/1)
    end
  end
end
