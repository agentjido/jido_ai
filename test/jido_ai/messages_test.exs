defmodule Jido.AI.MessagesTest do
  use ExUnit.Case, async: true

  import Jido.AI.Messages

  alias Jido.AI.Messages
  alias Jido.AI.{ContentPart, Message, Messages}

  # doctest Messages  # Temporarily disabled until doctests are fixed

  describe "user/1 and user/2" do
    test "creates user message with text content" do
      message = user("Hello world")

      assert %Message{
               role: :user,
               content: "Hello world",
               metadata: %{}
             } = message
    end

    test "creates user message with metadata" do
      message = user("Hello", %{priority: "high"})

      assert %Message{
               role: :user,
               content: "Hello",
               metadata: %{priority: "high"}
             } = message
    end
  end

  describe "assistant/1 and assistant/2" do
    test "creates assistant message with text content" do
      message = assistant("How can I help?")

      assert %Message{
               role: :assistant,
               content: "How can I help?",
               metadata: %{}
             } = message
    end

    test "creates assistant message with metadata" do
      message = assistant("Here's the answer", %{confidence: 0.95})

      assert %Message{
               role: :assistant,
               content: "Here's the answer",
               metadata: %{confidence: 0.95}
             } = message
    end
  end

  describe "system/1 and system/2" do
    test "creates system message with text content" do
      message = system("You are a helpful assistant")

      assert %Message{
               role: :system,
               content: "You are a helpful assistant",
               metadata: %{}
             } = message
    end

    test "creates system message with metadata" do
      message = system("Respond in French", %{language: "fr"})

      assert %Message{
               role: :system,
               content: "Respond in French",
               metadata: %{language: "fr"}
             } = message
    end
  end

  describe "tool_result/3 and tool_result/4" do
    test "creates tool result message" do
      message = tool_result("call_123", "get_weather", %{temp: 72})

      assert %Message{
               role: :tool,
               content: [
                 %ContentPart{
                   type: :tool_result,
                   tool_call_id: "call_123",
                   tool_name: "get_weather",
                   output: %{temp: 72}
                 }
               ],
               tool_call_id: "call_123",
               metadata: %{}
             } = message
    end

    test "creates tool result message with metadata" do
      message = tool_result("call_456", "search", ["result1", "result2"], %{count: 2})

      assert %Message{
               role: :tool,
               content: [
                 %ContentPart{
                   type: :tool_result,
                   tool_call_id: "call_456",
                   tool_name: "search",
                   output: ["result1", "result2"]
                 }
               ],
               tool_call_id: "call_456",
               metadata: %{count: 2}
             } = message
    end
  end

  describe "user_with_image/2 and user_with_image/3" do
    test "creates user message with text and image URL" do
      message = user_with_image("Describe this", "https://example.com/image.png")

      assert %Message{
               role: :user,
               content: [
                 %ContentPart{type: :text, text: "Describe this"},
                 %ContentPart{type: :image_url, url: "https://example.com/image.png"}
               ],
               metadata: %{}
             } = message
    end

    test "creates user message with text, image URL, and metadata" do
      message = user_with_image("What's this?", "https://example.com/photo.jpg", %{detail: "high"})

      assert %Message{
               role: :user,
               content: [
                 %ContentPart{type: :text, text: "What's this?"},
                 %ContentPart{type: :image_url, url: "https://example.com/photo.jpg"}
               ],
               metadata: %{detail: "high"}
             } = message
    end
  end

  describe "user_with_file/4 and user_with_file/5" do
    test "creates user message with text and file data" do
      pdf_data = <<"%PDF-1.4...">>
      message = user_with_file("Analyze this", pdf_data, "application/pdf", "report.pdf")

      assert %Message{
               role: :user,
               content: [
                 %ContentPart{type: :text, text: "Analyze this"},
                 %ContentPart{
                   type: :file,
                   data: ^pdf_data,
                   media_type: "application/pdf",
                   filename: "report.pdf"
                 }
               ],
               metadata: %{}
             } = message
    end

    test "creates user message with text, file data, and metadata" do
      json_data = ~s({"key": "value"})

      message =
        user_with_file("Process this JSON", json_data, "application/json", "data.json", %{
          encoding: "utf8"
        })

      assert %Message{
               role: :user,
               content: [
                 %ContentPart{type: :text, text: "Process this JSON"},
                 %ContentPart{
                   type: :file,
                   data: ^json_data,
                   media_type: "application/json",
                   filename: "data.json"
                 }
               ],
               metadata: %{encoding: "utf8"}
             } = message
    end
  end

  describe "validate_messages/1" do
    test "returns :ok for valid message list" do
      messages = [
        user("Hello"),
        assistant("Hi there"),
        system("You are helpful")
      ]

      assert :ok = Messages.validate_messages(messages)
    end

    test "returns error for invalid message in list" do
      messages = [
        user("Hello"),
        %{invalid: "message"},
        assistant("Hi")
      ]

      assert {:error, "Message at index 1: Not a valid Message struct"} =
               Messages.validate_messages(messages)
    end

    test "returns error for non-list input" do
      assert {:error, "Expected a list of messages, got: \"not a list\""} =
               Messages.validate_messages("not a list")
    end

    test "returns :ok for empty list" do
      assert :ok = Messages.validate_messages([])
    end
  end

  describe "validate_message/1" do
    test "returns :ok for valid message" do
      message = user("Hello")
      assert :ok = Messages.validate_message(message)
    end

    test "returns error for nil message" do
      assert {:error, "Message cannot be nil"} = Messages.validate_message(nil)
    end

    test "returns error for non-Message struct" do
      assert {:error, "Not a valid Message struct"} =
               Messages.validate_message(%{role: :user, content: "Hello"})
    end

    test "returns error for invalid role" do
      invalid_message = %Message{role: :invalid_role, content: "Hello"}

      assert {:error, "Invalid role: :invalid_role. Must be :user, :assistant, :system, or :tool"} =
               Messages.validate_message(invalid_message)
    end

    test "returns error for invalid content" do
      invalid_message = %Message{role: :user, content: 123}

      assert {:error, "Content must be a string or list of ContentPart structs, got: 123"} =
               Messages.validate_message(invalid_message)
    end

    test "validates content as list of ContentPart structs" do
      valid_content = [
        %ContentPart{type: :text, text: "Hello"},
        %ContentPart{type: :image_url, url: "https://example.com/image.png"}
      ]

      message = %Message{role: :user, content: valid_content}
      assert :ok = Messages.validate_message(message)
    end

    test "returns error for invalid ContentPart in content list" do
      invalid_content = [
        %ContentPart{type: :text, text: "Hello"},
        %{invalid: "content_part"}
      ]

      message = %Message{role: :user, content: invalid_content}

      assert {:error, "Content list contains invalid ContentPart structs"} =
               Messages.validate_message(message)
    end
  end

  describe "integration examples" do
    test "creates complete conversation flow" do
      messages = [
        system("You are a weather assistant"),
        user("What's the weather like?"),
        assistant("I'll check the weather for you"),
        tool_result("call_123", "get_weather", %{temp: 68, condition: "sunny"}),
        assistant("It's 68°F and sunny!")
      ]

      assert :ok = Messages.validate_messages(messages)
      assert length(messages) == 5
      assert Enum.all?(messages, &match?(%Message{}, &1))
    end

    test "creates multi-modal conversation" do
      pdf_data = <<"%PDF-1.4...">>

      messages = [
        user_with_image("Describe this chart", "https://example.com/chart.png"),
        assistant("This chart shows quarterly sales data..."),
        user_with_file("Also analyze this report", pdf_data, "application/pdf", "q4_report.pdf"),
        assistant("Based on both the chart and report...")
      ]

      assert :ok = Messages.validate_messages(messages)
      assert length(messages) == 4

      # Verify multi-modal content structure
      [image_msg, _, file_msg, _] = messages

      assert [
               %ContentPart{type: :text},
               %ContentPart{type: :image_url}
             ] = image_msg.content

      assert [
               %ContentPart{type: :text},
               %ContentPart{type: :file}
             ] = file_msg.content
    end
  end
end
