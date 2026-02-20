defmodule Jido.AI.Actions.LLM.CompleteTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Jido.AI.Actions.LLM.Complete
  alias Jido.AI.TestSupport.FakeReqLLM

  @moduletag :unit
  @moduletag :capture_log

  setup :set_mimic_from_context
  setup :stub_req_llm

  defp stub_req_llm(context), do: FakeReqLLM.setup_stubs(context)

  describe "schema" do
    test "has required and optional fields" do
      assert Complete.schema().fields[:prompt].meta.required == true
      refute Complete.schema().fields[:model].meta.required
      refute Complete.schema().fields[:timeout].meta.required
    end

    test "has expected defaults" do
      assert Complete.schema().fields[:max_tokens].value == 1024
      assert Complete.schema().fields[:temperature].value == 0.7
    end
  end

  describe "run/2" do
    test "returns response on happy path with default model resolution" do
      assert {:ok, result} = Complete.run(%{prompt: "The answer is"}, %{})
      assert result.model == Jido.AI.resolve_model(:fast)
      assert result.text =~ "Stubbed response for: The answer is"
      assert result.usage.total_tokens == result.usage.input_tokens + result.usage.output_tokens
    end

    test "returns validation error when prompt is missing" do
      assert {:error, _reason} = Complete.run(%{}, %{})
    end

    test "returns validation error when prompt is empty" do
      assert {:error, _reason} = Complete.run(%{prompt: ""}, %{})
    end

    test "uses context defaults when params are omitted" do
      context = %{
        provided_params: [:prompt],
        plugin_state: %{chat: %{default_model: :capable, default_max_tokens: 333, default_temperature: 0.2}}
      }

      expect(ReqLLM.Generation, :generate_text, fn model, _messages, opts ->
        assert model == Jido.AI.resolve_model(:capable)
        assert opts[:max_tokens] == 333
        assert opts[:temperature] == 0.2

        {:ok, %{message: %{content: "configured"}, usage: %{input_tokens: 3, output_tokens: 4}}}
      end)

      assert {:ok, result} = Complete.run(%{prompt: "hello"}, context)
      assert result.model == Jido.AI.resolve_model(:capable)
      assert result.text == "configured"
    end

    test "explicit params override context defaults" do
      context = %{
        provided_params: [:prompt, :model, :max_tokens, :temperature],
        plugin_state: %{chat: %{default_model: :fast, default_max_tokens: 999, default_temperature: 0.95}}
      }

      params = %{
        prompt: "hello",
        model: "custom:model",
        max_tokens: 42,
        temperature: 0.1
      }

      expect(ReqLLM.Generation, :generate_text, fn model, _messages, opts ->
        assert model == "custom:model"
        assert opts[:max_tokens] == 42
        assert opts[:temperature] == 0.1

        {:ok, %{message: %{content: "overridden"}, usage: %{input_tokens: 1, output_tokens: 2}}}
      end)

      assert {:ok, result} = Complete.run(params, context)
      assert result.model == "custom:model"
      assert result.text == "overridden"
    end

    test "resolves atom model aliases" do
      assert {:ok, result} = Complete.run(%{prompt: "hello", model: :capable}, %{})
      assert result.model == Jido.AI.resolve_model(:capable)
    end

    test "sanitizes provider errors" do
      expect(ReqLLM.Generation, :generate_text, fn _model, _messages, _opts ->
        {:error, :timeout}
      end)

      assert {:error, "Request timed out"} = Complete.run(%{prompt: "hello"}, %{})
    end

    test "returns sanitized error on invalid model format" do
      assert {:error, "An error occurred"} = Complete.run(%{prompt: "hello", model: 123}, %{})
    end
  end
end
