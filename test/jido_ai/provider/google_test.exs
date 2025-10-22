defmodule Jido.AI.Provider.GoogleTest do
  use ExUnit.Case, async: false
  use Mimic

  alias Jido.AI.Provider.Google

  @test_api_key "test-api-key"

  setup do
    tmp_dir = System.tmp_dir!() |> Path.join("jido_ai_test_#{:rand.uniform(9999)}")
    File.mkdir_p!(tmp_dir)

    Mimic.copy(Jido.AI.Provider)
    Mimic.copy(Req)

    Jido.AI.Provider
    |> stub(:base_dir, fn -> tmp_dir end)

    on_exit(fn ->
      File.rm_rf!(tmp_dir)
    end)

    {:ok, %{tmp_dir: tmp_dir}}
  end

  test "definition/0 returns the provider definition" do
    definition = Google.definition()
    assert definition.id == :google
    assert definition.name == "Google"
  end

  test "request_headers/2 returns base headers" do
    # API key handling is now done by ReqLLM internally
    # This function returns base headers for compatibility
    headers = Google.request_headers(api_key: @test_api_key)

    # Should not include API key - that's handled by ReqLLM
    refute Map.has_key?(headers, "x-goog-api-key")

    # But should have base headers
    assert is_map(headers)
  end

  test "build/1 creates a valid model struct with required parameters" do
    model_data = %{
      "name" => "models/gemini-2.0-flash",
      "displayName" => "Gemini 2.0 Flash",
      "description" => "Google's Flash model",
      "inputTokenLimit" => 30_720,
      "outputTokenLimit" => 2048,
      "supportedGenerationMethods" => ["generateContent", "countTokens"],
      "temperature" => 0.7,
      "topK" => 1,
      "topP" => 1,
      "version" => "001"
    }

    model_data = Map.put(model_data, "api_key", @test_api_key)

    {:ok, model} = Google.build(model_data)

    assert model.id == "gemini-2.0-flash"
    assert model.name == "Gemini 2.0 Flash"
    assert model.provider == :google
    assert model.api_key == @test_api_key
  end

  test "build/1 errors when model is missing" do
    model_data = Map.put(%{}, "api_key", @test_api_key)
    assert {:error, _} = Google.build(model_data)
  end

  test "list_models/1 fetches models from Registry" do
    # Now delegates to Model Registry which gets models from ReqLLM
    # The registry should have Google models available
    assert {:ok, models} = Google.list_models(api_key: @test_api_key)

    # Should return some models from the registry
    assert is_list(models)
    assert length(models) > 0

    # Models should be properly formatted
    model = List.first(models)
    assert is_struct(model, Jido.AI.Model)
    assert model.provider == :google

    # Should have at least some Gemini models
    gemini_models = Enum.filter(models, fn m -> String.contains?(m.id, "gemini") end)
    assert length(gemini_models) > 0
  end

  test "normalize/2 normalizes Gemini model IDs" do
    # Strips "models/" prefix from Google model format
    assert {:ok, "gemini-2.0-flash"} = Google.normalize("models/gemini-2.0-flash", [])
    assert {:ok, "gemini-2.0-flash-lite"} = Google.normalize("models/gemini-2.0-flash-lite", [])

    # Accepts models without prefix
    assert {:ok, "gemini-2.5-flash"} = Google.normalize("gemini-2.5-flash", [])

    # Note: normalize doesn't validate model existence, just normalizes format
    assert {:ok, "invalid-model"} = Google.normalize("invalid-model", [])
  end
end
