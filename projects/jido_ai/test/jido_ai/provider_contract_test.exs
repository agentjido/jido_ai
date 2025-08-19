defmodule Jido.AI.ProviderContractTest do
  @moduledoc """
  Tests that the Base macro generates working provider modules.
  """

  use ExUnit.Case, async: true

  # Create a minimal stub provider for contract testing
  defmodule StubProvider do
    use Jido.AI.Provider.Macro,
      json: "stub_test.json",
      base_url: "https://example.com",
      id: "stub_provider",
      name: "Stub Provider",
      env: ["STUB_API_KEY"]
  end

  describe "Base macro contract" do
    test "generates provider_info with correct structure" do
      info = StubProvider.provider_info()

      assert info.id == :stub_provider
      assert info.name == "Stub Provider"
      assert info.base_url == "https://example.com"
      assert info.env == [:STUB_API_KEY]
      assert is_map(info.models)
    end

    test "generates api_url function" do
      assert StubProvider.api_url() == "https://example.com"
    end

    test "implements generate_text/3 callback" do
      assert function_exported?(StubProvider, :generate_text, 3)
    end

    test "implements stream_text/3 callback" do
      assert function_exported?(StubProvider, :stream_text, 3)
    end
  end
end
