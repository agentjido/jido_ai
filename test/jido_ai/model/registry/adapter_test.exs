defmodule Jido.AI.Model.Registry.AdapterTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Jido.AI.Model.Registry.Adapter

  @moduletag :capture_log

  setup :set_mimic_global

  setup do
    # Copy Code module for mocking
    copy(Code)
    copy(ReqLLM.Provider.Registry)
    :ok
  end

  describe "Adapter.list_providers/0" do
    test "returns providers from ReqLLM registry when available" do
      expected_providers = [:anthropic, :openai, :google, :mistral]

      expect(Code, :ensure_loaded, fn ReqLLM.Provider.Registry ->
        {:module, ReqLLM.Provider.Registry}
      end)

      expect(ReqLLM.Provider.Registry, :list_providers, fn ->
        expected_providers
      end)

      {:ok, providers} = Adapter.list_providers()

      assert providers == expected_providers
      assert length(providers) == 4
    end

    test "returns error when registry unavailable" do
      expect(Code, :ensure_loaded, fn ReqLLM.Provider.Registry ->
        {:error, :nofile}
      end)

      {:error, :registry_unavailable} = Adapter.list_providers()
    end

    test "handles registry loading errors" do
      expect(Code, :ensure_loaded, fn ReqLLM.Provider.Registry ->
        raise "Module loading error"
      end)

      {:error, {:registry_error, _}} = Adapter.list_providers()
    end
  end

  describe "Adapter.list_models/1" do
    test "returns models for a valid provider" do
      provider_id = :anthropic
      model_names = ["claude-3-5-sonnet", "claude-3-haiku", "claude-3-opus"]

      expect(Code, :ensure_loaded, fn ReqLLM.Provider.Registry ->
        {:module, ReqLLM.Provider.Registry}
      end)

      expect(ReqLLM.Provider.Registry, :list_models, fn ^provider_id ->
        {:ok, model_names}
      end)

      {:ok, models} = Adapter.list_models(provider_id)

      assert length(models) == 3
      assert Enum.all?(models, &is_struct(&1, ReqLLM.Model))
      assert Enum.all?(models, &(&1.provider == provider_id))

      model_ids = Enum.map(models, & &1.model)
      assert "claude-3-5-sonnet" in model_ids
      assert "claude-3-haiku" in model_ids
      assert "claude-3-opus" in model_ids
    end

    test "handles provider not found" do
      provider_id = :nonexistent

      expect(Code, :ensure_loaded, fn ReqLLM.Provider.Registry ->
        {:module, ReqLLM.Provider.Registry}
      end)

      expect(ReqLLM.Provider.Registry, :list_models, fn ^provider_id ->
        {:error, :not_found}
      end)

      {:error, :provider_not_found} = Adapter.list_models(provider_id)
    end

    test "handles registry unavailable" do
      expect(Code, :ensure_loaded, fn ReqLLM.Provider.Registry ->
        {:error, :nofile}
      end)

      {:error, :registry_unavailable} = Adapter.list_models(:anthropic)
    end

    test "handles unexpected registry response format" do
      provider_id = :anthropic

      expect(Code, :ensure_loaded, fn ReqLLM.Provider.Registry ->
        {:module, ReqLLM.Provider.Registry}
      end)

      expect(ReqLLM.Provider.Registry, :list_models, fn ^provider_id ->
        %{unexpected: "format"}
      end)

      {:error, :unexpected_response} = Adapter.list_models(provider_id)
    end
  end

  describe "Adapter.get_model/2" do
    test "returns model information when available" do
      provider_id = :anthropic
      model_name = "claude-3-5-sonnet"

      mock_model = %ReqLLM.Model{
        provider: provider_id,
        model: model_name,
        capabilities: %{tool_call: true, reasoning: true},
        limit: %{context: 200_000, output: 4_096}
      }

      expect(Code, :ensure_loaded, fn ReqLLM.Provider.Registry ->
        {:module, ReqLLM.Provider.Registry}
      end)

      expect(ReqLLM.Provider.Registry, :get_model, fn ^provider_id, ^model_name ->
        {:ok, mock_model}
      end)

      {:ok, model} = Adapter.get_model(provider_id, model_name)

      assert model.provider == provider_id
      assert model.model == model_name
      assert model.capabilities.tool_call == true
      assert model.limit.context == 200_000
    end

    test "handles model not found" do
      provider_id = :anthropic
      model_name = "nonexistent-model"

      expect(Code, :ensure_loaded, fn ReqLLM.Provider.Registry ->
        {:module, ReqLLM.Provider.Registry}
      end)

      expect(ReqLLM.Provider.Registry, :get_model, fn ^provider_id, ^model_name ->
        {:error, :not_found}
      end)

      {:error, :not_found} = Adapter.get_model(provider_id, model_name)
    end

    test "handles registry with model info map format" do
      provider_id = :openai
      model_name = "gpt-4"

      model_info = %{
        "id" => "gpt-4",
        "capabilities" => %{"tool_call" => true, "reasoning" => true},
        "limit" => %{"context" => 8_192, "output" => 4_096}
      }

      expect(Code, :ensure_loaded, fn ReqLLM.Provider.Registry ->
        {:module, ReqLLM.Provider.Registry}
      end)

      expect(ReqLLM.Provider.Registry, :get_model, fn ^provider_id, ^model_name ->
        {:ok, model_info}
      end)

      {:ok, model} = Adapter.get_model(provider_id, model_name)

      assert model.provider == provider_id
      assert model.model == model_name
      assert model.capabilities.tool_call == true
      assert model.limit.context == 8_192
    end
  end

  describe "Adapter.model_exists?/2" do
    test "returns true when model exists" do
      provider_id = :anthropic
      model_name = "claude-3-5-sonnet"

      expect(Code, :ensure_loaded, fn ReqLLM.Provider.Registry ->
        {:module, ReqLLM.Provider.Registry}
      end)

      expect(ReqLLM.Provider.Registry, :get_model, fn ^provider_id, ^model_name ->
        {:ok, %ReqLLM.Model{provider: provider_id, model: model_name}}
      end)

      assert Adapter.model_exists?(provider_id, model_name) == true
    end

    test "returns false when model does not exist" do
      provider_id = :anthropic
      model_name = "nonexistent-model"

      expect(Code, :ensure_loaded, fn ReqLLM.Provider.Registry ->
        {:module, ReqLLM.Provider.Registry}
      end)

      expect(ReqLLM.Provider.Registry, :get_model, fn ^provider_id, ^model_name ->
        {:error, :not_found}
      end)

      assert Adapter.model_exists?(provider_id, model_name) == false
    end

    test "returns false when registry unavailable" do
      expect(Code, :ensure_loaded, fn ReqLLM.Provider.Registry ->
        {:error, :nofile}
      end)

      assert Adapter.model_exists?(:anthropic, "claude-3-5-sonnet") == false
    end
  end

  describe "Adapter.get_health_info/0" do
    test "returns health information when registry is healthy" do
      expected_providers = [:anthropic, :openai, :google]

      expect(Code, :ensure_loaded, fn ReqLLM.Provider.Registry ->
        {:module, ReqLLM.Provider.Registry}
      end)

      expect(ReqLLM.Provider.Registry, :list_providers, fn ->
        expected_providers
      end)

      # Mock list_models for sampling
      expect(ReqLLM.Provider.Registry, :list_models, 3, fn
        :anthropic -> {:ok, ["claude-3-5-sonnet", "claude-3-haiku"]}
        :openai -> {:ok, ["gpt-4", "gpt-3.5-turbo"]}
        :google -> {:ok, ["gemini-pro"]}
      end)

      {:ok, health} = Adapter.get_health_info()

      assert health.registry_available == true
      assert health.provider_count == 3
      assert health.sampled_providers == 3
      assert health.estimated_total_models > 0
      assert is_integer(health.response_time_ms)
      assert %DateTime{} = health.timestamp
    end

    test "reports unhealthy when registry unavailable" do
      expect(Code, :ensure_loaded, fn ReqLLM.Provider.Registry ->
        {:error, :nofile}
      end)

      {:ok, health} = Adapter.get_health_info()

      assert health.registry_available == false
      assert health.error == :registry_unavailable
      assert %DateTime{} = health.timestamp
    end

    test "handles health check errors gracefully" do
      expect(Code, :ensure_loaded, fn ReqLLM.Provider.Registry ->
        raise "Health check error"
      end)

      {:error, {:health_check_failed, _}} = Adapter.get_health_info()
    end
  end

  describe "metadata extraction helpers" do
    test "extracts limit information correctly" do
      # This tests the private helper functions indirectly
      provider_id = :test
      model_name = "test-model"

      model_info = %{
        "limit" => %{"context" => 100_000, "output" => 4_096},
        "capabilities" => %{"tool_call" => true, "reasoning" => false},
        "modalities" => %{
          "input" => ["text", "image"],
          "output" => ["text"]
        },
        "cost" => %{"input" => 0.001, "output" => 0.002}
      }

      expect(Code, :ensure_loaded, fn ReqLLM.Provider.Registry ->
        {:module, ReqLLM.Provider.Registry}
      end)

      expect(ReqLLM.Provider.Registry, :get_model, fn ^provider_id, ^model_name ->
        {:ok, model_info}
      end)

      {:ok, model} = Adapter.get_model(provider_id, model_name)

      # Verify extracted metadata
      assert model.limit.context == 100_000
      assert model.limit.output == 4_096
      assert model.capabilities.tool_call == true
      assert model.capabilities.reasoning == false
      assert model.modalities.input == [:text, :image]
      assert model.modalities.output == [:text]
      assert model.cost.input == 0.001
      assert model.cost.output == 0.002
    end

    test "handles missing metadata gracefully" do
      provider_id = :test
      model_name = "minimal-model"

      model_info = %{"id" => "minimal-model"}

      expect(Code, :ensure_loaded, fn ReqLLM.Provider.Registry ->
        {:module, ReqLLM.Provider.Registry}
      end)

      expect(ReqLLM.Provider.Registry, :get_model, fn ^provider_id, ^model_name ->
        {:ok, model_info}
      end)

      {:ok, model} = Adapter.get_model(provider_id, model_name)

      # Should create model with defaults when metadata is missing
      assert model.provider == provider_id
      assert model.model == model_name
      # Other fields should be nil or have defaults
    end
  end
end
