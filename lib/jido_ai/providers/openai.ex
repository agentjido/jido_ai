defmodule Jido.AI.Provider.OpenAI do
  @moduledoc """
  Adapter for the OpenAI AI provider.

  Implements the ProviderBehavior for OpenAI's specific API.
  """
  @behaviour Jido.AI.Model.Provider.Adapter
  alias Jido.AI.Provider
  alias Jido.AI.Provider.Helpers

  @base_url "https://api.openai.com/v1"

  # list models: https://api.openai.com/v1/models
  # retrieve model: https://api.openai.com/v1/models/{model}

  @provider_id :openai
  @provider_path "openai"

  @impl true
  def definition do
    %Provider{
      id: @provider_id,
      name: "OpenAI",
      description: "OpenAI's API provides access to GPT models, DALL-E, and more",
      type: :direct,
      api_base_url: @base_url,
      requires_api_key: true
    }
  end

  @impl true
  @doc """
  Lists available models from local cache or API.

  ## Options
    - refresh: boolean - Whether to force refresh from API (default: false)
    - api_key: string - OpenAI API key (optional)

  Returns a tuple with {:ok, models} on success or {:error, reason} on failure.
  """
  def list_models(opts \\ []) do
    refresh = Keyword.get(opts, :refresh, false)
    models_file = Helpers.get_models_file_path(@provider_path)

    cond do
      # If refresh requested, fetch from API
      refresh ->
        fetch_and_cache_models(opts)

      # If local file exists, try reading from it
      File.exists?(models_file) ->
        Helpers.read_models_from_cache(@provider_path, &process_models/1)

      # Otherwise fetch from API
      true ->
        fetch_and_cache_models(opts)
    end
  end

  @impl true
  @doc """
  Fetches a specific model by ID from the API or cache.

  ## Options
    - refresh: boolean - Whether to force refresh from API (default: false)
    - api_key: string - OpenAI API key (optional)

  Returns a tuple with {:ok, model} on success or {:error, reason} on failure.
  """
  def model(model_id, opts \\ []) do
    refresh = Keyword.get(opts, :refresh, false)

    # Check if we should refresh or try to get from cache first
    if refresh do
      fetch_model_from_api(model_id, opts)
    else
      # Try to get from cache first, fallback to API if not found
      case Helpers.fetch_model_from_cache(@provider_path, model_id, opts, &process_single_model/2) do
        {:ok, model} ->
          {:ok, model}

        {:error, _reason} ->
          # If not found in cache, try API
          fetch_model_from_api(model_id, opts)
      end
    end
  end

  @impl true
  @doc """
  Normalizes a model ID to ensure it's in the correct format for OpenAI.

  ## Options
    - No specific options for this method

  Returns a tuple with {:ok, normalized_id} on success or {:error, reason} on failure.
  """
  def normalize(model_id, _opts \\ []) do
    # OpenAI model IDs are simple strings like "gpt-4" or "text-embedding-ada-002"
    # This method ensures the ID is properly formatted
    if String.match?(model_id, ~r/^[a-zA-Z0-9\-]+$/) do
      {:ok, model_id}
    else
      {:error, "Invalid model ID format for OpenAI."}
    end
  end

  @impl true
  def base_url() do
    @base_url
  end

  @impl true
  def request_headers(opts) do
    api_key = Helpers.get_api_key(opts, "OPENAI_API_KEY", :openai_api_key)

    base_headers = %{
      "Content-Type" => "application/json"
    }

    if api_key do
      Map.put(base_headers, "Authorization", "Bearer #{api_key}")
    else
      base_headers
    end
  end

  # Private helper functions

  defp fetch_and_cache_models(opts) do
    provider = definition()
    url = base_url() <> "/models"
    headers = request_headers(opts)

    Helpers.fetch_and_cache_models(provider, url, headers, @provider_path, &process_models/1)
  end

  defp fetch_model_from_api(model_id, opts) do
    provider = definition()
    url = base_url() <> "/models/#{model_id}"
    headers = request_headers(opts)

    # Ensure the models directory exists
    base_dir = Jido.AI.Provider.base_dir()
    provider_dir = Path.join(base_dir, @provider_path)
    model_dir = Path.join(provider_dir, "models")

    # Create the models directory if it doesn't exist
    unless File.exists?(model_dir) do
      File.mkdir_p!(model_dir)
    end

    Helpers.fetch_model_from_api(
      provider,
      url,
      headers,
      model_id,
      @provider_path,
      &process_single_model/2,
      opts
    )
  end

  defp process_models(models) when is_list(models) do
    Enum.map(models, fn model ->
      %{
        id: model["id"],
        name: model["id"],
        description: model["description"] || "",
        created: model["created"],
        owned_by: model["owned_by"],
        capabilities: extract_capabilities(model),
        tier: determine_tier(model)
      }
    end)
  end

  defp process_models(_), do: []

  defp process_single_model(model_data, model_id) when is_map(model_data) do
    %{
      id: model_data["id"] || model_id,
      name: model_data["id"] || model_id,
      description: model_data["description"] || "",
      created: model_data["created"],
      owned_by: model_data["owned_by"],
      capabilities: extract_capabilities(model_data),
      tier: determine_tier(model_data)
    }
  end

  defp process_single_model(_, model_id), do: %{id: model_id, name: model_id}

  # Extract capabilities based on the model's name and other properties
  defp extract_capabilities(model) do
    model_id = model["id"] || ""

    %{
      chat: String.contains?(model_id, "gpt") || String.contains?(model_id, "turbo"),
      embedding: String.contains?(model_id, "embedding"),
      image: String.contains?(model_id, "dall-e"),
      vision: String.contains?(model_id, "vision"),
      multimodal: String.contains?(model_id, "vision") || String.contains?(model_id, "gpt-4"),
      audio: String.contains?(model_id, "whisper"),
      code: String.contains?(model_id, "gpt-4") || String.contains?(model_id, "codex")
    }
  end

  # Determine the tier based on model characteristics
  defp determine_tier(model) do
    model_id = model["id"] || ""

    cond do
      # Advanced tier for top models
      String.contains?(model_id, "gpt-4") ->
        %{value: :advanced, description: "High-performance model"}

      # Standard tier for mid-range models
      String.contains?(model_id, "gpt-3.5") ->
        %{value: :standard, description: "Balanced performance and cost"}

      # Basic tier for everything else
      true ->
        %{value: :basic, description: "Entry-level model"}
    end
  end
end
