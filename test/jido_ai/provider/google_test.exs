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

  test "request_headers/2 includes proper API key in headers" do
    headers = Google.request_headers(api_key: @test_api_key)
    assert headers["x-goog-api-key"] == @test_api_key
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

  test "list_models/1 fetches and processes models from API" do
    models_response = %{
      "models" => [
        %{
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
      ]
    }

    Req
    |> expect(:get, fn url, opts ->
      assert String.contains?(url, "generativelanguage.googleapis.com")
      assert Keyword.get(opts, :auth) == nil
      {:ok, %Req.Response{status: 200, body: models_response}}
    end)

    {:ok, [model]} = Google.list_models(api_key: @test_api_key)
    assert model.id == "gemini-2.0-flash"
    assert model.name == "Gemini 2.0 Flash"
    assert model.provider == :google
  end

  test "normalize/2 validates proper Gemini model IDs" do
    assert {:ok, "gemini-2.0-flash"} = Google.normalize("models/gemini-2.0-flash", [])
    assert {:ok, "gemini-2.0-flash-lite"} = Google.normalize("models/gemini-2.0-flash-lite", [])
    assert {:error, _} = Google.normalize("invalid-model", [])
  end
end
