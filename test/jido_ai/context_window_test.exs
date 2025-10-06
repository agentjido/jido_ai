defmodule Jido.AI.ContextWindowTest do
  use ExUnit.Case, async: true

  alias Jido.AI.{ContextWindow, Model, Prompt, Tokenizer}
  alias Jido.AI.ContextWindow.{Limits, ContextExceededError}

  describe "get_limits/1" do
    test "extracts limits from model with endpoint" do
      model = %Model{
        provider: :openai,
        model: "gpt-4-turbo",
        endpoints: [
          %{
            context_length: 128_000,
            max_completion_tokens: 4096,
            max_prompt_tokens: nil
          }
        ]
      }

      assert {:ok, %Limits{} = limits} = ContextWindow.get_limits(model)
      assert limits.total == 128_000
      assert limits.completion == 4096
      assert limits.prompt == 123_904
    end

    test "calculates prompt limit when not specified" do
      model = %Model{
        provider: :openai,
        model: "gpt-4",
        endpoints: [
          %{
            context_length: 8192,
            max_completion_tokens: nil,
            max_prompt_tokens: nil
          }
        ]
      }

      assert {:ok, %Limits{} = limits} = ContextWindow.get_limits(model)
      assert limits.total == 8192
      # 75% of total reserved for prompt
      assert limits.prompt == 6144
    end

    test "uses safe defaults when no endpoints" do
      model = %Model{provider: :openai, model: "unknown", endpoints: []}

      assert {:ok, %Limits{} = limits} = ContextWindow.get_limits(model)
      assert limits.total == 4096
      assert limits.completion == 1000
      assert limits.prompt == 3096
    end
  end

  describe "count_tokens/2" do
    test "counts tokens in a Prompt struct" do
      prompt =
        Prompt.new(:user, "Hello, how are you today?")

      model = %Model{provider: :openai, model: "gpt-4"}

      tokens = ContextWindow.count_tokens(prompt, model)
      assert tokens > 0
      assert is_integer(tokens)
    end

    test "counts tokens in message list" do
      messages = [
        %{role: :system, content: "You are a helpful assistant"},
        %{role: :user, content: "Hello!"}
      ]

      model = %Model{provider: :openai, model: "gpt-4"}

      tokens = ContextWindow.count_tokens(messages, model)
      assert tokens > 0
    end

    test "uses provider-specific estimation" do
      text = "Hello, world! This is a test."
      prompt = Prompt.new(:user, text)

      openai_model = %Model{provider: :openai, model: "gpt-4"}
      google_model = %Model{provider: :google, model: "gemini-pro"}

      openai_tokens = ContextWindow.count_tokens(prompt, openai_model)
      google_tokens = ContextWindow.count_tokens(prompt, google_model)

      # Google uses lower ratio (0.6 vs 0.75)
      assert google_tokens < openai_tokens
    end
  end

  describe "check_fit/3" do
    test "returns fit status when prompt fits" do
      prompt = Prompt.new(:user, "Short message")

      model = %Model{
        provider: :openai,
        model: "gpt-4",
        endpoints: [%{context_length: 8192, max_completion_tokens: 2048}]
      }

      assert {:ok, info} = ContextWindow.check_fit(prompt, model)
      assert info.fits == true
      assert info.tokens > 0
      assert info.limit > 0
      assert info.available > 0
    end

    test "returns not fit when prompt exceeds limit" do
      # Create a large prompt
      long_text = String.duplicate("word ", 10_000)
      prompt = Prompt.new(:user, long_text)

      model = %Model{
        provider: :openai,
        model: "gpt-3.5",
        endpoints: [%{context_length: 4096, max_completion_tokens: 1000}]
      }

      assert {:ok, info} = ContextWindow.check_fit(prompt, model)
      assert info.fits == false
      assert info.tokens > info.limit
      assert info.available == 0
    end

    test "respects reserve_completion option" do
      prompt = Prompt.new(:user, "Hello")

      model = %Model{
        provider: :openai,
        model: "gpt-4",
        endpoints: [%{context_length: 1000, max_completion_tokens: 100}]
      }

      {:ok, info_default} = ContextWindow.check_fit(prompt, model)
      {:ok, info_reserved} = ContextWindow.check_fit(prompt, model, reserve_completion: 500)

      # Reserved completion reduces available limit
      assert info_reserved.limit < info_default.limit
    end
  end

  describe "ensure_fit/3" do
    test "returns original prompt when it fits" do
      prompt = Prompt.new(:user, "Short message")

      model = %Model{
        provider: :openai,
        model: "gpt-4",
        endpoints: [%{context_length: 8192, max_completion_tokens: 2048}]
      }

      assert {:ok, result} = ContextWindow.ensure_fit(prompt, model)
      assert result == prompt
    end

    test "truncates prompt when it doesn't fit" do
      # Create prompt with many messages that will exceed small context
      messages =
        for i <- 1..50 do
          %Prompt.MessageItem{role: :user, content: "Message number #{i} with some additional content here"}
        end

      prompt = %Prompt{messages: messages}

      model = %Model{
        provider: :openai,
        model: "gpt-3.5",
        endpoints: [%{context_length: 200, max_completion_tokens: 50}]
      }

      assert {:ok, truncated} = ContextWindow.ensure_fit(prompt, model, strategy: :keep_recent)
      assert length(truncated.messages) < length(messages)
    end

    test "supports different truncation strategies" do
      messages =
        [%Prompt.MessageItem{role: :system, content: "You are helpful"}] ++
          for i <- 1..30 do
            %Prompt.MessageItem{role: :user, content: "Message #{i}"}
          end

      prompt = %Prompt{messages: messages}

      model = %Model{
        provider: :openai,
        model: "gpt-3.5",
        endpoints: [%{context_length: 300, max_completion_tokens: 50}]
      }

      # keep_recent strategy
      {:ok, recent} = ContextWindow.ensure_fit(prompt, model, strategy: :keep_recent, count: 5)
      assert length(recent.messages) == 5

      # keep_bookends strategy preserves system message
      {:ok, bookends} = ContextWindow.ensure_fit(prompt, model, strategy: :keep_bookends, count: 5)
      assert Enum.at(bookends.messages, 0).role == :system
    end
  end

  describe "ensure_fit!/3" do
    test "returns prompt when it fits" do
      prompt = Prompt.new(:user, "Short message")

      model = %Model{
        provider: :openai,
        model: "gpt-4",
        endpoints: [%{context_length: 8192, max_completion_tokens: 2048}]
      }

      result = ContextWindow.ensure_fit!(prompt, model)
      assert result == prompt
    end

    test "raises ContextExceededError when cannot fit" do
      # Even a single message with this much text won't fit in tiny context
      long_text = String.duplicate("word ", 1_000)
      prompt = Prompt.new(:system, long_text)

      model = %Model{
        provider: :openai,
        model: "gpt-3.5",
        endpoints: [%{context_length: 50, max_completion_tokens: 10}]
      }

      # With count: 1, we can truncate to 1 message, but that message alone exceeds the limit
      # This should raise because even after truncation to 1 message, it still doesn't fit
      assert_raise ContextExceededError, fn ->
        ContextWindow.ensure_fit!(prompt, model, strategy: :keep_recent, count: 1)
      end
    end
  end

  describe "extended_context?/1" do
    test "returns true for models with 100K+ context" do
      model = %Model{
        provider: :openai,
        model: "gpt-4-turbo",
        endpoints: [%{context_length: 128_000, max_completion_tokens: 4096}]
      }

      assert ContextWindow.extended_context?(model) == true
    end

    test "returns false for models with < 100K context" do
      model = %Model{
        provider: :openai,
        model: "gpt-3.5",
        endpoints: [%{context_length: 4096, max_completion_tokens: 1000}]
      }

      assert ContextWindow.extended_context?(model) == false
    end

    test "returns false when context length unknown" do
      model = %Model{provider: :openai, model: "unknown", endpoints: []}

      assert ContextWindow.extended_context?(model) == false
    end
  end

  describe "utilization/2" do
    test "calculates context window utilization percentage" do
      prompt = Prompt.new(:user, "Hello world")

      model = %Model{
        provider: :openai,
        model: "gpt-4",
        endpoints: [%{context_length: 1000, max_completion_tokens: 200}]
      }

      assert {:ok, percentage} = ContextWindow.utilization(prompt, model)
      assert percentage >= 0.0
      assert percentage < 100.0
      assert is_float(percentage)
    end

    test "can return over 100% when prompt exceeds context" do
      long_text = String.duplicate("word ", 10_000)
      prompt = Prompt.new(:user, long_text)

      model = %Model{
        provider: :openai,
        model: "gpt-3.5",
        endpoints: [%{context_length: 100, max_completion_tokens: 20}]
      }

      assert {:ok, percentage} = ContextWindow.utilization(prompt, model)
      assert percentage > 100.0
    end
  end

  describe "truncate/5" do
    test "delegates to Strategy module" do
      messages =
        for i <- 1..10 do
          %Prompt.MessageItem{role: :user, content: "Message #{i}"}
        end

      prompt = %Prompt{messages: messages}

      model = %Model{
        provider: :openai,
        model: "gpt-4",
        endpoints: [%{context_length: 8192, max_completion_tokens: 2048}]
      }

      assert {:ok, result} =
               ContextWindow.truncate(prompt, model, 100, :keep_recent, count: 3)

      assert length(result.messages) == 3
    end

    test "returns error for unknown strategy" do
      prompt = Prompt.new(:user, "Test")
      model = %Model{provider: :openai, model: "gpt-4", endpoints: []}

      assert {:error, {:unknown_strategy, :invalid}} =
               ContextWindow.truncate(prompt, model, 1000, :invalid, [])
    end
  end
end
