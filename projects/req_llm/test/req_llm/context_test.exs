defmodule ReqLLM.ContextTest do
  use ExUnit.Case, async: true

  alias ReqLLM.Context
  alias ReqLLM.Message
  alias ReqLLM.Message.ContentPart

  describe "Context" do
    test "creates context" do
      context = Context.new()
      assert context.messages == []

      messages = [
        %Message{role: :system, content: [ContentPart.text("You are helpful")]},
        %Message{role: :user, content: [ContentPart.text("Hello")]}
      ]

      context = Context.new(messages)
      assert Context.to_list(context) == messages
      assert length(context.messages) == 2
    end

    test "validates context" do
      messages = [
        %Message{role: :system, content: [ContentPart.text("System")]},
        %Message{role: :user, content: [ContentPart.text("Hello")]}
      ]

      context = Context.new(messages)

      assert {:ok, ^context} = Context.validate(context)
      assert context == Context.validate!(context)
    end

    test "provides constructor functions" do
      assert %Message{role: :user} = Context.user("Hello")
      assert %Message{role: :assistant} = Context.assistant("Hi")
      assert %Message{role: :system} = Context.system("System")

      # With metadata
      user_msg = Context.user("Hello", %{source: "chat"})
      assert user_msg.metadata == %{source: "chat"}

      # With image
      image_msg = Context.with_image(:user, "Look at this", "http://ex.com/img.jpg")
      assert image_msg.role == :user
      assert length(image_msg.content) == 2
    end

    test "supports Enumerable protocol" do
      messages = [Context.system("System"), Context.user("Hello")]
      context = Context.new(messages)

      # Test enumerable functions work
      assert {:ok, 2} = Enumerable.count(context)
      assert Enum.count(context) == 2
      assert Enum.map(context, & &1.role) == [:system, :user]
    end

    test "inspect protocol shows message count and roles" do
      context =
        Context.new([
          Context.system("System"),
          Context.user("Hello"),
          Context.assistant("Hi"),
          Context.user("How are you?")
        ])

      inspected = inspect(context)
      assert inspected =~ "#Context<4 msgs: system,user,assistant,user>"
    end
  end
end
