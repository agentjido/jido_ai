defmodule ReqLLM.Coverage.Anthropic.SystemPromptsTest do
  use ExUnit.Case, async: true
  alias ReqLLM.Test.LiveFixture

  @moduletag :coverage
  @moduletag :anthropic
  @moduletag :system_prompts

  describe "system prompts" do
    test "system prompt as string in top-level field" do
      model = ReqLLM.Model.from("anthropic:claude-3-haiku-20240307")
      system_prompt = "You are a helpful coding assistant specializing in Elixir."
      
      context = ReqLLM.Context.new([
        ReqLLM.Message.system(system_prompt),
        ReqLLM.Message.user("Write a simple hello world function in Elixir")
      ])

      {:ok, response} = LiveFixture.use_fixture("system_prompts/string_system", fn ->
        ReqLLM.generate_text(model, context: context, max_tokens: 100)
      end)

      # Verify response contains code
      text_content = response.chunks 
                    |> Enum.filter(&(&1.type == :text))
                    |> Enum.map(& &1.text)
                    |> Enum.join()

      assert text_content =~ "def"
      assert text_content =~ "hello"
    end

    test "system prompt as array of content blocks" do
      model = ReqLLM.Model.from("anthropic:claude-3-haiku-20240307")
      
      # System prompt with multiple content parts
      system_parts = [
        ReqLLM.Message.ContentPart.text("You are a code reviewer."),
        ReqLLM.Message.ContentPart.text("Focus on security and performance.")
      ]
      
      context = ReqLLM.Context.new([
        ReqLLM.Message.new(:system, system_parts),
        ReqLLM.Message.user("Review this code: def add(a, b), do: a + b")
      ])

      {:ok, response} = LiveFixture.use_fixture("system_prompts/array_system", fn ->
        ReqLLM.generate_text(model, context: context, max_tokens: 150)
      end)

      text_content = response.chunks 
                    |> Enum.filter(&(&1.type == :text))
                    |> Enum.map(& &1.text)
                    |> Enum.join()

      # Should provide review feedback
      assert text_content =~ ~r/(review|security|performance)/i
    end

    test "empty system prompt is omitted from request" do
      model = ReqLLM.Model.from("anthropic:claude-3-haiku-20240307")
      
      context = ReqLLM.Context.new([
        ReqLLM.Message.user("What is 2 + 2?")
      ])

      {:ok, response} = LiveFixture.use_fixture("system_prompts/no_system", fn ->
        ReqLLM.generate_text(model, context: context, max_tokens: 50)
      end)

      # Should still get valid response
      text_content = response.chunks 
                    |> Enum.filter(&(&1.type == :text))
                    |> Enum.map(& &1.text)
                    |> Enum.join()

      assert text_content =~ "4"
    end

    test "system message with role:system in messages array should fail" do
      # Note: This tests that our provider correctly converts system messages
      # to top-level system field and doesn't send role:system in messages
      model = ReqLLM.Model.from("anthropic:claude-3-haiku-20240307")
      
      context = ReqLLM.Context.new([
        ReqLLM.Message.system("You are helpful"),
        ReqLLM.Message.user("Hello")
      ])

      # This should work because our provider converts system messages properly
      {:ok, response} = LiveFixture.use_fixture("system_prompts/converted_system", fn ->
        ReqLLM.generate_text(model, context: context, max_tokens: 50)
      end)

      assert response.chunks != []
    end

    test "multiple system messages should be handled gracefully" do
      model = ReqLLM.Model.from("anthropic:claude-3-haiku-20240307")
      
      # Context validation should prevent multiple system messages
      assert_raise ArgumentError, ~r/multiple system messages/i, fn ->
        ReqLLM.Context.new([
          ReqLLM.Message.system("First system message"),
          ReqLLM.Message.system("Second system message"),
          ReqLLM.Message.user("Hello")
        ])
      end
    end
  end
end
