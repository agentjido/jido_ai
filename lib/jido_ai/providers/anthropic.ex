defmodule Jido.AI.Provider.Anthropic do
  @moduledoc """
  Adapter for the Anthropic AI provider.

  Implements the ProviderBehavior for Anthropic's specific API.
  """
  @behaviour Jido.AI.Model.Provider.Adapter
  alias Jido.AI.Provider
  alias Jido.AI.Provider.Helpers
  alias Jido.AI.Model

  @base_url "https://api.anthropic.com/v1"
  @api_version "2023-06-01"

  # List models
  # curl https://api.anthropic.com/v1/models \
  #    --header "x-api-key: $ANTHROPIC_API_KEY" \
  #    --header "anthropic-version: 2023-06-01"

  # Retrieve Model
  # curl https://api.anthropic.com/v1/models/{model_id} \
  # --header "x-api-key: $ANTHROPIC_API_KEY" \
  # --header "anthropic-version: 2023-06-01"

  @provider_id :anthropic
  @provider_path "anthropic"

  @impl true
  def request_headers(opts) do
    api_key = Helpers.get_api_key(opts, "ANTHROPIC_API_KEY", :anthropic_api_key)
    api_version = Keyword.get(opts, :api_version, @api_version)

    base_headers = %{
      "Content-Type" => "application/json",
      "anthropic-version" => api_version
    }

    if api_key do
      Map.put(base_headers, "x-api-key", api_key)
    else
      base_headers
    end
  end

  @impl true
  def definition do
    %Provider{
      id: @provider_id,
      name: "Anthropic",
      description: "Anthropic's API provides access to Claude models",
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
    - api_key: string - Anthropic API key (optional)

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
    - api_key: string - Anthropic API key (optional)

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
  Normalizes a model ID to ensure it's in the correct format for Anthropic.

  ## Options
    - No specific options for this method

  Returns a tuple with {:ok, normalized_id} on success or {:error, reason} on failure.
  """
  def normalize(model_id, _opts \\ []) do
    # Anthropic model IDs are simple strings like "claude-3-opus-20240229"
    # This method ensures the ID is properly formatted
    if String.match?(model_id, ~r/^claude-[a-zA-Z0-9\-]+$/) do
      {:ok, model_id}
    else
      {:error, "Invalid model ID format for Anthropic. Expected 'claude-*' format."}
    end
  end

  @impl true
  def base_url() do
    @base_url
  end

  @impl true
  def validate_model_opts(opts) do
    %Jido.AI.Model{
      id: opts[:model_id],
      name: opts[:model_name],
      description: opts[:model_description]
      # capabilities: opts[:model_capabilities],
      # tier: opts[:model_tier]
    }
  end

  @impl true
  @doc """
  Builds a %Jido.AI.Model{} struct from the provided options.

  This function validates the options, sets defaults, and creates a fully populated
  model struct for the Anthropic provider.

  ## Parameters
    - opts: Keyword list of options for building the model

  ## Returns
    - {:ok, %Jido.AI.Model{}} on success
    - {:error, reason} on failure
  """
  def build(opts) do
    # Extract or generate an API key
    api_key = Helpers.get_api_key(opts, "ANTHROPIC_API_KEY", :anthropic_api_key)

    # Get model_id from opts
    model_id = Keyword.get(opts, :model_id)

    # Validate model_id
    if is_nil(model_id) do
      {:error, "model_id is required for Anthropic models"}
    else
      # Create the model struct with all necessary fields
      model = %Model{
        id: Keyword.get(opts, :id, "anthropic_#{model_id}"),
        name: Keyword.get(opts, :name, "Anthropic #{model_id}"),
        provider: :anthropic,
        model_id: model_id,
        base_url: @base_url,
        api_key: api_key,
        temperature: Keyword.get(opts, :temperature, 0.7),
        max_tokens: Keyword.get(opts, :max_tokens, 1024),
        max_retries: Keyword.get(opts, :max_retries, 0),
        architecture: %Model.Architecture{
          modality: Keyword.get(opts, :modality, "text"),
          tokenizer: Keyword.get(opts, :tokenizer, "unknown"),
          instruct_type: Keyword.get(opts, :instruct_type)
        },
        description: Keyword.get(opts, :description, "Anthropic Claude model"),
        created: System.system_time(:second),
        endpoints: []
      }

      {:ok, model}
    end
  end

  @impl true
  def transform_model_to_clientmodel(_client_atom, _model) do
    {:error, "Not implemented yet"}
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
        name: model["display_name"] || model["name"] || model["id"],
        description: model["description"] || "",
        created: model["created_at"] || model["created"],
        max_tokens: model["max_tokens_to_sample"],
        context_length: model["context_window"],
        capabilities: extract_capabilities(model),
        tier: determine_tier(model),
        provider: @provider_id
      }
    end)
  end

  defp process_models(_), do: []

  defp process_single_model(model_data, model_id) when is_map(model_data) do
    %{
      id: model_data["id"] || model_id,
      name: model_data["display_name"] || model_data["name"] || model_data["id"] || model_id,
      description: model_data["description"] || "",
      created: model_data["created_at"] || model_data["created"],
      max_tokens: model_data["max_tokens_to_sample"],
      context_length: model_data["context_window"],
      capabilities: extract_capabilities(model_data),
      tier: determine_tier(model_data),
      provider: @provider_id
    }
  end

  defp process_single_model(_, model_id),
    do: %{id: model_id, name: model_id, provider: @provider_id}

  # Extract capabilities based on the model's name and other properties
  defp extract_capabilities(model) do
    model_id = model["id"] || ""

    %{
      # All Claude models support chat
      chat: true,
      # Anthropic doesn't offer embedding models
      embedding: false,
      # Claude 3 models support image input
      image: String.contains?(model_id, "opus") || String.contains?(model_id, "sonnet"),
      # Claude 3 models support vision
      vision: String.contains?(model_id, "opus") || String.contains?(model_id, "sonnet"),
      # Claude 3 models are multimodal
      multimodal: String.contains?(model_id, "opus") || String.contains?(model_id, "sonnet"),
      # Anthropic doesn't offer audio models
      audio: false,
      # All Claude models have good code capabilities
      code: true
    }
  end

  # Determine the tier based on model characteristics
  defp determine_tier(model) do
    model_id = model["id"] || ""

    cond do
      # Advanced tier for top models
      String.contains?(model_id, "opus") ->
        %{value: :advanced, description: "High-performance model"}

      # Standard tier for mid-range models
      String.contains?(model_id, "sonnet") ->
        %{value: :standard, description: "Balanced performance and cost"}

      # Basic tier for everything else
      true ->
        %{value: :basic, description: "Entry-level model"}
    end
  end
end
