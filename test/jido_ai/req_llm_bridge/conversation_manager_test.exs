defmodule Jido.AI.ReqLlmBridge.ConversationManagerTest do
  use ExUnit.Case, async: false

  @moduletag :capture_log

  alias Jido.AI.ReqLlmBridge.ConversationManager

  setup do
    # ConversationManager is already started by the application
    # Just ensure we have a clean state by creating a fresh conversation ID
    :ok
  end

  describe "conversation lifecycle" do
    test "create_conversation/0 creates new conversation" do
      assert {:ok, conv_id} = ConversationManager.create_conversation()
      assert is_binary(conv_id)
      assert String.length(conv_id) == 32
    end

    test "create_conversation/0 creates unique conversations" do
      {:ok, conv_id1} = ConversationManager.create_conversation()
      {:ok, conv_id2} = ConversationManager.create_conversation()

      assert conv_id1 != conv_id2
    end

    test "end_conversation/1 removes conversation" do
      {:ok, conv_id} = ConversationManager.create_conversation()

      # Verify conversation exists
      assert {:ok, []} = ConversationManager.get_history(conv_id)

      # End conversation
      assert :ok = ConversationManager.end_conversation(conv_id)

      # Verify conversation no longer exists
      assert {:error, :conversation_not_found} = ConversationManager.get_history(conv_id)
    end

    test "list_conversations/0 returns active conversations" do
      {:ok, conv_ids_before} = ConversationManager.list_conversations()

      {:ok, conv_id1} = ConversationManager.create_conversation()
      {:ok, conv_id2} = ConversationManager.create_conversation()

      {:ok, conv_ids_after} = ConversationManager.list_conversations()

      assert conv_id1 in conv_ids_after
      assert conv_id2 in conv_ids_after
      assert length(conv_ids_after) == length(conv_ids_before) + 2
    end
  end

  describe "tool management" do
    test "set_tools/2 and get_tools/1 work correctly" do
      {:ok, conv_id} = ConversationManager.create_conversation()

      tool_descriptors = [
        %{name: "weather_tool", description: "Gets weather", callback: fn _ -> :ok end},
        %{name: "calculator", description: "Does math", callback: fn _ -> :ok end}
      ]

      assert :ok = ConversationManager.set_tools(conv_id, tool_descriptors)
      assert {:ok, ^tool_descriptors} = ConversationManager.get_tools(conv_id)
    end

    test "set_tools/2 overwrites existing tools" do
      {:ok, conv_id} = ConversationManager.create_conversation()

      initial_tools = [%{name: "tool1", description: "First tool"}]
      updated_tools = [%{name: "tool2", description: "Second tool"}]

      ConversationManager.set_tools(conv_id, initial_tools)
      ConversationManager.set_tools(conv_id, updated_tools)

      {:ok, tools} = ConversationManager.get_tools(conv_id)
      assert tools == updated_tools
      assert length(tools) == 1
    end

    test "find_tool_by_name/2 finds tools correctly" do
      {:ok, conv_id} = ConversationManager.create_conversation()

      weather_tool = %{name: "get_weather", description: "Weather tool"}
      calc_tool = %{name: "calculator", description: "Math tool"}
      tools = [weather_tool, calc_tool]

      ConversationManager.set_tools(conv_id, tools)

      assert {:ok, ^weather_tool} = ConversationManager.find_tool_by_name(conv_id, "get_weather")
      assert {:ok, ^calc_tool} = ConversationManager.find_tool_by_name(conv_id, "calculator")
      assert {:error, :not_found} = ConversationManager.find_tool_by_name(conv_id, "nonexistent")
    end

    test "tool operations fail for non-existent conversation" do
      fake_conv_id = "nonexistent_conversation_id"

      assert {:error, :conversation_not_found} = ConversationManager.get_tools(fake_conv_id)
      assert {:error, :conversation_not_found} = ConversationManager.set_tools(fake_conv_id, [])

      assert {:error, :conversation_not_found} =
               ConversationManager.find_tool_by_name(fake_conv_id, "tool")
    end
  end

  describe "options management" do
    test "set_options/2 and get_options/1 work correctly" do
      {:ok, conv_id} = ConversationManager.create_conversation()

      options = %{
        model: "gpt-4",
        temperature: 0.7,
        max_tokens: 1000,
        custom_option: "test_value"
      }

      assert :ok = ConversationManager.set_options(conv_id, options)
      assert {:ok, ^options} = ConversationManager.get_options(conv_id)
    end

    test "set_options/2 overwrites existing options" do
      {:ok, conv_id} = ConversationManager.create_conversation()

      initial_options = %{model: "gpt-3.5-turbo", temperature: 0.5}
      updated_options = %{model: "gpt-4", temperature: 0.8, max_tokens: 2000}

      ConversationManager.set_options(conv_id, initial_options)
      ConversationManager.set_options(conv_id, updated_options)

      {:ok, options} = ConversationManager.get_options(conv_id)
      assert options == updated_options
    end

    test "options operations fail for non-existent conversation" do
      fake_conv_id = "nonexistent_conversation_id"

      assert {:error, :conversation_not_found} = ConversationManager.get_options(fake_conv_id)

      assert {:error, :conversation_not_found} =
               ConversationManager.set_options(fake_conv_id, %{})
    end
  end

  describe "message management" do
    test "add_user_message/3 adds message correctly" do
      {:ok, conv_id} = ConversationManager.create_conversation()

      message_content = "Hello, how are you?"
      metadata = %{client: "test_client"}

      assert :ok = ConversationManager.add_user_message(conv_id, message_content, metadata)

      {:ok, messages} = ConversationManager.get_history(conv_id)
      assert length(messages) == 1

      message = hd(messages)
      assert message.role == "user"
      assert message.content == message_content
      assert message.metadata == metadata
      assert %DateTime{} = message.timestamp
    end

    test "add_assistant_response/3 handles simple response" do
      {:ok, conv_id} = ConversationManager.create_conversation()

      response = %{
        content: "Hello! I'm doing well, thank you.",
        usage: %{prompt_tokens: 10, completion_tokens: 15, total_tokens: 25}
      }

      assert :ok = ConversationManager.add_assistant_response(conv_id, response)

      {:ok, messages} = ConversationManager.get_history(conv_id)
      assert length(messages) == 1

      message = hd(messages)
      assert message.role == "assistant"
      assert message.content == "Hello! I'm doing well, thank you."
      assert message.metadata.usage == response.usage
    end

    test "add_assistant_response/3 handles complex response with tool calls" do
      {:ok, conv_id} = ConversationManager.create_conversation()

      response = %{
        content: [
          %{type: "text", text: "Let me check the weather for you."}
        ],
        tool_calls: [
          %{id: "call_1", function: %{name: "get_weather", arguments: %{location: "Paris"}}}
        ],
        usage: %{total_tokens: 50},
        model: "gpt-4"
      }

      assert :ok = ConversationManager.add_assistant_response(conv_id, response)

      {:ok, messages} = ConversationManager.get_history(conv_id)
      message = hd(messages)

      assert message.role == "assistant"
      assert message.content == "Let me check the weather for you."
      assert message.metadata.tool_calls == response.tool_calls
      assert message.metadata.model == "gpt-4"
    end

    test "add_tool_results/3 adds tool results as messages" do
      {:ok, conv_id} = ConversationManager.create_conversation()

      tool_results = [
        %{
          tool_call_id: "call_1",
          name: "get_weather",
          content: ~s({"temperature": 22, "condition": "sunny"})
        },
        %{
          tool_call_id: "call_2",
          name: "calculator",
          content: ~s({"result": 42}),
          error: false
        }
      ]

      metadata = %{execution_time: 1250}

      assert :ok = ConversationManager.add_tool_results(conv_id, tool_results, metadata)

      {:ok, messages} = ConversationManager.get_history(conv_id)
      assert length(messages) == 2

      Enum.zip(messages, tool_results)
      |> Enum.each(fn {message, expected_result} ->
        assert message.role == "tool"
        assert message.content == expected_result.content
        assert message.metadata.tool_call_id == expected_result.tool_call_id
        assert message.metadata.tool_name == expected_result.name
        assert Map.has_key?(message.metadata, :error)
      end)
    end

    test "get_history/1 returns messages in chronological order" do
      {:ok, conv_id} = ConversationManager.create_conversation()

      # Add messages in sequence
      :ok = ConversationManager.add_user_message(conv_id, "First message")
      # Ensure different timestamps
      Process.sleep(10)
      :ok = ConversationManager.add_assistant_response(conv_id, %{content: "Second message"})
      Process.sleep(10)
      :ok = ConversationManager.add_user_message(conv_id, "Third message")

      {:ok, messages} = ConversationManager.get_history(conv_id)
      assert length(messages) == 3

      contents = Enum.map(messages, & &1.content)
      assert contents == ["First message", "Second message", "Third message"]

      # Verify timestamps are in ascending order
      timestamps = Enum.map(messages, & &1.timestamp)
      assert timestamps == Enum.sort(timestamps, DateTime)
    end

    test "message operations fail for non-existent conversation" do
      fake_conv_id = "nonexistent_conversation_id"

      assert {:error, :conversation_not_found} = ConversationManager.get_history(fake_conv_id)

      assert {:error, :conversation_not_found} =
               ConversationManager.add_user_message(fake_conv_id, "test")

      assert {:error, :conversation_not_found} =
               ConversationManager.add_assistant_response(fake_conv_id, %{content: "test"})

      assert {:error, :conversation_not_found} =
               ConversationManager.add_tool_results(fake_conv_id, [])
    end
  end

  describe "conversation metadata" do
    test "get_conversation_metadata/1 returns correct metadata" do
      {:ok, conv_id} = ConversationManager.create_conversation()

      # Add some messages and tools to test metadata
      ConversationManager.set_tools(conv_id, [%{name: "tool1"}, %{name: "tool2"}])
      ConversationManager.add_user_message(conv_id, "Message 1")
      ConversationManager.add_assistant_response(conv_id, %{content: "Response 1"})

      {:ok, metadata} = ConversationManager.get_conversation_metadata(conv_id)

      assert metadata.id == conv_id
      assert metadata.message_count == 2
      assert metadata.tool_count == 2
      assert %DateTime{} = metadata.created_at
      assert %DateTime{} = metadata.last_activity
    end

    test "metadata tracks message count correctly" do
      {:ok, conv_id} = ConversationManager.create_conversation()

      {:ok, initial_metadata} = ConversationManager.get_conversation_metadata(conv_id)
      assert initial_metadata.message_count == 0

      ConversationManager.add_user_message(conv_id, "Message 1")
      {:ok, metadata_after_1} = ConversationManager.get_conversation_metadata(conv_id)
      assert metadata_after_1.message_count == 1

      ConversationManager.add_assistant_response(conv_id, %{content: "Response 1"})
      {:ok, metadata_after_2} = ConversationManager.get_conversation_metadata(conv_id)
      assert metadata_after_2.message_count == 2

      # Tool results count as messages
      tool_results = [%{tool_call_id: "call_1", content: "result"}]
      ConversationManager.add_tool_results(conv_id, tool_results)
      {:ok, metadata_after_tools} = ConversationManager.get_conversation_metadata(conv_id)
      assert metadata_after_tools.message_count == 3
    end

    test "last_activity updates with conversation activity" do
      {:ok, conv_id} = ConversationManager.create_conversation()

      {:ok, initial_metadata} = ConversationManager.get_conversation_metadata(conv_id)
      initial_activity = initial_metadata.last_activity

      # Ensure time difference
      Process.sleep(50)

      ConversationManager.add_user_message(conv_id, "Update activity")

      {:ok, updated_metadata} = ConversationManager.get_conversation_metadata(conv_id)
      updated_activity = updated_metadata.last_activity

      assert DateTime.compare(updated_activity, initial_activity) == :gt
    end
  end

  describe "error handling and edge cases" do
    test "handles empty message content gracefully" do
      {:ok, conv_id} = ConversationManager.create_conversation()

      assert :ok = ConversationManager.add_user_message(conv_id, "")
      assert :ok = ConversationManager.add_assistant_response(conv_id, %{content: ""})

      {:ok, messages} = ConversationManager.get_history(conv_id)
      assert length(messages) == 2
      assert Enum.all?(messages, fn msg -> msg.content == "" end)
    end

    test "handles malformed assistant response gracefully" do
      {:ok, conv_id} = ConversationManager.create_conversation()

      # Response with unexpected structure
      malformed_response = %{
        content: nil,
        weird_field: "should be ignored"
      }

      assert :ok = ConversationManager.add_assistant_response(conv_id, malformed_response)

      {:ok, messages} = ConversationManager.get_history(conv_id)
      message = hd(messages)

      assert message.role == "assistant"
      # Should be converted to string
      assert is_binary(message.content)
    end

    test "handles empty tool results list" do
      {:ok, conv_id} = ConversationManager.create_conversation()

      assert :ok = ConversationManager.add_tool_results(conv_id, [])

      {:ok, messages} = ConversationManager.get_history(conv_id)
      assert messages == []
    end

    test "handles large message history efficiently" do
      {:ok, conv_id} = ConversationManager.create_conversation()

      # Add many messages
      Enum.each(1..100, fn i ->
        ConversationManager.add_user_message(conv_id, "Message #{i}")
      end)

      start_time = System.monotonic_time(:millisecond)
      {:ok, messages} = ConversationManager.get_history(conv_id)
      end_time = System.monotonic_time(:millisecond)

      assert length(messages) == 100
      # Should be very fast
      assert end_time - start_time < 100
    end

    test "handles content with different types" do
      {:ok, conv_id} = ConversationManager.create_conversation()

      # Test different content types in assistant response
      test_cases = [
        %{content: "simple string"},
        %{content: ["list", "of", "strings"]},
        %{content: [%{type: "text", text: "structured content"}]},
        # Number
        %{content: 42},
        # Map
        %{content: %{nested: "object"}}
      ]

      Enum.each(test_cases, fn response ->
        assert :ok = ConversationManager.add_assistant_response(conv_id, response)
      end)

      {:ok, messages} = ConversationManager.get_history(conv_id)
      assert length(messages) == length(test_cases)

      # All content should be converted to strings
      assert Enum.all?(messages, fn msg -> is_binary(msg.content) end)
    end
  end

  describe "concurrent access" do
    test "handles concurrent conversation creation" do
      tasks =
        Enum.map(1..10, fn _i ->
          Task.async(fn ->
            ConversationManager.create_conversation()
          end)
        end)

      results = Task.await_many(tasks, 5_000)

      # All should succeed
      assert Enum.all?(results, fn
               {:ok, _id} -> true
               _ -> false
             end)

      # All IDs should be unique
      ids = Enum.map(results, fn {:ok, id} -> id end)
      assert length(Enum.uniq(ids)) == 10
    end

    test "handles concurrent message additions to same conversation" do
      {:ok, conv_id} = ConversationManager.create_conversation()

      tasks =
        Enum.map(1..20, fn i ->
          Task.async(fn ->
            ConversationManager.add_user_message(conv_id, "Concurrent message #{i}")
          end)
        end)

      results = Task.await_many(tasks, 5_000)

      # All additions should succeed
      assert Enum.all?(results, fn
               :ok -> true
               _ -> false
             end)

      {:ok, messages} = ConversationManager.get_history(conv_id)
      assert length(messages) == 20
    end

    test "handles concurrent operations on different conversations" do
      # Create multiple conversations concurrently and operate on them
      conv_tasks =
        Enum.map(1..5, fn i ->
          Task.async(fn ->
            {:ok, conv_id} = ConversationManager.create_conversation()
            ConversationManager.add_user_message(conv_id, "Message in conversation #{i}")
            ConversationManager.set_tools(conv_id, [%{name: "tool_#{i}"}])
            conv_id
          end)
        end)

      conv_ids = Task.await_many(conv_tasks, 5_000)

      # Verify each conversation has its own state
      Enum.with_index(conv_ids, 1)
      |> Enum.each(fn {conv_id, i} ->
        {:ok, messages} = ConversationManager.get_history(conv_id)
        assert length(messages) == 1
        assert hd(messages).content == "Message in conversation #{i}"

        {:ok, tools} = ConversationManager.get_tools(conv_id)
        assert length(tools) == 1
        assert hd(tools).name == "tool_#{i}"
      end)
    end
  end
end
