defmodule ReqLLM.CapabilityTest do
  use ExUnit.Case, async: true

  alias ReqLLM.Capability

  setup_all do
    # Ensure application is started for provider registry
    Application.ensure_all_started(:req_llm)
    :ok
  end

  describe "for/1 with model spec" do
    test "returns capabilities for valid anthropic model" do
      capabilities = Capability.for("anthropic:claude-3-haiku-20240307")

      # Should at least have basic capabilities
      assert :max_tokens in capabilities
      assert :system_prompt in capabilities
      assert :metadata in capabilities

      # May have additional capabilities based on models.dev metadata
      assert is_list(capabilities)
      refute Enum.empty?(capabilities)
    end

    test "returns empty list for invalid model spec" do
      assert Capability.for("invalidprovider:model") == []
      assert Capability.for("not-a-spec") == []
    end

    test "handles unknown provider gracefully" do
      assert Capability.for("unknownprovider:model") == []
    end
  end

  describe "for/1 with Model struct" do
    test "works with Model struct" do
      model = %ReqLLM.Model{provider: :anthropic, model: "claude-3-haiku-20240307"}
      capabilities = Capability.for(model)

      assert is_list(capabilities)
      assert :max_tokens in capabilities
    end
  end

  describe "supports?/2" do
    test "checks if model supports a capability" do
      # Basic capabilities should always be supported
      assert Capability.supports?("anthropic:claude-3-haiku-20240307", :max_tokens)
      assert Capability.supports?("anthropic:claude-3-haiku-20240307", :system_prompt)
      assert Capability.supports?("anthropic:claude-3-haiku-20240307", :metadata)

      # Unknown capability should return false
      refute Capability.supports?("anthropic:claude-3-haiku-20240307", :unknown_capability)
    end
  end

  describe "provider_models/1" do
    test "returns model specs for anthropic provider" do
      models = Capability.provider_models(:anthropic)

      assert is_list(models)

      if not Enum.empty?(models) do
        # Should be in model spec format
        first_model = hd(models)
        assert String.contains?(first_model, "anthropic:")

        # Should be valid model specs
        assert String.split(first_model, ":") |> length() == 2
      end
    end

    test "returns empty list for unknown provider" do
      assert Capability.provider_models(:unknown_provider) == []
    end
  end

  describe "models_for/2" do
    test "finds models supporting basic capabilities" do
      models = Capability.models_for(:anthropic, :max_tokens)

      # Should return some models since all models support max_tokens
      assert is_list(models)

      # If we have anthropic models, they should all support max_tokens
      if not Enum.empty?(models) do
        for model <- models do
          assert Capability.supports?(model, :max_tokens)
        end
      end
    end

    test "handles unknown capabilities" do
      models = Capability.models_for(:anthropic, :unknown_capability)
      assert models == []
    end
  end

  describe "providers_for/1" do
    test "finds providers supporting basic capabilities" do
      providers = Capability.providers_for(:max_tokens)

      # Should include at least anthropic if it's configured
      assert is_list(providers)

      # Each returned provider should have models supporting the capability
      for provider <- providers do
        provider_models = Capability.models_for(provider, :max_tokens)
        refute Enum.empty?(provider_models)
      end
    end
  end
end
