defmodule ReqAI.ProviderTest do
  use ExUnit.Case, async: true
  doctest ReqAI.Provider

  alias ReqAI.Provider

  describe "new/4" do
    test "creates provider with required fields" do
      provider = Provider.new(:test, "Test Provider", "https://api.test.com")

      assert provider.id == :test
      assert provider.name == "Test Provider"
      assert provider.base_url == "https://api.test.com"
      assert provider.models == %{}
    end

    test "creates provider with models" do
      model = ReqAI.Model.new(:test_provider, "test-model")
      models = %{"model1" => model}
      provider = Provider.new(:test, "Test Provider", "https://api.test.com", models)

      assert provider.models == models
    end
  end

  describe "struct creation" do
    test "has default empty models map" do
      provider = %Provider{id: :test, name: "Test", base_url: "https://test.com"}
      assert provider.models == %{}
    end
  end
end
