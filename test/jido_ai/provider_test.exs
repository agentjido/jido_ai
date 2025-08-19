defmodule Jido.AI.ProviderTest do
  @moduledoc """
  Tests for the Provider struct and related functionality.
  """

  use ExUnit.Case, async: true

  alias Jido.AI.Error.Invalid.Parameter
  alias Jido.AI.Provider

  describe "Provider struct" do
    test "can be created with all fields" do
      provider = %Provider{
        id: :test,
        name: "Test Provider",
        base_url: "https://test.example.com",
        doc: "A test provider",
        env: [:test_api_key],
        models: %{}
      }

      assert provider.id == :test
      assert provider.name == "Test Provider"
      assert provider.base_url == "https://test.example.com"
      assert provider.doc == "A test provider"
      assert provider.env == [:test_api_key]
      assert provider.models == %{}
    end

    test "has default values for optional fields" do
      provider = %Provider{
        id: :minimal,
        name: "Minimal Provider"
      }

      assert provider.id == :minimal
      assert provider.name == "Minimal Provider"
      assert provider.base_url == nil
      assert provider.doc == nil
      assert is_nil(provider.env) or provider.env == []
      assert is_nil(provider.models) or provider.models == %{}
    end
  end

  describe "validate/1" do
    test "validates correct provider struct" do
      provider = %Provider{
        id: :test,
        name: "Test Provider",
        base_url: "https://test.example.com",
        env: [:test_api_key],
        doc: "Test provider",
        models: %{}
      }

      assert {:ok, ^provider} = Provider.validate(provider)
    end

    test "returns error for invalid provider" do
      invalid_provider = %Provider{
        # Should be atom
        id: "not_atom",
        name: "Test Provider",
        base_url: "https://test.example.com",
        env: [:test_api_key],
        doc: "Test provider",
        models: %{}
      }

      assert {:error, _validation_error} = Provider.validate(invalid_provider)
    end
  end

  describe "key validation" do
    test "get_key/2 returns error when no API key found" do
      provider = %Provider{
        id: :test_provider,
        name: "Test",
        env: [:nonexistent_var]
      }

      assert {:error, reason} = Provider.get_key(provider)
      assert %Parameter{} = reason
      assert String.contains?(reason.parameter, "nonexistent_var")
    end

    test "validate_key!/2 raises on validation error" do
      provider = %Provider{
        id: :test_provider,
        name: "Test",
        env: [:nonexistent_var]
      }

      assert_raise Parameter, fn ->
        Provider.validate_key!(provider)
      end
    end
  end
end
