defmodule JidoTest.AI.Provider.HelpersTest do
  use ExUnit.Case, async: false
  alias Jido.AI.Provider.Helpers
  alias Jido.AI.Keyring

  import Mimic

  @moduletag :capture_log
  @moduletag :tmp_dir

  setup :verify_on_exit!
  setup :set_mimic_global

  setup %{tmp_dir: tmp_dir} do
    # Mock the base_dir function to return our test directory
    original_base_dir = Application.get_env(:jido_ai, :provider_base_dir)
    Application.put_env(:jido_ai, :provider_base_dir, tmp_dir)

    # Create provider directory structure
    provider_dir = Path.join(tmp_dir, "test_provider")
    models_dir = Path.join(provider_dir, "models")
    File.mkdir_p!(provider_dir)
    File.mkdir_p!(models_dir)

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

  describe "get_models_file_path/1" do
    test "returns the correct path" do
      path = Helpers.get_models_file_path("test_provider")
      assert String.ends_with?(path, "test_provider/models.json")
    end
  end

  describe "get_model_file_path/2" do
    test "returns the correct path" do
      path = Helpers.get_model_file_path("test_provider", "test_model")
      assert String.ends_with?(path, "test_provider/models/test_model.json")
    end
  end

  describe "read_models_from_cache/2" do
    test "reads models from cache when available", %{test_dir: test_dir} do
      # Create a cache file
      cache_file = Path.join([test_dir, "test_provider", "models.json"])

      mock_models = %{
        "data" => [
          %{
            "id" => "test_model",
            "name" => "Test Model",
            "description" => "A test model"
          }
        ]
      }

      File.write!(cache_file, Jason.encode!(mock_models))

      # Define a simple process function
      process_fn = fn models ->
        Enum.map(models, fn model ->
          %{id: model["id"], name: model["name"], description: model["description"]}
        end)
      end

      {:ok, models} = Helpers.read_models_from_cache("test_provider", process_fn)

      assert length(models) == 1
      model = List.first(models)
      assert model.id == "test_model"
      assert model.name == "Test Model"
      assert model.description == "A test model"
    end

    test "handles different response formats", %{test_dir: test_dir} do
      # Create a cache file with a different format
      cache_file = Path.join([test_dir, "test_provider", "models.json"])

      # Format without "data" wrapper
      mock_models = [
        %{
          "id" => "test_model",
          "name" => "Test Model",
          "description" => "A test model"
        }
      ]

      File.write!(cache_file, Jason.encode!(mock_models))

      # Define a simple process function
      process_fn = fn models ->
        Enum.map(models, fn model ->
          %{id: model["id"], name: model["name"], description: model["description"]}
        end)
      end

      {:ok, models} = Helpers.read_models_from_cache("test_provider", process_fn)

      assert length(models) == 1
      model = List.first(models)
      assert model.id == "test_model"
      assert model.name == "Test Model"
    end

    test "returns error when cache file doesn't exist" do
      process_fn = fn models -> models end
      assert {:error, _} = Helpers.read_models_from_cache("nonexistent_provider", process_fn)
    end

    test "returns error when cache file is invalid JSON", %{test_dir: test_dir} do
      # Create an invalid cache file
      cache_file = Path.join([test_dir, "test_provider", "models.json"])

      File.write!(cache_file, "invalid json")

      process_fn = fn models -> models end
      assert {:error, _} = Helpers.read_models_from_cache("test_provider", process_fn)
    end
  end

  describe "fetch_model_from_cache/4" do
    test "reads model from dedicated cache file", %{test_dir: test_dir} do
      model_id = "test_model"

      # Create a cache file for the specific model
      cache_file = Path.join([test_dir, "test_provider", "models", "#{model_id}.json"])

      mock_model = %{
        "name" => "Test Model",
        "description" => "A test model"
      }

      File.write!(cache_file, Jason.encode!(mock_model))

      # Define a simple process function
      process_fn = fn model_data, id ->
        %{id: id, name: model_data["name"], description: model_data["description"]}
      end

      {:ok, model_result} = Helpers.fetch_model_from_cache("test_provider", model_id, [], process_fn)

      assert model_result.id == model_id
      assert model_result.name == "Test Model"
      assert model_result.description == "A test model"
    end

    test "returns error when model file doesn't exist and models list is unavailable" do
      process_fn = fn model_data, _id -> model_data end

      assert {:error, _} =
               Helpers.fetch_model_from_cache(
                 "nonexistent_provider",
                 "nonexistent_model",
                 [],
                 process_fn
               )
    end
  end

  describe "fetch_and_cache_models/5" do
    test "fetches models from API and caches them", %{test_dir: test_dir} do
      provider = %Jido.AI.Provider{id: :test_provider, name: "Test Provider"}
      url = "https://api.example.com/models"
      headers = %{"Authorization" => "Bearer test-token"}

      mock_models = %{
        "data" => [
          %{
            "id" => "test_model",
            "name" => "Test Model",
            "description" => "A test model"
          }
        ]
      }

      # Mock the Req.get function
      expect(Req, :get, fn ^url, [headers: ^headers] ->
        {:ok, %{status: 200, body: mock_models}}
      end)

      # Define a simple process function
      process_fn = fn models ->
        Enum.map(models, fn model ->
          %{id: model["id"], name: model["name"], description: model["description"]}
        end)
      end

      {:ok, models} =
        Helpers.fetch_and_cache_models(provider, url, headers, "test_provider", process_fn)

      assert length(models) == 1
      model = List.first(models)
      assert model.id == "test_model"
      assert model.name == "Test Model"

      # Verify the model was cached
      cache_file = Path.join([test_dir, "test_provider", "models.json"])
      assert File.exists?(cache_file)
    end

    test "handles API errors gracefully" do
      provider = %Jido.AI.Provider{id: :test_provider, name: "Test Provider"}
      url = "https://api.example.com/models"
      headers = %{"Authorization" => "Bearer test-token"}

      # Mock the Req.get function to return an error
      expect(Req, :get, fn ^url, [headers: ^headers] ->
        {:ok, %{status: 401, body: %{"error" => "Unauthorized"}}}
      end)

      process_fn = fn models -> models end

      assert {:error, _} =
               Helpers.fetch_and_cache_models(provider, url, headers, "test_provider", process_fn)
    end
  end

  describe "fetch_model_from_api/7" do
    test "fetches a model from API and caches it", %{test_dir: test_dir} do
      provider = %Jido.AI.Provider{id: :test_provider, name: "Test Provider"}
      url = "https://api.example.com/models/test_model"
      headers = %{"Authorization" => "Bearer test-token"}
      model_id = "test_model"

      mock_model = %{
        "data" => %{
          "name" => "Test Model",
          "description" => "A test model"
        }
      }

      # Mock the Req.get function
      expect(Req, :get, fn ^url, [headers: ^headers] ->
        {:ok, %{status: 200, body: mock_model}}
      end)

      # Define a simple process function
      process_fn = fn model_data, id ->
        %{id: id, name: model_data["name"], description: model_data["description"]}
      end

      {:ok, model_result} =
        Helpers.fetch_model_from_api(
          provider,
          url,
          headers,
          model_id,
          "test_provider",
          process_fn
        )

      assert model_result.id == model_id
      assert model_result.name == "Test Model"
      assert model_result.description == "A test model"

      # Verify the model was cached
      cache_file = Path.join([test_dir, "test_provider", "models", "#{model_id}.json"])
      assert File.exists?(cache_file)
    end

    test "handles API errors gracefully" do
      provider = %Jido.AI.Provider{id: :test_provider, name: "Test Provider"}
      url = "https://api.example.com/models/test_model"
      headers = %{"Authorization" => "Bearer test-token"}
      model_id = "test_model"

      # Mock the Req.get function to return an error
      expect(Req, :get, fn ^url, [headers: ^headers] ->
        {:ok, %{status: 404, body: %{"error" => "Model not found"}}}
      end)

      process_fn = fn model_data, _id -> model_data end

      assert {:error, _} =
               Helpers.fetch_model_from_api(
                 provider,
                 url,
                 headers,
                 model_id,
                 "test_provider",
                 process_fn
               )
    end
  end

  describe "get_api_key/3" do
    setup do
      # Save the original API key value
      original_key = Keyring.get(:test_key)
      original_env = System.get_env("TEST_API_KEY")

      # Clear the API key for testing
      Keyring.set_session_value(:test_key, nil)
      System.delete_env("TEST_API_KEY")

      on_exit(fn ->
        # Restore the original API key after tests
        if original_key, do: Keyring.set_session_value(:test_key, original_key)
        if original_env, do: System.put_env("TEST_API_KEY", original_env)
      end)

      :ok
    end

    test "returns API key from opts when available" do
      assert "opts-key" == Helpers.get_api_key([api_key: "opts-key"], "TEST_API_KEY", :test_key)
    end

    test "returns API key from Keyring when available" do
      Keyring.set_session_value(:test_key, "keyring-key")
      assert "keyring-key" == Helpers.get_api_key([], "TEST_API_KEY", :test_key)
    end

    test "returns API key from environment when available" do
      System.put_env("TEST_API_KEY", "env-key")
      assert "env-key" == Helpers.get_api_key([], "TEST_API_KEY", :test_key)
    end

    test "returns nil when no API key is available" do
      assert nil == Helpers.get_api_key([], "TEST_API_KEY", :test_key)
    end

    test "prioritizes API key from opts over Keyring and environment" do
      Keyring.set_session_value(:test_key, "keyring-key")
      System.put_env("TEST_API_KEY", "env-key")
      assert "opts-key" == Helpers.get_api_key([api_key: "opts-key"], "TEST_API_KEY", :test_key)
    end

    test "prioritizes API key from Keyring over environment" do
      Keyring.set_session_value(:test_key, "keyring-key")
      System.put_env("TEST_API_KEY", "env-key")
      assert "keyring-key" == Helpers.get_api_key([], "TEST_API_KEY", :test_key)
    end
  end
end
