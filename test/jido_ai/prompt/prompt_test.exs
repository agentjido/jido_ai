defmodule JidoTest.AI.PromptTest do
  use ExUnit.Case, async: true
  doctest Jido.AI.Prompt
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

  describe "new/3" do
    test "creates a new prompt with a single message" do
      prompt = Prompt.new(:user, "Hello")

      assert %Prompt{} = prompt
      assert length(prompt.messages) == 1
      assert hd(prompt.messages).role == :user
      assert hd(prompt.messages).content == "Hello"
      assert hd(prompt.messages).engine == :none
    end

    test "creates a new prompt with a templated message" do
      prompt = Prompt.new(:user, "Hello <%= @name %>", engine: :eex, params: %{name: "Alice"})

      assert %Prompt{} = prompt
      assert length(prompt.messages) == 1
      assert hd(prompt.messages).role == :user
      assert hd(prompt.messages).content == "Hello <%= @name %>"
      assert hd(prompt.messages).engine == :eex
      assert prompt.params == %{name: "Alice"}
    end

    test "creates a new prompt with metadata and id" do
      prompt = Prompt.new(:system, "You are an assistant",
        metadata: %{version: "1.0"},
        id: "system_prompt"
      )

      assert %Prompt{} = prompt
      assert prompt.metadata == %{version: "1.0"}
      assert prompt.id == "system_prompt"
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

    test "converts a prompt with templates to a single text string" do
      prompt = Prompt.new(%{
        messages: [
          %{role: :system, content: "You are an <%= @assistant_type %>", engine: :eex},
          %{role: :user, content: "Hello <%= @name %>", engine: :eex}
        ],
        params: %{assistant_type: "helpful assistant", name: "Alice"}
      })

      result = Prompt.to_text(prompt)
      assert result == "[system] You are an helpful assistant\n[user] Hello Alice"
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

  describe "versioning" do
    setup do
      prompt = Prompt.new(:user, "Hello")
      {:ok, prompt: prompt}
    end

    test "new_version creates a new version with changes", %{prompt: prompt} do
      v2 = Prompt.new_version(prompt, fn p ->
        Prompt.add_message(p, :assistant, "Hi there!")
      end)

      assert v2.version == 2
      assert length(v2.messages) == 2
      assert length(v2.history) == 1

      # Check that history contains the previous version
      [v1_history] = v2.history
      assert v1_history.version == 1
      assert length(v1_history.messages) == 1
    end

    test "get_version retrieves the current version", %{prompt: prompt} do
      {:ok, retrieved} = Prompt.get_version(prompt, 1)
      assert retrieved.version == 1
      assert retrieved.messages == prompt.messages
    end

    test "get_version retrieves a historical version", %{prompt: prompt} do
      v2 = Prompt.new_version(prompt, fn p ->
        Prompt.add_message(p, :assistant, "Hi there!")
      end)

      {:ok, v1} = Prompt.get_version(v2, 1)
      assert v1.version == 1
      assert length(v1.messages) == 1
      assert hd(v1.messages).content == "Hello"
    end

    test "get_version returns error for non-existent version", %{prompt: prompt} do
      result = Prompt.get_version(prompt, 999)
      assert {:error, "Cannot get future version 999 (current: 1)"} = result
    end

    test "list_versions returns all available versions", %{prompt: prompt} do
      v2 = Prompt.new_version(prompt, fn p ->
        Prompt.add_message(p, :assistant, "Hi there!")
      end)

      v3 = Prompt.new_version(v2, fn p ->
        Prompt.add_message(p, :user, "How are you?")
      end)

      versions = Prompt.list_versions(v3)
      assert versions == [3, 2, 1]
    end

    test "compare_versions identifies added and removed messages", %{prompt: prompt} do
      v2 = Prompt.new_version(prompt, fn p ->
        Prompt.add_message(p, :assistant, "Hi there!")
      end)

      {:ok, diff} = Prompt.compare_versions(v2, 2, 1)

      assert length(diff.added_messages) == 1
      assert hd(diff.added_messages).role == :assistant
      assert hd(diff.added_messages).content == "Hi there!"
      assert diff.removed_messages == []
    end

    test "multiple versions maintain correct history", %{prompt: prompt} do
      v2 = Prompt.new_version(prompt, fn p ->
        Prompt.add_message(p, :assistant, "Hi there!")
      end)

      v3 = Prompt.new_version(v2, fn p ->
        Prompt.add_message(p, :user, "How are you?")
      end)

      v4 = Prompt.new_version(v3, fn p ->
        Prompt.add_message(p, :assistant, "I'm doing well!")
      end)

      assert v4.version == 4
      assert length(v4.history) == 3

      [v3_history, v2_history, v1_history] = v4.history
      assert v3_history.version == 3
      assert v2_history.version == 2
      assert v1_history.version == 1

      {:ok, v1} = Prompt.get_version(v4, 1)
      assert length(v1.messages) == 1

      {:ok, v3} = Prompt.get_version(v4, 3)
      assert length(v3.messages) == 3
    end
  end
end
