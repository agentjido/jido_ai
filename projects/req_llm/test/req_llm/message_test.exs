defmodule ReqLLM.MessageTest do
  use ExUnit.Case, async: true

  alias ReqLLM.Message
  alias ReqLLM.Message.ContentPart

  describe "struct creation and validation" do
    test "creates message with required role field" do
      message = %Message{role: :user}

      assert message.role == :user
      assert message.content == []
      assert message.name == nil
      assert message.tool_call_id == nil
      assert message.tool_calls == nil
      assert message.metadata == %{}
    end

    test "requires role field" do
      assert_raise ArgumentError, fn ->
        struct!(Message, %{})
      end
    end

    test "accepts all valid role types" do
      valid_roles = [:user, :assistant, :system, :tool]

      for role <- valid_roles do
        message = %Message{role: role}
        assert message.role == role
      end
    end

    test "valid?/1 returns true for valid messages" do
      message = %Message{role: :user, content: []}
      assert Message.valid?(message)

      message_with_content = %Message{
        role: :assistant,
        content: [ContentPart.text("Hello")]
      }

      assert Message.valid?(message_with_content)
    end

    test "valid?/1 returns false for invalid content" do
      invalid_message = %{role: :user, content: "not a list"}
      refute Message.valid?(invalid_message)

      refute Message.valid?(nil)
      refute Message.valid?(%{})
    end
  end

  describe "message types with content" do
    test "user message with text content" do
      content = [ContentPart.text("Hello world")]
      message = %Message{role: :user, content: content}

      assert message.role == :user
      assert message.content == content
      assert Message.valid?(message)
    end

    test "assistant message with multiple content parts" do
      content = [
        ContentPart.text("Here's the image:"),
        ContentPart.image_url("https://example.com/pic.jpg")
      ]

      message = %Message{role: :assistant, content: content}

      assert message.role == :assistant
      assert length(message.content) == 2
      assert Message.valid?(message)
    end

    test "system message with reasoning content" do
      content = [ContentPart.reasoning("System initialization")]
      message = %Message{role: :system, content: content}

      assert message.role == :system
      assert message.content == content
      assert Message.valid?(message)
    end

    test "tool message with tool result" do
      content = [ContentPart.tool_result("call_123", %{result: "success"})]

      message = %Message{
        role: :tool,
        content: content,
        tool_call_id: "call_123"
      }

      assert message.role == :tool
      assert message.tool_call_id == "call_123"
      assert Message.valid?(message)
    end
  end

  describe "message metadata and fields" do
    test "message with name field" do
      message = %Message{
        role: :assistant,
        name: "Claude",
        content: [ContentPart.text("Hello")]
      }

      assert message.name == "Claude"
      assert Message.valid?(message)
    end

    test "message with tool_call_id for tool messages" do
      message = %Message{
        role: :tool,
        tool_call_id: "call_456",
        content: [ContentPart.tool_result("call_456", "output")]
      }

      assert message.tool_call_id == "call_456"
      assert Message.valid?(message)
    end

    test "message with tool_calls array" do
      tool_calls = [
        %{id: "call_1", name: "search", args: %{query: "test"}},
        %{id: "call_2", name: "calc", args: %{expr: "2+2"}}
      ]

      message = %Message{
        role: :assistant,
        tool_calls: tool_calls,
        content: []
      }

      assert message.tool_calls == tool_calls
      assert length(message.tool_calls) == 2
      assert Message.valid?(message)
    end

    test "message with custom metadata" do
      metadata = %{
        timestamp: 1_234_567_890,
        model: "claude-3",
        source: "api",
        extra: %{nested: "value"}
      }

      message = %Message{
        role: :user,
        content: [ContentPart.text("Test")],
        metadata: metadata
      }

      assert message.metadata == metadata
      assert message.metadata.timestamp == 1_234_567_890
      assert message.metadata.extra.nested == "value"
    end
  end

  describe "complex message structures" do
    test "assistant message with tool calls and content" do
      message = %Message{
        role: :assistant,
        content: [ContentPart.text("I'll help you with that calculation.")],
        tool_calls: [%{id: "call_1", name: "calculator", args: %{op: "add", a: 1, b: 2}}],
        metadata: %{thinking: "User wants math help"}
      }

      assert message.role == :assistant
      assert length(message.content) == 1
      assert length(message.tool_calls) == 1
      assert message.metadata.thinking == "User wants math help"
      assert Message.valid?(message)
    end

    test "message with mixed content types" do
      content = [
        ContentPart.text("Look at this file:"),
        ContentPart.file("binary data", "document.pdf", "application/pdf"),
        ContentPart.text("What do you think?"),
        ContentPart.image(<<1, 2, 3>>, "image/png")
      ]

      message = %Message{role: :user, content: content}

      assert length(message.content) == 4
      assert Message.valid?(message)

      # Check content types
      types = Enum.map(message.content, & &1.type)
      assert types == [:text, :file, :text, :image]
    end

    test "empty content is valid" do
      message = %Message{role: :assistant, content: []}
      assert Message.valid?(message)
      assert message.content == []
    end
  end

  describe "edge cases and error handling" do
    test "message with nil values in optional fields" do
      message = %Message{
        role: :user,
        content: [ContentPart.text("Test")],
        name: nil,
        tool_call_id: nil,
        tool_calls: nil,
        metadata: %{}
      }

      assert Message.valid?(message)
      assert message.name == nil
      assert message.tool_call_id == nil
      assert message.tool_calls == nil
    end

    test "message with empty metadata" do
      message = %Message{role: :system, metadata: %{}}
      assert message.metadata == %{}
      assert Message.valid?(message)
    end

    test "message with large content" do
      large_text = String.duplicate("a", 10_000)
      large_content = [ContentPart.text(large_text)]
      message = %Message{role: :user, content: large_content}

      assert Message.valid?(message)
      assert String.length(List.first(message.content).text) == 10_000
    end

    test "message with unicode content" do
      unicode_content = [ContentPart.text("Hello 🌍 世界 🚀")]
      message = %Message{role: :user, content: unicode_content}

      assert Message.valid?(message)
      assert List.first(message.content).text == "Hello 🌍 世界 🚀"
    end

    test "message with deeply nested metadata" do
      nested_metadata = %{
        level1: %{
          level2: %{
            level3: %{
              deeply_nested: "value",
              array: [1, 2, %{inner: "data"}]
            }
          }
        }
      }

      message = %Message{
        role: :assistant,
        content: [],
        metadata: nested_metadata
      }

      assert Message.valid?(message)
      assert get_in(message.metadata, [:level1, :level2, :level3, :deeply_nested]) == "value"
    end
  end

  describe "Inspect implementation" do
    test "inspects message with single text content" do
      message = %Message{
        role: :user,
        content: [ContentPart.text("Hello")]
      }

      output = inspect(message)
      assert output =~ "#Message<"
      assert output =~ "user"
      assert output =~ "text"
      assert output =~ ">"
    end

    test "inspects message with multiple content types" do
      message = %Message{
        role: :assistant,
        content: [
          ContentPart.text("Here's info:"),
          ContentPart.image_url("http://example.com/pic.jpg"),
          ContentPart.reasoning("I think this works")
        ]
      }

      output = inspect(message)
      assert output =~ "#Message<"
      assert output =~ "assistant"
      assert output =~ "text,image_url,reasoning"
    end

    test "inspects message with empty content" do
      message = %Message{role: :system, content: []}

      output = inspect(message)
      assert output =~ "#Message<"
      assert output =~ "system"
      # Empty content summary
      assert output =~ " >"
    end

    test "inspects message with tool content" do
      message = %Message{
        role: :tool,
        content: [
          ContentPart.tool_result("call_1", "success"),
          ContentPart.tool_call("call_2", "calc", %{op: "add"})
        ]
      }

      output = inspect(message)
      assert output =~ "#Message<"
      assert output =~ "tool"
      assert output =~ "tool_result,tool_call"
    end

    test "inspect handles all content part types" do
      content_types = [
        ContentPart.text("text"),
        ContentPart.image_url("http://example.com/img.jpg"),
        ContentPart.image(<<1, 2, 3>>, "image/png"),
        ContentPart.file("data", "file.txt", "text/plain"),
        ContentPart.tool_call("id1", "tool", %{}),
        ContentPart.tool_result("id2", "result"),
        ContentPart.reasoning("thinking")
      ]

      message = %Message{role: :user, content: content_types}
      output = inspect(message)

      assert output =~ "text,image_url,image,file,tool_call,tool_result,reasoning"
    end
  end

  describe "message serialization scenarios" do
    test "message ready for API serialization" do
      message = %Message{
        role: :user,
        content: [
          ContentPart.text("Analyze this image:"),
          ContentPart.image_url("https://example.com/chart.png")
        ],
        metadata: %{request_id: "req_123", priority: "high"}
      }

      # Verify structure is serializable
      assert Message.valid?(message)
      assert is_list(message.content)
      assert is_map(message.metadata)
      assert is_atom(message.role)
    end

    test "tool response message structure" do
      message = %Message{
        role: :tool,
        content: [
          ContentPart.tool_result("call_abc", %{
            status: "success",
            data: %{temperature: 22.5, humidity: 65},
            timestamp: 1_704_067_200
          })
        ],
        tool_call_id: "call_abc",
        name: "weather_sensor"
      }

      assert Message.valid?(message)
      assert message.role == :tool
      assert message.tool_call_id == "call_abc"
      assert message.name == "weather_sensor"

      result = List.first(message.content)
      assert result.type == :tool_result
      assert result.output.status == "success"
    end

    test "assistant message with reasoning chain" do
      message = %Message{
        role: :assistant,
        content: [
          ContentPart.reasoning("Let me think about this step by step..."),
          ContentPart.reasoning("First, I need to understand the problem"),
          ContentPart.text("Based on my analysis, here's the solution:")
        ],
        metadata: %{reasoning_enabled: true, steps: 3}
      }

      assert Message.valid?(message)
      assert length(message.content) == 3

      reasoning_parts = Enum.filter(message.content, &(&1.type == :reasoning))
      assert length(reasoning_parts) == 2
    end
  end
end
