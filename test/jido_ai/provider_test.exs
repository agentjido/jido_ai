defmodule JidoTest.AI.ProviderTest do
  use ExUnit.Case, async: true
  alias Jido.AI.Provider

  describe "base_dir/0" do
    test "returns the expected base directory path" do
      base_dir = Provider.base_dir()
      assert String.ends_with?(base_dir, "priv/provider")
    end
  end

  describe "list/0" do
    test "returns a list of provider structs" do
      providers = Provider.list()

      assert is_list(providers)
      assert length(providers) > 0

      # Check that all returned items are Provider structs
      Enum.each(providers, fn provider ->
        assert %Provider{} = provider
        assert is_atom(provider.id)
        assert is_binary(provider.name)
      end)

      # Check for expected providers
      provider_ids = Enum.map(providers, & &1.id)
      assert :openai in provider_ids
      assert :anthropic in provider_ids
      assert :openrouter in provider_ids
      assert :cloudflare in provider_ids
    end
  end

  describe "get_adapter_module/1" do
    test "returns the correct adapter module for a provider struct" do
      # Create a provider struct
      provider = %Provider{id: :openrouter, name: "OpenRouter"}

      # Get the adapter module
      {:ok, adapter} = Provider.get_adapter_module(provider)

      # Check that it's the expected module
      assert adapter == Jido.AI.Provider.OpenRouter
    end

    test "returns an error for an unknown provider" do
      # Create a provider struct with an unknown ID
      provider = %Provider{id: :unknown_provider, name: "Unknown"}

      # Get the adapter module
      result = Provider.get_adapter_module(provider)

      # Check that it returns an error
      assert {:error, _} = result
    end
  end

  describe "get_adapter_by_id/1" do
    test "returns the correct adapter module for a provider ID" do
      # Get the adapter module by ID
      {:ok, adapter} = Provider.get_adapter_by_id(:openrouter)

      # Check that it's the expected module
      assert adapter == Jido.AI.Provider.OpenRouter
    end

    test "returns an error for an unknown provider ID" do
      # Get the adapter module for an unknown ID
      result = Provider.get_adapter_by_id(:unknown_provider)

      # Check that it returns an error
      assert {:error, _} = result
    end

    test "handles string provider IDs" do
      # Get the adapter module by string ID
      {:ok, adapter} = Provider.get_adapter_by_id("openrouter")

      # Check that it's the expected module
      assert adapter == Jido.AI.Provider.OpenRouter
    end
  end

  describe "ensure_atom/1" do
    test "returns the input when it's already an atom" do
      assert :openrouter == Provider.ensure_atom(:openrouter)
    end

    test "converts known provider strings to atoms" do
      assert :openai == Provider.ensure_atom("openai")
      assert :anthropic == Provider.ensure_atom("anthropic")
      assert :openrouter == Provider.ensure_atom("openrouter")
    end

    test "converts unknown strings to atoms" do
      assert :unknown_provider == Provider.ensure_atom("unknown_provider")
    end

    test "returns the input for other types" do
      assert 123 == Provider.ensure_atom(123)
    end
  end
end
