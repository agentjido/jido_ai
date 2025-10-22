defmodule Jido.AI.ReqLlmBridge.ConversationManagerTest do
  use ExUnit.Case, async: false

  alias Jido.AI.ReqLlmBridge.ConversationManager

  @moduledoc """
  Tests for the ConversationManager module.

  Tests cover:
  - Conversation lifecycle (create, end, list)
  - Message management (user, assistant, tool messages)
  - Tool configuration per conversation
  - Options management per conversation
  - Metadata tracking and updates
  """

  setup do
    # ConversationManager is started by application supervision tree
    # Just need to clear all conversations before each test
    :ok = ConversationManager.clear_all_conversations()

    :ok
  end

  describe "5.1 Conversation Lifecycle" do
    test "conversation creation generates unique ID" do
      # Create first conversation
      assert {:ok, conv_id1} = ConversationManager.create_conversation()
      assert is_binary(conv_id1)
      assert String.length(conv_id1) > 0

      # Create second conversation
      assert {:ok, conv_id2} = ConversationManager.create_conversation()
      assert is_binary(conv_id2)
      assert String.length(conv_id2) > 0

      # IDs should be different
      assert conv_id1 != conv_id2
    end

    test "conversation ending removes from storage" do
      # Create conversation
      {:ok, conv_id} = ConversationManager.create_conversation()

      # Verify it exists in list
      {:ok, conversations} = ConversationManager.list_conversations()
      assert conv_id in conversations

      # End conversation
      assert :ok = ConversationManager.end_conversation(conv_id)

      # Verify no longer in list
      {:ok, conversations_after} = ConversationManager.list_conversations()
      refute conv_id in conversations_after

      # Verify getting conversation returns error
      assert {:error, :conversation_not_found} =
               ConversationManager.get_history(conv_id)
    end

    test "listing active conversations" do
      # Create 3 conversations
      {:ok, conv_id1} = ConversationManager.create_conversation()
      {:ok, conv_id2} = ConversationManager.create_conversation()
      {:ok, conv_id3} = ConversationManager.create_conversation()

      # List should have all 3
      {:ok, conversations} = ConversationManager.list_conversations()
      assert length(conversations) == 3
      assert conv_id1 in conversations
      assert conv_id2 in conversations
      assert conv_id3 in conversations

      # End 1 conversation
      :ok = ConversationManager.end_conversation(conv_id2)

      # List should now have 2
      {:ok, conversations_after} = ConversationManager.list_conversations()
      assert length(conversations_after) == 2
      assert conv_id1 in conversations_after
      refute conv_id2 in conversations_after
      assert conv_id3 in conversations_after
    end
  end

  describe "5.2 Message Management" do
    test "adding user messages to history" do
      {:ok, conv_id} = ConversationManager.create_conversation()

      # Add user message
      assert :ok =
               ConversationManager.add_user_message(conv_id, "What's the weather like?")

      # Get history
      {:ok, history} = ConversationManager.get_history(conv_id)

      # Verify message in history
      assert length(history) == 1
      [message] = history

      assert message.role == "user"
      assert message.content == "What's the weather like?"
      assert %DateTime{} = message.timestamp
      assert is_map(message.metadata)
    end

    test "adding assistant responses to history" do
      {:ok, conv_id} = ConversationManager.create_conversation()

      # Add assistant response with metadata
      response = %{
        content: "The weather is sunny and 75°F",
        tool_calls: [%{name: "get_weather", id: "call_123"}],
        usage: %{prompt_tokens: 10, completion_tokens: 15},
        model: "gpt-4"
      }

      assert :ok = ConversationManager.add_assistant_response(conv_id, response)

      # Get history
      {:ok, history} = ConversationManager.get_history(conv_id)

      # Verify message in history
      assert length(history) == 1
      [message] = history

      assert message.role == "assistant"
      assert message.content == "The weather is sunny and 75°F"
      assert %DateTime{} = message.timestamp

      # Verify metadata includes tool_calls, usage, model
      assert message.metadata.tool_calls == [%{name: "get_weather", id: "call_123"}]
      assert message.metadata.usage == %{prompt_tokens: 10, completion_tokens: 15}
      assert message.metadata.model == "gpt-4"
    end

    test "adding tool results to history" do
      {:ok, conv_id} = ConversationManager.create_conversation()

      # Add tool results
      tool_results = [
        %{
          tool_call_id: "call_123",
          name: "get_weather",
          content: "Weather is sunny, 75°F"
        },
        %{
          tool_call_id: "call_124",
          name: "get_temperature",
          content: "Temperature is 75°F"
        }
      ]

      assert :ok = ConversationManager.add_tool_results(conv_id, tool_results)

      # Get history
      {:ok, history} = ConversationManager.get_history(conv_id)

      # Verify messages in history
      assert length(history) == 2

      # First tool result
      first_message = Enum.at(history, 0)
      assert first_message.role == "tool"
      assert first_message.content == "Weather is sunny, 75°F"
      assert first_message.metadata.tool_call_id == "call_123"
      assert first_message.metadata.tool_name == "get_weather"

      # Second tool result
      second_message = Enum.at(history, 1)
      assert second_message.role == "tool"
      assert second_message.content == "Temperature is 75°F"
      assert second_message.metadata.tool_call_id == "call_124"
      assert second_message.metadata.tool_name == "get_temperature"
    end

    test "retrieving complete conversation history in chronological order" do
      {:ok, conv_id} = ConversationManager.create_conversation()

      # Add messages in order: user → assistant → tool results
      :ok = ConversationManager.add_user_message(conv_id, "What's the weather?")

      response = %{
        content: "Let me check that for you",
        tool_calls: [%{name: "get_weather", id: "call_1"}]
      }

      :ok = ConversationManager.add_assistant_response(conv_id, response)

      tool_results = [
        %{tool_call_id: "call_1", name: "get_weather", content: "Sunny, 75°F"}
      ]

      :ok = ConversationManager.add_tool_results(conv_id, tool_results)

      # Get history
      {:ok, history} = ConversationManager.get_history(conv_id)

      # Verify chronological order
      assert length(history) == 3
      assert Enum.at(history, 0).role == "user"
      assert Enum.at(history, 1).role == "assistant"
      assert Enum.at(history, 2).role == "tool"

      # Verify all messages have timestamps
      Enum.each(history, fn message ->
        assert %DateTime{} = message.timestamp
      end)

      # Verify timestamps are in order (each should be >= previous)
      [msg1, msg2, msg3] = history

      assert DateTime.compare(msg1.timestamp, msg2.timestamp) in [:lt, :eq]
      assert DateTime.compare(msg2.timestamp, msg3.timestamp) in [:lt, :eq]
    end
  end

  describe "5.3 Tool Configuration" do
    test "setting tools for conversation" do
      {:ok, conv_id} = ConversationManager.create_conversation()

      # Define tools
      tools = [
        %{name: "get_weather", description: "Get current weather"},
        %{name: "get_time", description: "Get current time"}
      ]

      # Set tools
      assert :ok = ConversationManager.set_tools(conv_id, tools)
    end

    test "getting tools for conversation" do
      {:ok, conv_id} = ConversationManager.create_conversation()

      # Set tools
      tools = [
        %{name: "get_weather", description: "Get current weather"},
        %{name: "calculator", description: "Perform calculations"}
      ]

      :ok = ConversationManager.set_tools(conv_id, tools)

      # Get tools
      assert {:ok, retrieved_tools} = ConversationManager.get_tools(conv_id)

      # Verify tools match
      assert length(retrieved_tools) == 2
      assert Enum.any?(retrieved_tools, &(&1.name == "get_weather"))
      assert Enum.any?(retrieved_tools, &(&1.name == "calculator"))
    end

    test "finding tool by name" do
      {:ok, conv_id} = ConversationManager.create_conversation()

      # Set multiple tools
      tools = [
        %{name: "get_weather", description: "Get current weather", params: %{}},
        %{name: "calculator", description: "Perform calculations", params: %{}}
      ]

      :ok = ConversationManager.set_tools(conv_id, tools)

      # Find existing tool
      assert {:ok, tool} = ConversationManager.find_tool_by_name(conv_id, "get_weather")
      assert tool.name == "get_weather"
      assert tool.description == "Get current weather"

      # Find non-existent tool
      assert {:error, :not_found} =
               ConversationManager.find_tool_by_name(conv_id, "non_existent")
    end
  end

  describe "5.4 Options Management" do
    test "setting conversation options (model, temperature, etc.)" do
      {:ok, conv_id} = ConversationManager.create_conversation()

      # Set options
      options = %{
        model: "gpt-4",
        temperature: 0.7,
        max_tokens: 1000,
        top_p: 0.9
      }

      assert :ok = ConversationManager.set_options(conv_id, options)
    end

    test "getting conversation options" do
      {:ok, conv_id} = ConversationManager.create_conversation()

      # Set options
      options = %{
        model: "gpt-4",
        temperature: 0.7,
        max_tokens: 1000
      }

      :ok = ConversationManager.set_options(conv_id, options)

      # Get options
      assert {:ok, retrieved_options} = ConversationManager.get_options(conv_id)

      # Verify options match
      assert retrieved_options.model == "gpt-4"
      assert retrieved_options.temperature == 0.7
      assert retrieved_options.max_tokens == 1000
    end
  end

  describe "5.5 Metadata" do
    test "conversation metadata includes creation time" do
      {:ok, conv_id} = ConversationManager.create_conversation()

      # Get metadata
      {:ok, metadata} = ConversationManager.get_conversation_metadata(conv_id)

      # Verify created_at timestamp exists
      assert Map.has_key?(metadata, :created_at)
      assert %DateTime{} = metadata.created_at
    end

    test "metadata includes message count" do
      {:ok, conv_id} = ConversationManager.create_conversation()

      # Add 3 messages
      :ok = ConversationManager.add_user_message(conv_id, "Message 1")
      :ok = ConversationManager.add_user_message(conv_id, "Message 2")
      :ok = ConversationManager.add_user_message(conv_id, "Message 3")

      # Get metadata
      {:ok, metadata} = ConversationManager.get_conversation_metadata(conv_id)

      # Verify message_count is 3
      assert metadata.message_count == 3
    end

    test "last_activity updates on message add" do
      {:ok, conv_id} = ConversationManager.create_conversation()

      # Get initial metadata
      {:ok, initial_metadata} = ConversationManager.get_conversation_metadata(conv_id)
      initial_last_activity = initial_metadata.last_activity

      # Wait a bit to ensure timestamp difference
      Process.sleep(100)

      # Add message
      :ok = ConversationManager.add_user_message(conv_id, "New message")

      # Get updated metadata
      {:ok, updated_metadata} = ConversationManager.get_conversation_metadata(conv_id)
      updated_last_activity = updated_metadata.last_activity

      # Verify last_activity is later than initial
      assert DateTime.compare(updated_last_activity, initial_last_activity) == :gt
    end
  end

  describe "5.6 Error Handling" do
    test "operations on non-existent conversation return error" do
      non_existent_id = "non_existent_conversation_id"

      # Try various operations
      assert {:error, :conversation_not_found} =
               ConversationManager.get_history(non_existent_id)

      assert {:error, :conversation_not_found} =
               ConversationManager.get_tools(non_existent_id)

      assert {:error, :conversation_not_found} =
               ConversationManager.get_options(non_existent_id)

      assert {:error, :conversation_not_found} =
               ConversationManager.get_conversation_metadata(non_existent_id)
    end

    test "adding message to non-existent conversation returns error" do
      non_existent_id = "non_existent_conversation_id"

      assert {:error, :conversation_not_found} =
               ConversationManager.add_user_message(non_existent_id, "Test message")
    end

    test "setting tools for non-existent conversation returns error" do
      non_existent_id = "non_existent_conversation_id"

      assert {:error, :conversation_not_found} =
               ConversationManager.set_tools(non_existent_id, [])
    end
  end
end
