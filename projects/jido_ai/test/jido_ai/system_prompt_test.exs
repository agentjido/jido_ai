defmodule Jido.AI.SystemPromptTest do
  @moduledoc """
  Tests for system prompt functionality in Jido.AI.

  This module tests the implementation of Iteration 2 of the rich prompts plan,
  which adds explicit system_prompt parameter support while maintaining backward compatibility.
  """

  use ExUnit.Case, async: false
  use Jido.AI.TestSupport.HTTPCase

  import Jido.AI.Test.Fixtures.ModelFixtures
  import Jido.AI.TestSupport.Assertions
  import Mimic

  alias Jido.AI
  alias Jido.AI.Provider.OpenAI
  alias Jido.AI.Provider.Request.Builder
  alias Jido.AI.Test.FakeProvider
  alias Jido.AI.{Keyring, Message}

  setup :verify_on_exit!

  setup do
    copy(Keyring)
    # Register providers for testing
    Jido.AI.Provider.Registry.register(:fake, FakeProvider)

    on_exit(fn ->
      Jido.AI.Provider.Registry.clear()
      Jido.AI.Provider.Registry.initialize()
    end)

    :ok
  end

  describe "generate_text/3 - system prompt support" do
    test "3-arity with system prompt option works" do
      stub(Kagi, :get, fn _, _, _ -> nil end)

      result =
        assert_ok(AI.generate_text("fake:fake-model", "Hello", system_prompt: "You are helpful"))

      assert result =~ "system:You are helpful:"
      assert result =~ "fake-model"
      assert result =~ "Hello"
    end

    test "3-arity with nil system prompt option works" do
      stub(Kagi, :get, fn _, _, _ -> nil end)

      result = assert_ok(AI.generate_text("fake:fake-model", "Hello", system_prompt: nil))

      refute result =~ "system:"
      assert result =~ "fake-model"
      assert result =~ "Hello"
    end

    test "3-arity with system prompt and other options" do
      stub(Kagi, :get, fn _, _, _ -> nil end)

      result =
        assert_ok(
          AI.generate_text("fake:fake-model", "Hello",
            system_prompt: "You are helpful",
            max_tokens: 100
          )
        )

      assert result =~ "system:You are helpful:"
      assert result =~ "fake-model"
      assert result =~ "Hello"
      assert result =~ "max_tokens: 100"
    end

    test "3-arity with message array and system prompt" do
      stub(Kagi, :get, fn _, _, _ -> nil end)

      messages = [%Message{role: :user, content: "Hello there"}]

      result =
        assert_ok(AI.generate_text("fake:fake-model", messages, system_prompt: "You are helpful"))

      assert result =~ "system:You are helpful:"
      assert result =~ "fake-model"
    end
  end

  describe "generate_text backward compatibility" do
    test "3-arity with opts still works (backward compatible)" do
      stub(Kagi, :get, fn _, _, _ -> nil end)

      result = assert_ok(AI.generate_text("fake:fake-model", "Hello", max_tokens: 50))

      refute result =~ "system:"
      assert result =~ "fake-model"
      assert result =~ "Hello"
      assert result =~ "max_tokens: 50"
    end

    test "2-arity still works (backward compatible)" do
      stub(Kagi, :get, fn _, _, _ -> nil end)

      result = assert_ok(AI.generate_text("fake:fake-model", "Hello"))

      refute result =~ "system:"
      assert result =~ "fake-model"
      assert result =~ "Hello"
    end
  end

  describe "stream_text/3 - system prompt support" do
    test "3-arity with system prompt option works" do
      stub(Kagi, :get, fn _, _, _ -> nil end)

      stream =
        assert_ok(AI.stream_text("fake:fake-model", "Hello", system_prompt: "You are helpful"))

      chunks = Enum.to_list(stream)

      assert chunks == ["chunk_1", "chunk_2", "chunk_3"]
    end

    test "3-arity with nil system prompt option works" do
      stub(Kagi, :get, fn _, _, _ -> nil end)

      stream = assert_ok(AI.stream_text("fake:fake-model", "Hello", system_prompt: nil))
      chunks = Enum.to_list(stream)

      assert chunks == ["chunk_1", "chunk_2", "chunk_3"]
    end

    test "3-arity with system prompt and other options" do
      stub(Kagi, :get, fn _, _, _ -> nil end)

      stream =
        assert_ok(
          AI.stream_text("fake:fake-model", "Hello",
            system_prompt: "You are helpful",
            max_tokens: 100
          )
        )

      chunks = Enum.to_list(stream)

      assert chunks == ["chunk_1", "chunk_2", "chunk_3"]
    end
  end

  describe "stream_text backward compatibility" do
    test "3-arity with opts still works (backward compatible)" do
      stub(Kagi, :get, fn _, _, _ -> nil end)

      stream = assert_ok(AI.stream_text("fake:fake-model", "Hello", max_tokens: 50))
      chunks = Enum.to_list(stream)

      assert chunks == ["chunk_1", "chunk_2", "chunk_3"]
    end

    test "2-arity still works (backward compatible)" do
      stub(Kagi, :get, fn _, _, _ -> nil end)

      stream = assert_ok(AI.stream_text("fake:fake-model", "Hello"))
      chunks = Enum.to_list(stream)

      assert chunks == ["chunk_1", "chunk_2", "chunk_3"]
    end
  end

  describe "Provider.Base integration tests" do
    test "build_chat_completion_body prepends system message" do
      model = fake()

      # Test without system prompt
      body_without_system =
        Builder.build_chat_completion_body(OpenAI, model, "Hello", nil, [])

      messages_without_system = body_without_system[:messages]

      assert length(messages_without_system) == 1
      assert hd(messages_without_system) == %{role: "user", content: "Hello"}

      # Test with system prompt
      body_with_system =
        Builder.build_chat_completion_body(OpenAI, model, "Hello", "You are helpful", [])

      messages_with_system = body_with_system[:messages]

      assert length(messages_with_system) == 2
      assert hd(messages_with_system) == %{role: "system", content: "You are helpful"}
      assert Enum.at(messages_with_system, 1) == %{role: "user", content: "Hello"}
    end

    test "build_chat_completion_body with message array and system prompt" do
      model = fake()
      messages = [%Message{role: :user, content: "Hello there"}]

      body =
        Builder.build_chat_completion_body(OpenAI, model, messages, "You are helpful", [])

      final_messages = body[:messages]

      assert length(final_messages) == 2
      assert hd(final_messages) == %{role: "system", content: "You are helpful"}
      assert Enum.at(final_messages, 1) == %{"role" => "user", "content" => "Hello there"}
    end

    test "system message is injected at position 0" do
      model = fake()

      existing_messages = [
        %Message{role: :user, content: "First message"},
        %Message{role: :assistant, content: "Response"},
        %Message{role: :user, content: "Second message"}
      ]

      body =
        Builder.build_chat_completion_body(
          OpenAI,
          model,
          existing_messages,
          "System instruction",
          []
        )

      final_messages = body[:messages]

      assert length(final_messages) == 4
      assert hd(final_messages) == %{role: "system", content: "System instruction"}
      # Verify other messages follow
      assert Enum.at(final_messages, 1)["role"] == "user"
      assert Enum.at(final_messages, 1)["content"] == "First message"
    end
  end
end
