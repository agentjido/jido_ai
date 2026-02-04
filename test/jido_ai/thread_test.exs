defmodule Jido.AI.ThreadTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Thread
  alias Jido.AI.Thread.Entry

  # ============================================================================
  # Thread Creation
  # ============================================================================

  describe "new/1" do
    test "creates empty thread with generated ID" do
      thread = Thread.new()
      assert is_binary(thread.id)
      assert thread.entries == []
      assert thread.system_prompt == nil
    end

    test "creates thread with custom ID" do
      thread = Thread.new(id: "custom-123")
      assert thread.id == "custom-123"
    end

    test "creates thread with system prompt" do
      thread = Thread.new(system_prompt: "You are helpful.")
      assert thread.system_prompt == "You are helpful."
    end
  end

  # ============================================================================
  # Appending Messages
  # ============================================================================

  describe "append_user/2" do
    test "appends user message" do
      thread =
        Thread.new()
        |> Thread.append_user("Hello!")

      assert Thread.length(thread) == 1
      [entry] = thread.entries
      assert entry.role == :user
      assert entry.content == "Hello!"
      assert %DateTime{} = entry.timestamp
    end

    test "appends multiple user messages" do
      thread =
        Thread.new()
        |> Thread.append_user("First")
        |> Thread.append_user("Second")

      assert Thread.length(thread) == 2
      # Entries are stored in reverse order internally
      [second, first] = thread.entries
      assert first.content == "First"
      assert second.content == "Second"
    end
  end

  describe "append_assistant/3" do
    test "appends assistant message without tool calls" do
      thread =
        Thread.new()
        |> Thread.append_assistant("Hello, I'm here to help!")

      assert Thread.length(thread) == 1
      [entry] = thread.entries
      assert entry.role == :assistant
      assert entry.content == "Hello, I'm here to help!"
      assert entry.tool_calls == nil
    end

    test "appends assistant message with tool calls" do
      tool_calls = [
        %{id: "tc_1", name: "calculator", arguments: %{x: 1, y: 2}}
      ]

      thread =
        Thread.new()
        |> Thread.append_assistant("", tool_calls)

      assert Thread.length(thread) == 1
      [entry] = thread.entries
      assert entry.role == :assistant
      assert entry.content == ""
      assert entry.tool_calls == tool_calls
    end
  end

  describe "append_tool_result/4" do
    test "appends tool result" do
      thread =
        Thread.new()
        |> Thread.append_tool_result("tc_1", "calculator", ~s({"result": 3}))

      assert Thread.length(thread) == 1
      [entry] = thread.entries
      assert entry.role == :tool
      assert entry.tool_call_id == "tc_1"
      assert entry.name == "calculator"
      assert entry.content == ~s({"result": 3})
    end
  end

  describe "append/2" do
    test "appends arbitrary entry with timestamp" do
      entry = %Entry{role: :user, content: "Test"}
      thread = Thread.new() |> Thread.append(entry)

      [appended] = thread.entries
      assert appended.content == "Test"
      assert %DateTime{} = appended.timestamp
    end

    test "preserves existing timestamp when provided" do
      original_time = ~U[2024-01-15 10:30:00Z]
      entry = %Entry{role: :user, content: "Test", timestamp: original_time}
      thread = Thread.new() |> Thread.append(entry)

      [appended] = thread.entries
      assert appended.timestamp == original_time
    end
  end

  # ============================================================================
  # Projection to Messages
  # ============================================================================

  describe "to_messages/2" do
    test "returns empty list for empty thread" do
      thread = Thread.new()
      assert Thread.to_messages(thread) == []
    end

    test "projects user message" do
      thread = Thread.new() |> Thread.append_user("Hello")
      messages = Thread.to_messages(thread)

      assert [%{role: :user, content: "Hello"}] = messages
    end

    test "prepends system prompt when present" do
      thread =
        Thread.new(system_prompt: "Be helpful")
        |> Thread.append_user("Hello")

      messages = Thread.to_messages(thread)

      assert [
               %{role: :system, content: "Be helpful"},
               %{role: :user, content: "Hello"}
             ] = messages
    end

    test "projects full conversation" do
      thread =
        Thread.new(system_prompt: "You are helpful.")
        |> Thread.append_user("Hello")
        |> Thread.append_assistant("Hi there!")
        |> Thread.append_user("What is 2+2?")
        |> Thread.append_assistant("", [%{id: "tc_1", name: "calc", arguments: %{}}])
        |> Thread.append_tool_result("tc_1", "calc", "4")
        |> Thread.append_assistant("The answer is 4.")

      messages = Thread.to_messages(thread)

      assert length(messages) == 7
      assert Enum.at(messages, 0).role == :system
      assert Enum.at(messages, 1).role == :user
      assert Enum.at(messages, 2).role == :assistant
      assert Enum.at(messages, 3).role == :user
      assert Enum.at(messages, 4).role == :assistant
      assert Enum.at(messages, 5).role == :tool
      assert Enum.at(messages, 6).role == :assistant
    end

    test "respects limit option" do
      thread =
        Thread.new(system_prompt: "System")
        |> Thread.append_user("First")
        |> Thread.append_assistant("Reply 1")
        |> Thread.append_user("Second")
        |> Thread.append_assistant("Reply 2")

      # Limit to last 2 entries
      messages = Thread.to_messages(thread, limit: 2)

      # System prompt + last 2 entries
      assert length(messages) == 3
      assert Enum.at(messages, 0).role == :system
      assert Enum.at(messages, 1).content == "Second"
      assert Enum.at(messages, 2).content == "Reply 2"
    end

    test "limit: 0 returns only system prompt" do
      thread =
        Thread.new(system_prompt: "System")
        |> Thread.append_user("First")
        |> Thread.append_assistant("Reply")

      messages = Thread.to_messages(thread, limit: 0)

      assert length(messages) == 1
      assert Enum.at(messages, 0).role == :system
    end

    test "limit: 0 returns empty list when no system prompt" do
      thread =
        Thread.new()
        |> Thread.append_user("First")

      messages = Thread.to_messages(thread, limit: 0)

      assert messages == []
    end
  end

  # ============================================================================
  # Utility Functions
  # ============================================================================

  describe "length/1" do
    test "returns 0 for empty thread" do
      assert Thread.length(Thread.new()) == 0
    end

    test "returns entry count" do
      thread =
        Thread.new()
        |> Thread.append_user("One")
        |> Thread.append_assistant("Two")

      assert Thread.length(thread) == 2
    end
  end

  describe "empty?/1" do
    test "returns true for empty thread" do
      assert Thread.empty?(Thread.new()) == true
    end

    test "returns false for non-empty thread" do
      thread = Thread.new() |> Thread.append_user("Hello")
      assert Thread.empty?(thread) == false
    end
  end

  describe "clear/1" do
    test "removes all entries but keeps system prompt" do
      thread =
        Thread.new(system_prompt: "Be helpful")
        |> Thread.append_user("Hello")
        |> Thread.append_assistant("Hi!")
        |> Thread.clear()

      assert Thread.empty?(thread) == true
      assert thread.system_prompt == "Be helpful"
    end
  end

  describe "last_entry/1" do
    test "returns nil for empty thread" do
      assert Thread.last_entry(Thread.new()) == nil
    end

    test "returns last entry" do
      thread =
        Thread.new()
        |> Thread.append_user("First")
        |> Thread.append_assistant("Second")

      entry = Thread.last_entry(thread)
      assert entry.role == :assistant
      assert entry.content == "Second"
    end
  end

  describe "last_assistant_content/1" do
    test "returns nil for empty thread" do
      assert Thread.last_assistant_content(Thread.new()) == nil
    end

    test "returns nil when no assistant messages" do
      thread = Thread.new() |> Thread.append_user("Hello")
      assert Thread.last_assistant_content(thread) == nil
    end

    test "returns last assistant content" do
      thread =
        Thread.new()
        |> Thread.append_user("Hello")
        |> Thread.append_assistant("First reply")
        |> Thread.append_user("Another question")
        |> Thread.append_assistant("Second reply")

      assert Thread.last_assistant_content(thread) == "Second reply"
    end
  end

  describe "append_messages/2" do
    test "imports list of message maps" do
      messages = [
        %{role: :user, content: "Hello"},
        %{role: :assistant, content: "Hi!"}
      ]

      thread = Thread.new() |> Thread.append_messages(messages)

      assert Thread.length(thread) == 2
      # Entries are stored in reverse order internally
      [second, first] = thread.entries
      assert first.role == :user
      assert first.content == "Hello"
      assert second.role == :assistant
      assert second.content == "Hi!"
    end

    test "handles string role names" do
      messages = [
        %{role: "user", content: "Hello"},
        %{role: "assistant", content: "Hi!"}
      ]

      thread = Thread.new() |> Thread.append_messages(messages)

      # Entries are stored in reverse order internally
      [second, first] = thread.entries
      assert first.role == :user
      assert second.role == :assistant
    end

    test "handles string-keyed maps from JSON" do
      messages = [
        %{"role" => "user", "content" => "Hello from JSON"},
        %{"role" => "assistant", "content" => "Hi!", "tool_calls" => [%{"id" => "tc_1", "name" => "calc"}]},
        %{"role" => "tool", "tool_call_id" => "tc_1", "name" => "calc", "content" => "42"}
      ]

      thread = Thread.new() |> Thread.append_messages(messages)

      assert Thread.length(thread) == 3
      # Entries are stored in reverse order internally
      [tool, assistant, user] = thread.entries
      assert user.role == :user
      assert user.content == "Hello from JSON"
      assert assistant.role == :assistant
      assert assistant.tool_calls == [%{"id" => "tc_1", "name" => "calc"}]
      assert tool.role == :tool
      assert tool.tool_call_id == "tc_1"
      assert tool.name == "calc"
    end

    test "handles known extended roles (developer, function)" do
      messages = [
        %{role: "developer", content: "Some developer message"},
        %{role: :function, content: "Some function result"}
      ]

      thread = Thread.new() |> Thread.append_messages(messages)

      assert Thread.length(thread) == 2
      # Entries are stored in reverse order internally
      [second, first] = thread.entries
      assert first.role == :developer
      assert second.role == :function
    end

    test "passes through unknown roles as-is" do
      messages = [
        %{role: "custom_role", content: "Custom message"},
        %{role: :other_role, content: "Other message"}
      ]

      thread = Thread.new() |> Thread.append_messages(messages)

      # Entries are stored in reverse order internally
      [second, first] = thread.entries
      # String roles stay as strings, atom roles stay as atoms
      assert first.role == "custom_role"
      assert second.role == :other_role
    end

    test "preserves tool_calls and tool_call_id" do
      messages = [
        %{role: :assistant, content: "", tool_calls: [%{id: "tc_1", name: "calc"}]},
        %{role: :tool, tool_call_id: "tc_1", name: "calc", content: "42"}
      ]

      thread = Thread.new() |> Thread.append_messages(messages)

      # Entries are stored in reverse order internally
      [tool, assistant] = thread.entries
      assert assistant.tool_calls == [%{id: "tc_1", name: "calc"}]
      assert tool.tool_call_id == "tc_1"
      assert tool.name == "calc"
    end
  end

  # ============================================================================
  # Round-trip Tests
  # ============================================================================

  describe "round-trip" do
    test "conversation survives to_messages -> append_messages" do
      original =
        Thread.new(system_prompt: "System prompt")
        |> Thread.append_user("Hello")
        |> Thread.append_assistant("Hi there!")

      # Project to messages (excluding system since it's in thread.system_prompt)
      # Entries are stored in reverse order, so reverse to get chronological
      messages =
        original.entries
        |> Enum.reverse()
        |> Enum.map(fn entry ->
          case entry do
            %{role: :user, content: c} -> %{role: :user, content: c}
            %{role: :assistant, content: c} -> %{role: :assistant, content: c}
          end
        end)

      # Rebuild
      rebuilt =
        Thread.new(system_prompt: "System prompt")
        |> Thread.append_messages(messages)

      # Compare
      assert Thread.length(rebuilt) == Thread.length(original)
      assert Thread.to_messages(rebuilt) == Thread.to_messages(original)
    end
  end
end
