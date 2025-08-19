defmodule Jido.AI.TokenCounterTest do
  use ExUnit.Case, async: true

  alias Jido.AI.{Message, TokenCounter}

  describe "count_tokens/1" do
    test "counts tokens for simple text" do
      assert TokenCounter.count_tokens("Hello world") == 2
    end

    test "counts tokens for longer text" do
      text = "This is a longer piece of text that should have more tokens"
      assert TokenCounter.count_tokens(text) > 10
    end

    test "returns 0 for empty string" do
      assert TokenCounter.count_tokens("") == 0
    end

    test "returns 0 for nil" do
      assert TokenCounter.count_tokens(nil) == 0
    end

    test "returns minimum 1 token for non-empty strings" do
      assert TokenCounter.count_tokens("hi") == 1
    end
  end

  describe "count_message_tokens/1" do
    test "counts tokens in map messages" do
      messages = [
        %{content: "Hello"},
        %{content: "How are you?"}
      ]

      # Should be content tokens + 4 overhead per message
      assert TokenCounter.count_message_tokens(messages) == 1 + 4 + 3 + 4
    end

    test "counts tokens in Message structs" do
      messages = [
        %Message{role: :user, content: "Hello world"},
        %Message{role: :assistant, content: "Hi there!"}
      ]

      # Should be content tokens + 4 overhead per message  
      assert TokenCounter.count_message_tokens(messages) == 2 + 4 + 2 + 4
    end

    test "returns 0 for empty list" do
      assert TokenCounter.count_message_tokens([]) == 0
    end

    test "returns 0 for invalid input" do
      assert TokenCounter.count_message_tokens(nil) == 0
    end
  end

  describe "count_request_tokens/1" do
    test "counts tokens in chat completion request" do
      request = %{
        "model" => "gpt-4",
        "messages" => [
          %{"role" => "system", "content" => "You are a helpful assistant"},
          %{"role" => "user", "content" => "Hello world"}
        ]
      }

      # Should include message tokens + base overhead
      tokens = TokenCounter.count_request_tokens(request)
      # at least the content + overhead
      assert tokens > 15
    end

    test "returns 0 for invalid request" do
      assert TokenCounter.count_request_tokens(%{}) == 0
    end
  end

  describe "count_response_tokens/1" do
    test "counts tokens in chat completion response" do
      response = %{
        "choices" => [
          %{"message" => %{"content" => "Hello there, how can I help you today?"}}
        ]
      }

      tokens = TokenCounter.count_response_tokens(response)
      assert tokens > 5
    end

    test "handles multiple choices" do
      response = %{
        "choices" => [
          %{"message" => %{"content" => "Response one"}},
          %{"message" => %{"content" => "Response two"}}
        ]
      }

      tokens = TokenCounter.count_response_tokens(response)
      assert tokens > 4
    end

    test "returns 0 for invalid response" do
      assert TokenCounter.count_response_tokens(%{}) == 0
    end
  end

  describe "count_stream_tokens/1" do
    test "counts tokens in stream content" do
      assert TokenCounter.count_stream_tokens("Hello") == 1
      assert TokenCounter.count_stream_tokens("Hello world") == 2
    end

    test "returns 0 for empty content" do
      assert TokenCounter.count_stream_tokens("") == 0
    end

    test "returns 0 for invalid input" do
      assert TokenCounter.count_stream_tokens(nil) == 0
    end
  end
end
