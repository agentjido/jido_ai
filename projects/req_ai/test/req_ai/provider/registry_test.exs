defmodule ReqAI.Provider.RegistryTest do
  use ExUnit.Case, async: true
  doctest ReqAI.Provider.Registry

  alias ReqAI.Provider.Registry

  describe "fetch/1" do
    test "returns error for unknown provider" do
      assert Registry.fetch(:unknown) == {:error, :not_found}
    end

    test "returns error for non-atom provider" do
      assert Registry.fetch("string") == {:error, :not_found}
    end
  end

  describe "fetch!/1" do
    test "raises for unknown provider" do
      assert_raise ReqAI.Error.Invalid.Parameter, ~r/provider unknown/, fn ->
        Registry.fetch!(:unknown)
      end
    end
  end

  describe "list_providers/0" do
    test "returns list of registered providers" do
      providers = Registry.list_providers()
      assert :anthropic in providers
    end
  end

  describe "fetch/1 with registered providers" do
    test "returns anthropic provider" do
      assert {:ok, ReqAI.Provider.Anthropic} = Registry.fetch(:anthropic)
    end
  end
end
