defmodule JidoTest.AI.Prompt.MessageItemTest do
  use ExUnit.Case, async: true
  @moduletag :capture_log

  alias Jido.AI.Prompt.MessageItem

  describe "new/1" do
    test "creates a new message item with default values" do
      message = MessageItem.new(%{})

      assert %MessageItem{} = message
      assert message.role == :user
      assert message.content == ""
      assert message.engine == :none
    end

    test "creates a message item with specified values" do
      message = MessageItem.new(%{
        role: :system,
        content: "You are an assistant",
        engine: :eex
      })

      assert message.role == :system
      assert message.content == "You are an assistant"
      assert message.engine == :eex
    end

    test "creates a message item with partial values" do
      message = MessageItem.new(%{role: :assistant})

      assert message.role == :assistant
      assert message.content == ""
      assert message.engine == :none
    end
  end

  describe "from_map/1" do
    test "creates a message item from a map with string keys" do
      message = MessageItem.from_map(%{
        "role" => "user",
        "content" => "Hello"
      })

      assert message.role == :user
      assert message.content == "Hello"
      assert message.engine == :none
    end

    test "creates a message item with engine specified" do
      message = MessageItem.from_map(%{
        "role" => "system",
        "content" => "You are an <%= @assistant_type %>",
        "engine" => :eex
      })

      assert message.role == :system
      assert message.content == "You are an <%= @assistant_type %>"
      assert message.engine == :eex
    end

    test "handles different role types" do
      message = MessageItem.from_map(%{
        "role" => "assistant",
        "content" => "I can help with that"
      })

      assert message.role == :assistant
      assert message.content == "I can help with that"
    end

    test "handles function role" do
      message = MessageItem.from_map(%{
        "role" => "function",
        "content" => "Result of calculation",
        "name" => "calculator"
      })

      assert message.role == :function
      assert message.content == "Result of calculation"
    end
  end
end
