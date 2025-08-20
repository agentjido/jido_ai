defmodule Jido.AI.Provider.OpenRouterTest do
  @moduledoc """
  Tests for OpenRouter provider implementation.

  Focuses on provider-specific behavior since OpenRouter uses all defaults from Base.
  """

  use Jido.AI.TestSupport.HTTPCase
  use Jido.AI.TestSupport.KeyringCase

  alias Jido.AI.Error.API.Request
  alias Jido.AI.Error.Invalid.Parameter
  alias Jido.AI.Model
  alias Jido.AI.Provider.OpenRouter

  describe "provider configuration" do
    test "provider_info returns correct metadata" do
      info = OpenRouter.provider_info()

      assert info.id == :openrouter
      assert info.base_url == "https://openrouter.ai/api/v1"
      assert is_map(info.models)
      assert map_size(info.models) > 0
    end

    test "api_url returns correct endpoint" do
      assert OpenRouter.api_url() == "https://openrouter.ai/api/v1"
    end

    test "has models loaded from openrouter.json" do
      info = OpenRouter.provider_info()

      # Should have at least some models
      assert map_size(info.models) > 0

      # Check that models have expected structure
      model_ids = Map.keys(info.models)
      refute Enum.empty?(model_ids)
    end
  end

  describe "generate_text/3 (using defaults)" do
    test "successful text generation", %{test_name: test_name} do
      model = %Model{provider: :openrouter, model: "anthropic/claude-3.5-sonnet"}

      session(openrouter_api_key: "sk-or-test-key") do
        with_success(%{
          "choices" => [%{"message" => %{"content" => "Hello from OpenRouter!"}}]
        }) do
          result = OpenRouter.generate_text(model, "Hello")
          assert {:ok, "Hello from OpenRouter!"} = result
        end
      end
    end

    test "handles API errors", %{test_name: test_name} do
      model = %Model{provider: :openrouter, model: "anthropic/claude-3.5-sonnet"}

      session(openrouter_api_key: "sk-or-test-key") do
        with_error(429, %{"error" => %{"message" => "Rate limited"}}) do
          result = OpenRouter.generate_text(model, "Hello")
          assert {:error, %Request{}} = result
        end
      end
    end

    test "validates prompt", %{test_name: _test_name} do
      model = %Model{provider: :openrouter, model: "anthropic/claude-3.5-sonnet"}

      result = OpenRouter.generate_text(model, "")
      assert {:error, %Parameter{parameter: "prompt"}} = result
    end
  end

  describe "stream_text/3 (using defaults)" do
    test "successful streaming", %{test_name: test_name} do
      model = %Model{provider: :openrouter, model: "anthropic/claude-3.5-sonnet"}

      session(openrouter_api_key: "sk-or-test-key") do
        with_sse([
          %{"choices" => [%{"delta" => %{"content" => "Hello"}}]},
          %{"choices" => [%{"delta" => %{"content" => " world"}}]}
        ]) do
          result = OpenRouter.stream_text(model, "Hello")
          assert {:ok, stream} = result

          chunks = Enum.to_list(stream)
          # Just verify we get some text chunks back - exact content may vary
          refute Enum.empty?(chunks)
          assert Enum.all?(chunks, &is_binary/1)
        end
      end
    end

    test "validates prompt for streaming", %{test_name: _test_name} do
      model = %Model{provider: :openrouter, model: "anthropic/claude-3.5-sonnet"}

      result = OpenRouter.stream_text(model, "")
      assert {:error, %Parameter{parameter: "prompt"}} = result
    end
  end
end
