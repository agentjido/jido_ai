defmodule JidoTest.AI.PromptStructTest do
  use ExUnit.Case, async: true
  @moduletag :capture_log

  alias Jido.AI.Prompt

  describe "new/1" do
    test "creates a new prompt struct with default values" do
      prompt = Prompt.new(%{
        messages: [
          %{role: :user, content: "Hello"}
        ]
      })

      assert %Prompt{} = prompt
      assert length(prompt.messages) == 1
      assert hd(prompt.messages).role == :user
      assert hd(prompt.messages).content == "Hello"
      assert prompt.params == %{}
      assert prompt.metadata == %{}
      assert is_binary(prompt.id)
      assert prompt.version == 1
      assert prompt.history == []
    end

    test "creates a prompt with multiple messages" do
      prompt = Prompt.new(%{
        messages: [
          %{role: :system, content: "You are an assistant"},
          %{role: :user, content: "Hello"},
          %{role: :assistant, content: "Hi there!"}
        ]
      })

      assert length(prompt.messages) == 3
      [system, user, assistant] = prompt.messages
      assert system.role == :system
      assert user.role == :user
      assert assistant.role == :assistant
    end

    test "creates a prompt with parameters" do
      prompt = Prompt.new(%{
        messages: [
          %{role: :user, content: "Hello <%= @name %>", engine: :eex}
        ],
        params: %{name: "Alice"}
      })

      assert prompt.params == %{name: "Alice"}
      assert hd(prompt.messages).engine == :eex
    end
  end

  describe "render/2" do
    test "renders a simple prompt without templates" do
      prompt = Prompt.new(%{
        messages: [
          %{role: :user, content: "Hello"}
        ]
      })

      result = Prompt.render(prompt)
      assert result == [%{role: :user, content: "Hello"}]
    end

    test "renders a prompt with EEx templates" do
      prompt = Prompt.new(%{
        messages: [
          %{role: :user, content: "Hello <%= @name %>", engine: :eex}
        ],
        params: %{name: "Alice"}
      })

      result = Prompt.render(prompt)
      assert result == [%{role: :user, content: "Hello Alice"}]
    end

    test "renders a prompt with override parameters" do
      prompt = Prompt.new(%{
        messages: [
          %{role: :user, content: "Hello <%= @name %>", engine: :eex}
        ],
        params: %{name: "Alice"}
      })

      result = Prompt.render(prompt, %{name: "Bob"})
      assert result == [%{role: :user, content: "Hello Bob"}]
    end

    test "renders a prompt with multiple messages and templates" do
      prompt = Prompt.new(%{
        messages: [
          %{role: :system, content: "You are an <%= @assistant_type %>", engine: :eex},
          %{role: :user, content: "Hello <%= @name %>", engine: :eex},
          %{role: :assistant, content: "Hi there!"}
        ],
        params: %{assistant_type: "helpful assistant", name: "Alice"}
      })

      result = Prompt.render(prompt)
      assert length(result) == 3
      [system, user, assistant] = result
      assert system.content == "You are an helpful assistant"
      assert user.content == "Hello Alice"
      assert assistant.content == "Hi there!"
    end
  end

  describe "to_text/2" do
    test "converts a prompt to a single text string" do
      prompt = Prompt.new(%{
        messages: [
          %{role: :system, content: "You are an assistant"},
          %{role: :user, content: "Hello"},
          %{role: :assistant, content: "Hi there!"}
        ]
      })

      result = Prompt.to_text(prompt)
      assert result == "[system] You are an assistant\n[user] Hello\n[assistant] Hi there!"
    end
  end

  describe "add_message/3" do
    test "adds a message to the prompt" do
      prompt = Prompt.new(%{
        messages: [
          %{role: :user, content: "Hello"}
        ]
      })

      updated = Prompt.add_message(prompt, :assistant, "Hi there!")
      assert length(updated.messages) == 2
      assert List.last(updated.messages).role == :assistant
      assert List.last(updated.messages).content == "Hi there!"
    end

    test "adds a templated message to the prompt" do
      prompt = Prompt.new(%{
        messages: [
          %{role: :user, content: "Hello"}
        ]
      })

      updated = Prompt.add_message(prompt, :assistant, "Hi <%= @name %>!", engine: :eex)
      assert length(updated.messages) == 2
      assert List.last(updated.messages).role == :assistant
      assert List.last(updated.messages).content == "Hi <%= @name %>!"
      assert List.last(updated.messages).engine == :eex
    end
  end
end
