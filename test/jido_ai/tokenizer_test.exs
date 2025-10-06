defmodule Jido.AI.TokenizerTest do
  use ExUnit.Case, async: true

  alias Jido.AI.{Prompt, Tokenizer}

  describe "count_tokens/2" do
    test "counts tokens with default provider" do
      text = "Hello, world! This is a test."
      tokens = Tokenizer.count_tokens(text)

      assert tokens > 0
      assert is_integer(tokens)
    end

    test "uses provider-specific ratios" do
      # Use text that will produce different results across providers
      text = "The quick brown fox jumps over the lazy dog multiple times today"

      # OpenAI uses 0.75 ratio
      openai_tokens = Tokenizer.count_tokens(text, :openai)

      # Anthropic uses 0.8 ratio (slightly more tokens)
      anthropic_tokens = Tokenizer.count_tokens(text, :anthropic)

      # Google uses 0.6 ratio (fewer tokens)
      google_tokens = Tokenizer.count_tokens(text, :google)

      # Verify different providers give different counts
      assert google_tokens < openai_tokens
      assert openai_tokens < anthropic_tokens
    end

    test "handles punctuation correctly" do
      text = "Hello, world! How are you? I'm fine."
      tokens = Tokenizer.count_tokens(text, :openai)

      # Should split on punctuation boundaries
      assert tokens > 5
    end

    test "handles empty string" do
      assert Tokenizer.count_tokens("", :openai) == 0
    end

    test "handles single word" do
      tokens = Tokenizer.count_tokens("Hello", :openai)
      assert tokens >= 1
    end

    test "uses default ratio for unknown provider" do
      text = "Test message"
      default_tokens = Tokenizer.count_tokens(text, :default)
      unknown_tokens = Tokenizer.count_tokens(text, :unknown_provider)

      assert default_tokens == unknown_tokens
    end
  end

  describe "count_message/2" do
    test "counts tokens in message with overhead" do
      message = %{role: :user, content: "Hello, world!"}
      tokens = Tokenizer.count_message(message, :openai)

      # Content tokens + 4 overhead
      content_tokens = Tokenizer.count_tokens("Hello, world!", :openai)
      assert tokens == content_tokens + 4
    end

    test "handles multimodal content (list)" do
      message = %{
        role: :user,
        content: [
          "Text part one",
          "Text part two"
        ]
      }

      tokens = Tokenizer.count_message(message, :openai)

      # Should count text parts + multimodal overhead
      assert tokens > 0
    end

    test "includes message structure overhead" do
      short_message = %{role: :user, content: "Hi"}
      tokens = Tokenizer.count_message(short_message, :openai)

      # Even short message has minimum overhead
      assert tokens >= 4
    end
  end

  describe "count_messages/2" do
    test "counts tokens in multiple messages" do
      messages = [
        %{role: :system, content: "You are a helpful assistant"},
        %{role: :user, content: "Hello!"},
        %{role: :assistant, content: "Hi there! How can I help?"}
      ]

      tokens = Tokenizer.count_messages(messages, :openai)

      assert tokens > 0

      # Should be sum of individual messages
      individual_sum =
        messages
        |> Enum.map(&Tokenizer.count_message(&1, :openai))
        |> Enum.sum()

      assert tokens == individual_sum
    end

    test "handles empty message list" do
      assert Tokenizer.count_messages([], :openai) == 0
    end

    test "handles single message" do
      messages = [%{role: :user, content: "Test"}]
      tokens = Tokenizer.count_messages(messages, :openai)

      assert tokens > 0
    end
  end

  describe "count_prompt/2" do
    test "counts tokens in Prompt struct" do
      prompt =
        Prompt.new(:user, "Hello, how are you?")

      tokens = Tokenizer.count_prompt(prompt, :openai)

      assert tokens > 0
      assert is_integer(tokens)
    end

    test "counts all messages in prompt" do
      prompt =
        Prompt.new(%{
          messages: [
            %{role: :system, content: "You are helpful"},
            %{role: :user, content: "Hello!"}
          ]
        })

      tokens = Tokenizer.count_prompt(prompt, :openai)

      # Should count both messages
      assert tokens > Tokenizer.count_tokens("Hello!", :openai)
    end

    test "uses specified provider for counting" do
      prompt = Prompt.new(:user, "Test message for counting tokens with different providers")

      openai_tokens = Tokenizer.count_prompt(prompt, :openai)
      google_tokens = Tokenizer.count_prompt(prompt, :google)

      # Different providers should give different counts
      assert openai_tokens != google_tokens
    end
  end

  describe "get_ratio/1" do
    test "returns correct ratios for known providers" do
      assert Tokenizer.get_ratio(:openai) == 0.75
      assert Tokenizer.get_ratio(:anthropic) == 0.8
      assert Tokenizer.get_ratio(:google) == 0.6
      assert Tokenizer.get_ratio(:groq) == 0.75
      assert Tokenizer.get_ratio(:together) == 0.75
      assert Tokenizer.get_ratio(:openrouter) == 0.75
      assert Tokenizer.get_ratio(:ollama) == 0.75
      assert Tokenizer.get_ratio(:llamacpp) == 0.75
    end

    test "returns default ratio for unknown provider" do
      assert Tokenizer.get_ratio(:unknown) == 0.75
      assert Tokenizer.get_ratio(:default) == 0.75
    end
  end

  describe "legacy encode/decode" do
    test "encode splits on spaces (backward compatibility)" do
      result = Tokenizer.encode("hello world test", "any-model")
      assert result == ["hello", "world", "test"]
    end

    test "decode joins with spaces (backward compatibility)" do
      result = Tokenizer.decode(["hello", "world"], "any-model")
      assert result == "hello world"
    end

    test "encode/decode round trip" do
      original = "hello world test"
      encoded = Tokenizer.encode(original, "model")
      decoded = Tokenizer.decode(encoded, "model")

      assert decoded == original
    end
  end

  describe "token estimation accuracy" do
    test "estimates are reasonable for typical messages" do
      # Typical message lengths
      short = "Hi there!"
      medium = "Hello, how are you doing today? I hope everything is going well."
      long = String.duplicate("This is a longer message with more content. ", 20)

      short_tokens = Tokenizer.count_tokens(short, :openai)
      medium_tokens = Tokenizer.count_tokens(medium, :openai)
      long_tokens = Tokenizer.count_tokens(long, :openai)

      # Short should be ~2-5 tokens
      assert short_tokens in 2..10

      # Medium should be more than short
      assert medium_tokens > short_tokens

      # Long should be significantly more
      assert long_tokens > medium_tokens * 5
    end

    test "estimation scales linearly with content" do
      base_text = "This is a test message. "

      tokens_1x = Tokenizer.count_tokens(base_text, :openai)
      tokens_2x = Tokenizer.count_tokens(String.duplicate(base_text, 2), :openai)
      tokens_4x = Tokenizer.count_tokens(String.duplicate(base_text, 4), :openai)

      # Should scale approximately linearly (allowing for some rounding)
      assert tokens_2x >= tokens_1x * 2 - 2
      assert tokens_2x <= tokens_1x * 2 + 2

      assert tokens_4x >= tokens_1x * 4 - 4
      assert tokens_4x <= tokens_1x * 4 + 4
    end
  end
end
