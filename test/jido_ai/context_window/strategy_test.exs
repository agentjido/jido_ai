defmodule Jido.AI.ContextWindow.StrategyTest do
  use ExUnit.Case, async: true

  alias Jido.AI.{Model, Prompt}
  alias Jido.AI.ContextWindow.Strategy

  setup do
    model = %Model{
      provider: :openai,
      model: "gpt-4",
      endpoints: [%{context_length: 8192, max_completion_tokens: 2048}]
    }

    messages =
      [%Prompt.MessageItem{role: :system, content: "You are a helpful assistant"}] ++
        for i <- 1..20 do
          %Prompt.MessageItem{role: :user, content: "Message number #{i} with some content here"}
        end

    prompt = %Prompt{messages: messages}

    {:ok, model: model, prompt: prompt, messages: messages}
  end

  describe "keep_recent/4" do
    test "keeps N most recent messages", %{prompt: prompt, model: model} do
      {:ok, result} = Strategy.keep_recent(prompt, model, 5000, count: 5)

      assert length(result.messages) == 5
      # Should keep last 5 messages
      assert Enum.at(result.messages, -1).content =~ "Message number 20"
      assert Enum.at(result.messages, -5).content =~ "Message number 16"
    end

    test "calculates count automatically when not provided", %{prompt: prompt, model: model} do
      {:ok, result} = Strategy.keep_recent(prompt, model, 150)

      assert length(result.messages) > 0
      assert length(result.messages) < length(prompt.messages)
    end

    test "keeps all messages if count exceeds total", %{prompt: prompt, model: model} do
      {:ok, result} = Strategy.keep_recent(prompt, model, 10_000, count: 100)

      assert length(result.messages) == length(prompt.messages)
    end
  end

  describe "keep_bookends/4" do
    test "preserves system message and recent messages", %{prompt: prompt, model: model} do
      {:ok, result} = Strategy.keep_bookends(prompt, model, 5000, count: 5)

      # Should have system message + 5 recent
      assert length(result.messages) == 6
      assert Enum.at(result.messages, 0).role == :system
      assert Enum.at(result.messages, -1).content =~ "Message number 20"
    end

    test "handles prompts without system message" do
      messages =
        for i <- 1..10 do
          %Prompt.MessageItem{role: :user, content: "Message #{i}"}
        end

      prompt = %Prompt{messages: messages}
      model = %Model{provider: :openai, model: "gpt-4", endpoints: []}

      {:ok, result} = Strategy.keep_bookends(prompt, model, 500, count: 3)

      # No system message, just recent messages
      assert length(result.messages) == 3
    end

    test "calculates count based on available space after system", %{prompt: prompt, model: model} do
      {:ok, result} = Strategy.keep_bookends(prompt, model, 300)

      # System message + as many as fit
      assert Enum.at(result.messages, 0).role == :system
      assert length(result.messages) > 1
    end
  end

  describe "sliding_window/4" do
    test "applies sliding window with overlap", %{prompt: prompt, model: model} do
      {:ok, result} = Strategy.sliding_window(prompt, model, 5000, count: 10, overlap: 2)

      assert length(result.messages) == 10
      # Should take last 10 messages (simulating window slide)
      assert Enum.at(result.messages, -1).content =~ "Message number 20"
    end

    test "returns all messages if they fit", %{model: model} do
      small_messages =
        for i <- 1..3 do
          %Prompt.MessageItem{role: :user, content: "Msg #{i}"}
        end

      prompt = %Prompt{messages: small_messages}

      {:ok, result} = Strategy.sliding_window(prompt, model, 5000, count: 10)

      assert length(result.messages) == 3
    end

    test "returns error if overlap >= count", %{prompt: prompt, model: model} do
      assert {:error, :invalid_overlap} =
               Strategy.sliding_window(prompt, model, 500, count: 5, overlap: 5)

      assert {:error, :invalid_overlap} =
               Strategy.sliding_window(prompt, model, 500, count: 5, overlap: 6)
    end

    test "defaults overlap to 2", %{prompt: prompt, model: model} do
      {:ok, result} = Strategy.sliding_window(prompt, model, 5000, count: 8)

      assert length(result.messages) == 8
    end
  end

  describe "smart_truncate/4" do
    test "preserves system, first user, and recent messages", %{prompt: prompt, model: model} do
      {:ok, result} = Strategy.smart_truncate(prompt, model, 5000, count: 5)

      # System + first user + recent
      assert Enum.at(result.messages, 0).role == :system
      # Check we have some recent messages
      assert Enum.at(result.messages, -1).content =~ "Message number"
    end

    test "preserves first user message by default" do
      messages =
        [%Prompt.MessageItem{role: :system, content: "Instructions"}] ++
          [%Prompt.MessageItem{role: :user, content: "Task description"}] ++
          for i <- 2..20 do
            %Prompt.MessageItem{role: :user, content: "Message #{i}"}
          end

      prompt = %Prompt{messages: messages}
      model = %Model{provider: :openai, model: "gpt-4", endpoints: []}

      {:ok, result} = Strategy.smart_truncate(prompt, model, 500, count: 5)

      # Should have: system + task description + some recent
      assert Enum.at(result.messages, 0).role == :system
      assert Enum.at(result.messages, 1).content == "Task description"
    end

    test "can disable first user preservation" do
      messages =
        [%Prompt.MessageItem{role: :system, content: "Instructions"}] ++
          for i <- 1..20 do
            %Prompt.MessageItem{role: :user, content: "Message #{i}"}
          end

      prompt = %Prompt{messages: messages}
      model = %Model{provider: :openai, model: "gpt-4", endpoints: []}

      {:ok, result} =
        Strategy.smart_truncate(prompt, model, 500, count: 3, preserve_first: false)

      # System + recent (no guaranteed first user)
      assert Enum.at(result.messages, 0).role == :system
      # Should have recent messages
      assert length(result.messages) > 1
    end

    test "handles prompts without system message" do
      messages =
        for i <- 1..15 do
          %Prompt.MessageItem{role: :user, content: "Message #{i}"}
        end

      prompt = %Prompt{messages: messages}
      model = %Model{provider: :openai, model: "gpt-4", endpoints: []}

      {:ok, result} = Strategy.smart_truncate(prompt, model, 500)

      # First user + recent
      assert Enum.at(result.messages, 0).content == "Message 1"
      assert length(result.messages) > 1
    end

    test "calculates count automatically", %{prompt: prompt, model: model} do
      {:ok, result} = Strategy.smart_truncate(prompt, model, 200)

      # System + first user + calculated recent
      assert Enum.at(result.messages, 0).role == :system
      assert length(result.messages) > 2
      assert length(result.messages) < length(prompt.messages)
    end
  end

  describe "apply/5" do
    test "dispatches to correct strategy", %{prompt: prompt, model: model} do
      {:ok, recent} = Strategy.apply(prompt, model, 500, :keep_recent, count: 3)
      assert length(recent.messages) == 3

      {:ok, bookends} = Strategy.apply(prompt, model, 500, :keep_bookends, count: 3)
      assert Enum.at(bookends.messages, 0).role == :system

      {:ok, sliding} = Strategy.apply(prompt, model, 500, :sliding_window, count: 5)
      assert length(sliding.messages) <= 5

      {:ok, smart} = Strategy.apply(prompt, model, 500, :smart_truncate, count: 5)
      assert Enum.at(smart.messages, 0).role == :system
    end

    test "returns error for unknown strategy", %{prompt: prompt, model: model} do
      assert {:error, {:unknown_strategy, :invalid}} =
               Strategy.apply(prompt, model, 500, :invalid, [])
    end
  end
end
