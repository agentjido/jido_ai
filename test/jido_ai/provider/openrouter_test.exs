defmodule Jido.AI.Provider.OpenRouterTest do
  use ExUnit.Case, async: false
  use Mimic

  alias Jido.AI.Provider.OpenRouter
  alias Jido.AI.Keyring

  @moduletag :capture_log
  @moduletag :tmp_dir

  setup :set_mimic_global
  setup :verify_on_exit!

  setup %{tmp_dir: tmp_dir} do
    # Mock the base_dir function to return our test directory
    original_base_dir = Application.get_env(:jido_ai, :provider_base_dir)
    Application.put_env(:jido_ai, :provider_base_dir, tmp_dir)

    # Create provider directory structure
    provider_dir = Path.join(tmp_dir, "openrouter")
    models_dir = Path.join(provider_dir, "models")
    File.mkdir_p!(provider_dir)
    File.mkdir_p!(models_dir)

    # Mock Dotenvy.source! to return an empty map by default
    stub(Dotenvy, :source!, fn _sources -> %{} end)

    # Mock Dotenvy.env! to raise by default
    stub(Dotenvy, :env!, fn _key, _type -> raise "Not found" end)

    # Mock Keyring.get to return nil by default
    stub(Keyring, :get, fn _key -> nil end)

    on_exit(fn ->
      # Restore the original base_dir
      if original_base_dir do
        Application.put_env(:jido_ai, :provider_base_dir, original_base_dir)
      else
        Application.delete_env(:jido_ai, :provider_base_dir)
      end
    end)

    {:ok, %{test_dir: tmp_dir}}
  end

  describe "definition/0" do
    test "returns provider definition" do
      provider = OpenRouter.definition()
      assert provider.id == :openrouter
      assert provider.name == "OpenRouter"
      assert provider.type == :proxy
      assert provider.api_base_url == "https://openrouter.ai/api/v1"
    end
  end

  describe "normalize/2" do
    test "accepts valid model IDs" do
      assert {:ok, "anthropic/claude-3-opus"} = OpenRouter.normalize("anthropic/claude-3-opus")
      assert {:ok, "google/gemini-pro"} = OpenRouter.normalize("google/gemini-pro")
    end

    test "rejects invalid model IDs" do
      assert {:error, _} = OpenRouter.normalize("invalid-model-id")
      assert {:error, _} = OpenRouter.normalize("")
    end
  end

  describe "request_headers/2" do
    test "includes required headers" do
      headers = OpenRouter.request_headers([])

      assert headers["HTTP-Referer"] == "https://agentjido.xyz"
      assert headers["X-Title"] == "Jido AI"
      assert headers["Content-Type"] == "application/json"
    end

    test "adds API key from options" do
      headers = OpenRouter.request_headers(api_key: "test-key")
      assert headers["Authorization"] == "Bearer test-key"
    end

    test "adds API key from environment" do
      # Mock Keyring.get to return our test key
      expect(Keyring, :get, fn :openrouter_api_key -> "env-key" end)

      headers = OpenRouter.request_headers([])
      assert headers["Authorization"] == "Bearer env-key"
    end
  end

  describe "list_models/1" do
    test "fetches and processes models from API" do
      mock_models = %{
        "data" => [
          %{
            "id" => "anthropic/claude-3-opus",
            "name" => "Claude 3 Opus",
            "description" => "Most powerful Claude model",
            "created" => 1_234_567_890,
            "architecture" => %{
              "modality" => "text",
              "instruct_type" => "claude",
              "tokenizer" => "claude"
            },
            "endpoints" => [
              %{
                "name" => "claude-3-opus",
                "provider_name" => "anthropic",
                "context_length" => 200_000,
                "pricing" => %{
                  "prompt" => 0.015,
                  "completion" => 0.075
                }
              }
            ]
          }
        ]
      }

      Req
      |> expect(:get, fn _url, _opts ->
        {:ok, %{status: 200, body: mock_models}}
      end)

      assert {:ok, models} = OpenRouter.list_models(refresh: true)
      assert length(models) == 1
      model = List.first(models)
      assert model.id == "anthropic/claude-3-opus"
      assert model.name == "Claude 3 Opus"
      assert model.capabilities.chat == true
    end

    test "handles API errors gracefully" do
      Req
      |> expect(:get, fn _url, _opts ->
        {:error, "Connection failed"}
      end)

      assert {:error, _} = OpenRouter.list_models(refresh: true)
    end
  end

  describe "model/2" do
    test "fetches specific model details", %{test_dir: tmp_dir} do
      # Create the nested directory structure for the model
      model = "anthropic/claude-3-opus"
      model_dir_path = Path.join([tmp_dir, "openrouter", "models", Path.dirname(model)])
      File.mkdir_p!(model_dir_path)

      mock_model = %{
        "data" => %{
          "id" => model,
          "name" => "Claude 3 Opus",
          "description" => "Most powerful Claude model",
          "created" => 1_234_567_890,
          "architecture" => %{
            "modality" => "text",
            "instruct_type" => "claude"
          },
          "endpoints" => [
            %{
              "name" => "claude-3-opus",
              "provider_name" => "anthropic",
              "context_length" => 200_000
            }
          ]
        }
      }

      Req
      |> expect(:get, fn _url, _opts ->
        {:ok, %{status: 200, body: mock_model}}
      end)

      assert {:ok, model_result} = OpenRouter.model(model, refresh: true)
      assert model_result.name == "Claude 3 Opus"
      assert model_result.capabilities.chat == true
      assert model_result.id == model
    end

    test "handles model fetch errors" do
      Req
      |> expect(:get, fn _url, _opts ->
        {:ok, %{status: 404, body: %{"error" => "Model not found"}}}
      end)

      assert {:error, _} = OpenRouter.model("invalid/model", refresh: true)
    end
  end
end
