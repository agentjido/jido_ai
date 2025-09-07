defmodule ReqLLM.MessagesTest do
  use ExUnit.Case, async: true

  import ReqLLM.Messages
  alias ReqLLM.{Message, ContentPart}

  describe "builder functions" do
    test "creates user, assistant, and system messages" do
      user_msg = user("Hello world", %{priority: "high"})

      assert %Message{role: :user, content: "Hello world", metadata: %{priority: "high"}} =
               user_msg

      assistant_msg = assistant("I can help you")
      assert %Message{role: :assistant, content: "I can help you", metadata: %{}} = assistant_msg

      system_msg = system("You are helpful")
      assert %Message{role: :system, content: "You are helpful", metadata: %{}} = system_msg
    end

    test "creates tool result messages" do
      message = tool_result("call_123", "get_weather", %{temp: 72}, %{count: 3})

      expected_content = [
        %ContentPart{
          type: :tool_result,
          tool_call_id: "call_123",
          tool_name: "get_weather",
          output: %{temp: 72}
        }
      ]

      assert %Message{
               role: :tool,
               content: ^expected_content,
               tool_call_id: "call_123",
               metadata: %{count: 3}
             } = message
    end
  end

  test "validate/1 handles string input" do
    assert {:ok, "Hello world"} = validate("Hello world")

    assert {:error, error} = validate("")
    assert error.tag == :empty_prompt
    assert error.reason == "Messages cannot be empty"

    assert {:error, error} = validate(42)
    assert error.tag == :invalid_messages
    assert error.reason == "Expected string or message list"
  end

  test "validate_messages/1 handles message lists" do
    messages = [user("Hello"), assistant("Hi"), tool_result("call_1", "tool", "result")]
    assert :ok = validate_messages(messages)

    assert {:error, %ReqLLM.Error.Invalid.MessageList{reason: "Message list cannot be empty"}} =
             validate_messages([])

    assert {:error,
            %ReqLLM.Error.Invalid.MessageList{reason: "Expected a list of messages", received: 42}} =
             validate_messages(42)
  end

  test "validation error cases" do
    invalid_messages = [user("Valid"), %{role: :user, content: "Invalid"}]

    assert {:error, %ReqLLM.Error.Invalid.Message{reason: "Not a valid Message struct", index: 1}} =
             validate_messages(invalid_messages)

    invalid_message = %Message{role: :invalid_role, content: "Hello"}

    assert {:error, %ReqLLM.Error.Invalid.Role{role: :invalid_role}} =
             validate_message(invalid_message)

    invalid_content = %Message{role: :user, content: 42}

    assert {:error,
            %ReqLLM.Error.Invalid.Content{
              reason: "Content must be a string or list of ContentPart structs",
              received: 42
            }} =
             validate_message(invalid_content)
  end
end
