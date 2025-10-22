defmodule Jido.AI.Provider.OpenRouterTest do
  use ExUnit.Case, async: false
  use Mimic

  alias Jido.AI.Keyring
  alias Jido.AI.Provider.OpenRouter

  @moduletag :capture_log
  @moduletag :tmp_dir

  setup :set_mimic_global
  setup :verify_on_exit!

  setup %{tmp_dir: tmp_dir} do
    # Mock the base_dir function to return our test directory
    original_base_dir = Application.get_env(:jido_ai, :provider_base_dir)
    Application.put_env(:jido_ai, :provider_base_dir, tmp_dir)

    # Create provider directory structure
    provider_dir = Path.join(tmp_dir, "openrouter")
    models_dir = Path.join(provider_dir, "models")
    File.mkdir_p!(provider_dir)
    File.mkdir_p!(models_dir)

    # Copy modules for mocking
    copy(Jido.AI.Model.Registry)

    # Mock Dotenvy.source! to return an empty map by default
    stub(Dotenvy, :source!, fn _sources -> %{} end)

    # Mock Dotenvy.env! to raise by default
    stub(Dotenvy, :env!, fn _key, _type -> raise "Not found" end)

    # Mock Keyring.get to return nil by default
    stub(Keyring, :get, fn _key -> nil end)

    on_exit(fn ->
      # Restore the original base_dir
      if original_base_dir do
        Application.put_env(:jido_ai, :provider_base_dir, original_base_dir)
      else
        Application.delete_env(:jido_ai, :provider_base_dir)
      end
    end)

    {:ok, %{test_dir: tmp_dir}}
  end

  describe "definition/0" do
    test "returns provider definition" do
      provider = OpenRouter.definition()
      assert provider.id == :openrouter
      assert provider.name == "OpenRouter"
      assert provider.type == :proxy
      assert provider.api_base_url == "https://openrouter.ai/api/v1"
    end
  end

  describe "normalize/2" do
    test "accepts valid model IDs" do
      assert {:ok, "anthropic/claude-3-opus"} = OpenRouter.normalize("anthropic/claude-3-opus")
      assert {:ok, "google/gemini-pro"} = OpenRouter.normalize("google/gemini-pro")
    end

    test "rejects invalid model IDs" do
      assert {:error, _} = OpenRouter.normalize("invalid-model-id")
      assert {:error, _} = OpenRouter.normalize("")
    end
  end

  describe "request_headers/2" do
    test "includes required headers" do
      headers = OpenRouter.request_headers([])

      assert headers["HTTP-Referer"] == "https://agentjido.xyz"
      assert headers["X-Title"] == "Jido AI"
      assert headers["Content-Type"] == "application/json"
    end

    test "headers handled internally by ReqLLM" do
      # Authorization headers are now handled internally by ReqLLM
      # This function only returns base headers for compatibility
      headers = OpenRouter.request_headers(api_key: "test-key")

      # Should not include Authorization - that's handled by ReqLLM
      refute Map.has_key?(headers, "Authorization")

      # But should include the base headers
      assert headers["HTTP-Referer"] == "https://agentjido.xyz"
      assert headers["X-Title"] == "Jido AI"
    end

    test "environment keys handled by ReqLLM" do
      # Environment-based authentication is now handled by ReqLLM/Keyring
      # This function just returns base headers
      headers = OpenRouter.request_headers([])

      # Should not include Authorization
      refute Map.has_key?(headers, "Authorization")
    end
  end

  describe "list_models/1" do
    test "fetches models from Registry" do
      # Now delegates to Model Registry which gets models from ReqLLM
      # The registry should have OpenRouter models available
      assert {:ok, models} = OpenRouter.list_models()

      # Should return some models from the registry
      assert is_list(models)
      assert length(models) > 0

      # Models should be properly formatted
      model = List.first(models)
      assert is_struct(model, Jido.AI.Model)
      assert model.provider == :openrouter
    end

    test "handles registry errors gracefully" do
      # Mock the Registry to return an error
      alias Jido.AI.Model.Registry

      expect(Registry, :list_models, fn :openrouter ->
        {:error, "Registry unavailable"}
      end)

      assert {:error, _} = OpenRouter.list_models()
    end
  end

  describe "model/2" do
    test "fetches specific model from Registry" do
      # Now delegates to Model Registry which gets model from ReqLLM
      # First, get a list of available models to find a real one
      {:ok, models} = OpenRouter.list_models()
      real_model = List.first(models)

      # Fetch that specific model
      assert {:ok, model_result} = OpenRouter.model(real_model.id)
      assert model_result.id == real_model.id
      assert model_result.provider == :openrouter
      assert is_struct(model_result, Jido.AI.Model)
    end

    test "handles model not found errors" do
      # Try to fetch a model that doesn't exist in the registry
      assert {:error, reason} = OpenRouter.model("nonexistent/invalid-model-12345")
      assert reason =~ "Model not found"
    end
  end
end
