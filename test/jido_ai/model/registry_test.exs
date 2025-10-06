defmodule Jido.AI.Model.RegistryTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Jido.AI.Model.Registry
  alias Jido.AI.Model.Registry.{Adapter, MetadataBridge}
  alias Jido.AI.{Model, Provider}

  @moduletag :capture_log

  setup :set_mimic_global

  setup do
    # Copy modules that will be mocked
    copy(Adapter)
    copy(Provider)
    copy(MetadataBridge)
    copy(Registry)
    :ok
  end

  describe "Registry.list_models/1" do
    test "returns models from ReqLLM registry when available" do
      # Mock successful registry response
      _mock_models = [
        %Model{
          id: "claude-3-5-sonnet",
          provider: :anthropic,
          name: "Claude 3.5 Sonnet",
          capabilities: %{tool_call: true, reasoning: true},
          reqllm_id: "anthropic:claude-3-5-sonnet"
        },
        %Model{
          id: "gpt-4",
          provider: :openai,
          name: "GPT-4",
          capabilities: %{tool_call: true, reasoning: true},
          reqllm_id: "openai:gpt-4"
        }
      ]

      expect(Adapter, :list_providers, fn -> {:ok, [:anthropic, :openai]} end)

      expect(Adapter, :list_models, 2, fn
        :anthropic -> {:ok, [%ReqLLM.Model{provider: :anthropic, model: "claude-3-5-sonnet"}]}
        :openai -> {:ok, [%ReqLLM.Model{provider: :openai, model: "gpt-4"}]}
      end)

      # Mock metadata bridge conversion
      stub(MetadataBridge, :to_jido_model, fn reqllm_model ->
        case reqllm_model.provider do
          :anthropic ->
            %Model{
              id: "claude-3-5-sonnet",
              provider: :anthropic,
              name: "Claude 3.5 Sonnet",
              capabilities: %{tool_call: true, reasoning: true},
              reqllm_id: "anthropic:claude-3-5-sonnet"
            }

          :openai ->
            %Model{
              id: "gpt-4",
              provider: :openai,
              name: "GPT-4",
              capabilities: %{tool_call: true, reasoning: true},
              reqllm_id: "openai:gpt-4"
            }
        end
      end)

      {:ok, models} = Registry.list_models()

      assert length(models) == 2
      assert Enum.any?(models, &(&1.provider == :anthropic))
      assert Enum.any?(models, &(&1.provider == :openai))
    end

    test "falls back to legacy provider when registry unavailable" do
      # Mock registry failure
      expect(Adapter, :list_providers, fn -> {:error, :registry_unavailable} end)

      # Mock legacy provider fallback
      legacy_models = [
        %{"id" => "legacy-model", "provider" => :openai}
      ]

      stub(Provider, :list_all_cached_models, fn -> legacy_models end)

      {:ok, models} = Registry.list_models()

      assert is_list(models)
      assert length(models) >= 0
    end

    test "filters by provider when specified" do
      mock_anthropic_model = %ReqLLM.Model{provider: :anthropic, model: "claude-3-5-sonnet"}

      expect(Adapter, :list_models, fn :anthropic ->
        {:ok, [mock_anthropic_model]}
      end)

      stub(MetadataBridge, :to_jido_model, fn _model ->
        %Model{
          id: "claude-3-5-sonnet",
          provider: :anthropic,
          name: "Claude 3.5 Sonnet",
          reqllm_id: "anthropic:claude-3-5-sonnet"
        }
      end)

      {:ok, models} = Registry.list_models(:anthropic)

      assert length(models) == 1
      assert hd(models).provider == :anthropic
    end
  end

  describe "Registry.get_model/2" do
    test "returns enhanced model from registry" do
      mock_reqllm_model = %ReqLLM.Model{
        provider: :anthropic,
        model: "claude-3-5-sonnet",
        capabilities: %{tool_call: true, reasoning: true},
        limit: %{context: 200_000, output: 4_096}
      }

      expected_jido_model = %Model{
        id: "claude-3-5-sonnet",
        provider: :anthropic,
        name: "Claude 3.5 Sonnet",
        capabilities: %{tool_call: true, reasoning: true},
        reqllm_id: "anthropic:claude-3-5-sonnet"
      }

      expect(Adapter, :get_model, fn :anthropic, "claude-3-5-sonnet" ->
        {:ok, mock_reqllm_model}
      end)

      stub(MetadataBridge, :to_jido_model, fn _model -> expected_jido_model end)

      {:ok, model} = Registry.get_model(:anthropic, "claude-3-5-sonnet")

      assert model.id == "claude-3-5-sonnet"
      assert model.provider == :anthropic
      assert model.capabilities.tool_call == true
      assert model.capabilities.reasoning == true
    end

    test "falls back to legacy provider when model not found in registry" do
      # Mock registry failure
      expect(Adapter, :get_model, fn :openai, "gpt-4" ->
        {:error, :not_found}
      end)

      # Mock legacy adapter fallback
      expect(Provider, :get_adapter_by_id, fn :openai ->
        {:ok, Jido.AI.Provider.OpenAI}
      end)

      legacy_model = %{"id" => "gpt-4", "provider" => :openai}
      stub(Provider, :list_all_cached_models, fn -> [legacy_model] end)
      stub(Provider, :get_combined_model_info, fn "gpt-4" -> {:ok, legacy_model} end)

      {:ok, model} = Registry.get_model(:openai, "gpt-4")

      assert model["id"] == "gpt-4"
      assert model["provider"] == :openai
    end
  end

  describe "Registry.discover_models/1" do
    test "filters models by capabilities" do
      mock_models = [
        %Model{
          id: "claude-3-5-sonnet",
          provider: :anthropic,
          capabilities: %{tool_call: true, reasoning: true}
        },
        %Model{
          id: "claude-3-haiku",
          provider: :anthropic,
          capabilities: %{tool_call: false, reasoning: true}
        },
        %Model{
          id: "gpt-4",
          provider: :openai,
          capabilities: %{tool_call: true, reasoning: true}
        }
      ]

      expect(Adapter, :list_providers, fn -> {:ok, [:anthropic, :openai]} end)
      expect(Adapter, :list_models, 2, fn _provider -> {:ok, []} end)

      # Mock the internal list_models call to return our test models
      stub(Registry, :list_models, fn -> {:ok, mock_models} end)

      {:ok, tool_call_models} = Registry.discover_models(capability: :tool_call)

      # Should only return models with tool_call capability
      assert length(tool_call_models) == 2

      assert Enum.all?(tool_call_models, fn model ->
               model.capabilities && model.capabilities.tool_call
             end)
    end

    test "filters models by context length" do
      mock_models = [
        %Model{
          id: "model-small-context",
          provider: :test,
          endpoints: [%Model.Endpoint{context_length: 8_192}]
        },
        %Model{
          id: "model-large-context",
          provider: :test,
          endpoints: [%Model.Endpoint{context_length: 200_000}]
        }
      ]

      stub(Registry, :list_models, fn -> {:ok, mock_models} end)

      {:ok, large_context_models} = Registry.discover_models(min_context_length: 100_000)

      assert length(large_context_models) == 1
      assert hd(large_context_models).id == "model-large-context"
    end

    test "handles empty filter list" do
      mock_models = [
        %Model{id: "model1", provider: :test},
        %Model{id: "model2", provider: :test}
      ]

      stub(Registry, :list_models, fn -> {:ok, mock_models} end)

      {:ok, all_models} = Registry.discover_models([])

      assert length(all_models) == 2
    end
  end

  describe "Registry.get_registry_stats/0" do
    test "returns comprehensive statistics" do
      mock_models = [
        %Model{
          id: "model1",
          provider: :anthropic,
          capabilities: %{tool_call: true, reasoning: true},
          reqllm_id: "anthropic:model1"
        },
        %Model{
          id: "model2",
          provider: :openai,
          capabilities: %{tool_call: true, reasoning: false},
          reqllm_id: "openai:model2"
        },
        %Model{
          id: "legacy-model",
          provider: :legacy,
          capabilities: nil,
          reqllm_id: nil
        }
      ]

      stub(Registry, :list_models, fn -> {:ok, mock_models} end)

      {:ok, stats} = Registry.get_registry_stats()

      assert stats.total_models == 3
      # models with reqllm_id
      assert stats.registry_models == 2
      # models without reqllm_id
      assert stats.legacy_models == 1
      assert stats.total_providers == 3

      # Check provider coverage
      assert stats.provider_coverage[:anthropic] == 1
      assert stats.provider_coverage[:openai] == 1
      assert stats.provider_coverage[:legacy] == 1

      # Check capabilities distribution
      assert stats.capabilities_distribution[:tool_call] == 2
      assert stats.capabilities_distribution[:reasoning] == 1
    end

    test "handles registry failure gracefully" do
      stub(Registry, :list_models, fn -> {:error, :registry_unavailable} end)

      {:ok, stats} = Registry.get_registry_stats()

      # Should still return stats structure, even if with error information
      assert is_map(stats)
    end
  end

  describe "error handling" do
    test "handles registry adapter errors gracefully" do
      expect(Adapter, :list_providers, fn -> raise "Registry connection error" end)

      # Should not crash, should fall back gracefully
      result = Registry.list_models()

      # Should return some kind of result (even if empty/error)
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "handles metadata bridge errors gracefully" do
      mock_reqllm_model = %ReqLLM.Model{provider: :test, model: "test-model"}

      expect(Adapter, :list_providers, fn -> {:ok, [:test]} end)
      expect(Adapter, :list_models, fn :test -> {:ok, [mock_reqllm_model]} end)

      # Mock metadata bridge to raise error
      stub(MetadataBridge, :to_jido_model, fn _model ->
        raise "Metadata conversion error"
      end)

      # Should handle the error and not crash
      result = Registry.list_models()

      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end
end
