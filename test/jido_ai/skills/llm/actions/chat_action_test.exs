defmodule Jido.AI.Actions.LLM.ChatTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Jido.AI.Actions.LLM.Chat
  alias Jido.AI.TestSupport.FakeReqLLM

  @moduletag :unit
  @moduletag :capture_log

  setup :set_mimic_from_context
  setup :stub_req_llm

  defp stub_req_llm(context), do: FakeReqLLM.setup_stubs(context)

  describe "schema" do
    test "has required and optional fields" do
      assert Chat.schema().fields[:prompt].meta.required == true
      refute Chat.schema().fields[:model].meta.required
      refute Chat.schema().fields[:system_prompt].meta.required
      refute Chat.schema().fields[:timeout].meta.required
    end

    test "has expected defaults" do
      assert Chat.schema().fields[:max_tokens].value == 1024
      assert Chat.schema().fields[:temperature].value == 0.7
    end
  end

  describe "run/2" do
    test "returns response on happy path with default model resolution" do
      assert {:ok, result} = Chat.run(%{prompt: "Hello world"}, %{})
      assert result.model == Jido.AI.resolve_model(:fast)
      assert result.text =~ "Stubbed response for: Hello world"
      assert result.usage.input_tokens > 0
      assert result.usage.output_tokens > 0
      assert result.usage.total_tokens == result.usage.input_tokens + result.usage.output_tokens
    end

    test "returns validation error when prompt is missing" do
      assert {:error, _reason} = Chat.run(%{}, %{})
    end

    test "returns validation error when prompt is empty" do
      assert {:error, _reason} = Chat.run(%{prompt: ""}, %{})
    end

    test "applies plugin defaults when fields are omitted" do
      context = %{
        provided_params: [:prompt],
        plugin_state: %{
          chat: %{
            default_model: :capable,
            default_system_prompt: "You are concise",
            default_max_tokens: 222,
            default_temperature: 0.15
          }
        }
      }

      expect(ReqLLM.Generation, :generate_text, fn model, messages, opts ->
        assert model == Jido.AI.resolve_model(:capable)
        assert opts[:max_tokens] == 222
        assert opts[:temperature] == 0.15
        assert has_system_prompt?(messages, "You are concise")

        {:ok, %{message: %{content: "ok"}, usage: %{input_tokens: 2, output_tokens: 3}}}
      end)

      assert {:ok, result} = Chat.run(%{prompt: "hello"}, context)
      assert result.text == "ok"
      assert result.model == Jido.AI.resolve_model(:capable)
    end

    test "explicit params override plugin defaults" do
      context = %{
        provided_params: [:prompt, :model, :system_prompt, :max_tokens, :temperature],
        plugin_state: %{
          chat: %{
            default_model: :fast,
            default_system_prompt: "Default system prompt",
            default_max_tokens: 999,
            default_temperature: 0.99
          }
        }
      }

      params = %{
        prompt: "hello",
        model: "custom:model",
        system_prompt: "Explicit system prompt",
        max_tokens: 55,
        temperature: 0.4
      }

      expect(ReqLLM.Generation, :generate_text, fn model, messages, opts ->
        assert model == "custom:model"
        assert opts[:max_tokens] == 55
        assert opts[:temperature] == 0.4
        assert has_system_prompt?(messages, "Explicit system prompt")

        {:ok, %{message: %{content: "overridden"}, usage: %{input_tokens: 1, output_tokens: 1}}}
      end)

      assert {:ok, result} = Chat.run(params, context)
      assert result.model == "custom:model"
      assert result.text == "overridden"
    end

    test "sanitizes provider errors" do
      expect(ReqLLM.Generation, :generate_text, fn _model, _messages, _opts ->
        {:error, :timeout}
      end)

      assert {:error, "Request timed out"} = Chat.run(%{prompt: "hello"}, %{})
    end

    test "returns sanitized error on invalid model format" do
      assert {:error, "An error occurred"} = Chat.run(%{prompt: "hello", model: 123}, %{})
    end
  end

  defp has_system_prompt?(messages, expected) do
    Enum.any?(messages, fn
      %{role: role, content: content} when role in [:system, "system"] ->
        content_to_string(content) == expected

      _ ->
        false
    end)
  end

  defp content_to_string(content) when is_binary(content), do: content
  defp content_to_string(content) when is_list(content), do: Jido.AI.Turn.extract_from_content(content)
  defp content_to_string(_), do: ""
end
