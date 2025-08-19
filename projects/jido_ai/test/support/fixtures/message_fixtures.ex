defmodule Jido.AI.Test.Fixtures.MessageFixtures do
  @moduledoc """
  Shared fixtures for Message testing
  """
  import Jido.AI.Messages

  alias Jido.AI.{Message, ContentPart}

  def user_message(content \\ "Hello") do
    user(content)
  end

  def assistant_message(content \\ "Hi there") do
    assistant(content)
  end

  def system_message(content \\ "You are helpful") do
    system(content)
  end

  def tool_message(call_id \\ "call_123", result \\ %{result: "success"}) do
    tool_result(call_id, "test_tool", result)
  end

  def multimodal_message do
    user([
      ContentPart.text("What's in this image?"),
      ContentPart.image_url("https://example.com/image.jpg")
    ])
  end

  def tool_call_conversation do
    [
      user("What's the weather?"),
      Message.assistant_with_tools("", [
        %{
          id: "call_123",
          type: "function",
          function: %{name: "get_weather", arguments: %{location: "NYC"}}
        }
      ]),
      tool_result("call_123", "get_weather", %{weather: "sunny", temp: 72}),
      assistant("It's sunny and 72°F in NYC")
    ]
  end
end
