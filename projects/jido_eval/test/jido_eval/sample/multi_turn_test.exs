defmodule Jido.Eval.Sample.MultiTurnTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Jido.Eval.Sample.MultiTurn
  alias Jido.AI.Message

  doctest MultiTurn

  describe "new/1" do
    test "creates a valid multi-turn sample" do
      conversation = [
        %Message{role: :user, content: "Hello"},
        %Message{role: :assistant, content: "Hi! How can I help?"}
      ]

      attrs = %{
        conversation: conversation,
        tags: %{"category" => "greeting"}
      }

      assert {:ok, sample} = MultiTurn.new(attrs)
      assert sample.conversation == conversation
      assert sample.tags == %{"category" => "greeting"}
    end

    test "creates sample with default empty conversation" do
      attrs = %{conversation: [%Message{role: :user, content: "Hello"}]}
      assert {:ok, sample} = MultiTurn.new(attrs)
      assert length(sample.conversation) == 1
    end

    test "rejects sample with empty conversation" do
      attrs = %{conversation: []}
      assert {:error, reason} = MultiTurn.new(attrs)
      assert reason == "Conversation cannot be empty"
    end

    test "rejects sample with non-list conversation" do
      attrs = %{conversation: "not a list"}
      assert {:error, reason} = MultiTurn.new(attrs)
      assert reason == "Conversation must be a list"
    end

    test "rejects sample with invalid messages" do
      attrs = %{conversation: ["not a message"]}
      assert {:error, reason} = MultiTurn.new(attrs)
      assert reason == "All conversation items must be valid Messages"
    end
  end

  describe "validate/1" do
    test "validates sample with valid conversation" do
      sample = %MultiTurn{
        conversation: [%Message{role: :user, content: "Hello"}]
      }

      assert :ok = MultiTurn.validate(sample)
    end

    test "rejects sample with empty conversation" do
      sample = %MultiTurn{conversation: []}
      assert {:error, _reason} = MultiTurn.validate(sample)
    end

    test "rejects sample with invalid messages" do
      sample = %MultiTurn{conversation: ["invalid"]}
      assert {:error, _reason} = MultiTurn.validate(sample)
    end
  end

  describe "add_message/2" do
    test "adds a Message to conversation" do
      sample = %MultiTurn{conversation: []}
      message = %Message{role: :user, content: "Hello"}

      updated = MultiTurn.add_message(sample, message)

      assert length(updated.conversation) == 1
      assert hd(updated.conversation) == message
    end

    test "adds a string message with role" do
      sample = %MultiTurn{conversation: []}
      updated = MultiTurn.add_message(sample, "Hello", :user)

      assert length(updated.conversation) == 1
      assert [%Message{role: :user, content: "Hello"}] = updated.conversation
    end

    test "appends to existing conversation" do
      initial_message = %Message{role: :user, content: "Hello"}
      sample = %MultiTurn{conversation: [initial_message]}
      new_message = %Message{role: :assistant, content: "Hi!"}

      updated = MultiTurn.add_message(sample, new_message)

      assert length(updated.conversation) == 2
      assert updated.conversation == [initial_message, new_message]
    end
  end

  describe "last_message/1" do
    test "returns last message from conversation" do
      messages = [
        %Message{role: :user, content: "Hello"},
        %Message{role: :assistant, content: "Hi!"},
        %Message{role: :user, content: "How are you?"}
      ]

      sample = %MultiTurn{conversation: messages}
      last = MultiTurn.last_message(sample)

      assert last.content == "How are you?"
      assert last.role == :user
    end

    test "returns nil for empty conversation" do
      sample = %MultiTurn{conversation: []}
      assert nil == MultiTurn.last_message(sample)
    end
  end

  describe "messages_by_role/2" do
    test "filters messages by role" do
      messages = [
        %Message{role: :user, content: "Hello"},
        %Message{role: :assistant, content: "Hi!"},
        %Message{role: :user, content: "How are you?"},
        %Message{role: :assistant, content: "I'm doing well!"}
      ]

      sample = %MultiTurn{conversation: messages}
      user_messages = MultiTurn.messages_by_role(sample, :user)
      assistant_messages = MultiTurn.messages_by_role(sample, :assistant)

      assert length(user_messages) == 2
      assert length(assistant_messages) == 2
      assert Enum.all?(user_messages, &(&1.role == :user))
      assert Enum.all?(assistant_messages, &(&1.role == :assistant))
    end

    test "returns empty list when no messages match role" do
      messages = [%Message{role: :user, content: "Hello"}]
      sample = %MultiTurn{conversation: messages}

      assert [] == MultiTurn.messages_by_role(sample, :system)
    end
  end

  describe "turn_count/1" do
    test "counts messages in conversation" do
      messages = [
        %Message{role: :user, content: "Hello"},
        %Message{role: :assistant, content: "Hi!"}
      ]

      sample = %MultiTurn{conversation: messages}
      assert 2 == MultiTurn.turn_count(sample)
    end

    test "returns 0 for empty conversation" do
      sample = %MultiTurn{conversation: []}
      assert 0 == MultiTurn.turn_count(sample)
    end
  end

  describe "to_map/1 and from_map/1" do
    test "round-trip conversion preserves data" do
      original = %MultiTurn{
        id: "conv_001",
        conversation: [
          %Message{role: :user, content: "Hello"},
          %Message{role: :assistant, content: "Hi!"}
        ],
        retrieved_contexts: ["context1"],
        reference_contexts: ["ref1"],
        reference: "Expected outcome",
        rubrics: %{"quality" => "high"},
        tags: %{"category" => "test"}
      }

      map = MultiTurn.to_map(original)
      assert {:ok, restored} = MultiTurn.from_map(map)

      assert restored.id == original.id
      assert restored.conversation == original.conversation
      assert restored.retrieved_contexts == original.retrieved_contexts
      assert restored.reference_contexts == original.reference_contexts
      assert restored.reference == original.reference
      assert restored.rubrics == original.rubrics
      assert restored.tags == original.tags
    end

    test "to_map converts messages to maps" do
      sample = %MultiTurn{
        conversation: [%Message{role: :user, content: "Hello"}]
      }

      map = MultiTurn.to_map(sample)
      conversation_maps = map.conversation

      assert is_list(conversation_maps)
      assert [%{role: :user, content: "Hello"}] = conversation_maps
    end

    test "from_map converts message maps to structs" do
      map = %{
        conversation: [
          %{role: :user, content: "Hello"},
          %{role: :assistant, content: "Hi!"}
        ]
      }

      assert {:ok, sample} = MultiTurn.from_map(map)
      assert [msg1, msg2] = sample.conversation
      assert %Message{role: :user, content: "Hello"} = msg1
      assert %Message{role: :assistant, content: "Hi!"} = msg2
    end

    test "from_map handles string keys" do
      map = %{
        "id" => "test",
        "conversation" => [%{"role" => "user", "content" => "Hello"}],
        "tags" => %{"key" => "value"}
      }

      assert {:ok, sample} = MultiTurn.from_map(map)
      assert sample.id == "test"
      assert length(sample.conversation) == 1
      assert sample.tags == %{"key" => "value"}
    end
  end

  describe "property tests" do
    property "conversation must always be a non-empty list of Messages" do
      check all(
              messages <-
                list_of(
                  fixed_map(%{
                    role: member_of([:user, :assistant, :system]),
                    content: string(:printable, min_length: 1, max_length: 100)
                  }),
                  min_length: 1,
                  max_length: 10
                ),
              max_runs: 50
            ) do
        conversation = Enum.map(messages, &struct(Message, &1))
        attrs = %{conversation: conversation}

        assert {:ok, sample} = MultiTurn.new(attrs)
        assert :ok = MultiTurn.validate(sample)
        assert length(sample.conversation) == length(messages)
      end
    end

    property "round-trip serialization preserves conversation structure" do
      check all(
              id <- string(:alphanumeric, min_length: 1, max_length: 20),
              conversation_size <- integer(1..5),
              max_runs: 30
            ) do
        messages =
          Enum.map(1..conversation_size, fn i ->
            role = if rem(i, 2) == 1, do: :user, else: :assistant
            %Message{role: role, content: "Message #{i}"}
          end)

        original = %MultiTurn{
          id: id,
          conversation: messages,
          tags: %{"test" => "property"}
        }

        map = MultiTurn.to_map(original)
        assert {:ok, restored} = MultiTurn.from_map(map)

        assert restored.id == original.id
        assert restored.conversation == original.conversation
        assert restored.tags == original.tags
      end
    end
  end

  describe "edge cases" do
    test "handles very long conversations" do
      messages =
        Enum.map(1..1000, fn i ->
          role = if rem(i, 2) == 1, do: :user, else: :assistant
          %Message{role: role, content: "Message #{i}"}
        end)

      attrs = %{conversation: messages}
      assert {:ok, sample} = MultiTurn.new(attrs)
      assert length(sample.conversation) == 1000
    end

    test "handles unicode content in messages" do
      messages = [
        %Message{role: :user, content: "Hello 世界 🌍"},
        %Message{role: :assistant, content: "مرحبا بالعالم"}
      ]

      attrs = %{conversation: messages}
      assert {:ok, sample} = MultiTurn.new(attrs)
      assert sample.conversation == messages
    end

    test "handles all message roles" do
      messages = [
        %Message{role: :user, content: "User message"},
        %Message{role: :assistant, content: "Assistant message"},
        %Message{role: :system, content: "System message"},
        %Message{role: :tool, content: "Tool message", tool_call_id: "tool_123"}
      ]

      attrs = %{conversation: messages}
      assert {:ok, sample} = MultiTurn.new(attrs)
      assert sample.conversation == messages
    end

    test "handles complex Message structures" do
      complex_message = %Message{
        role: :assistant,
        content: "Complex response",
        tool_calls: [%{"id" => "call_1", "function" => %{"name" => "test"}}],
        metadata: %{"provider" => "test"}
      }

      messages = [
        %Message{role: :user, content: "Hello"},
        complex_message
      ]

      attrs = %{conversation: messages}
      assert {:ok, sample} = MultiTurn.new(attrs)
      assert sample.conversation == messages
    end
  end
end
