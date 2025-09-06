defmodule Jido.AI.Provider.OpenRouter do
  @moduledoc """
  Adapter for the OpenRouter AI provider.

  Implements the ProviderBehavior for OpenRouter's specific API.
  """
  @behaviour Jido.AI.Model.Provider.Adapter
  alias Jido.AI.Provider

  @base_url "https://openrouter.ai/api/v1"

  # List Models
  # curl https://openrouter.ai/api/v1/models

  # Get Model
  # curl https://openrouter.ai/api/v1/models/{model}/endpoints

  @provider_id :openrouter
  @provider_path "openrouter"

  @impl true
  def definition do
    %Provider{
      id: @provider_id,
      name: "OpenRouter",
      description: "OpenRouter is a unified API for multiple AI models",
      type: :proxy,
      api_base_url: "https://openrouter.ai/api/v1"
    }
  end

  @doc """
  Returns a list of models for the provider.

  This is a required function for the Provider.Adapter behaviour.
  """
  def models(opts \\ []) do
    list_models(opts)
  end

  @impl true
  @doc """
  Lists available models from local cache or API.

  ## Options
    - refresh: boolean - Whether to force refresh from API (default: false)
    - api_key: string - OpenRouter API key (optional)

  Returns a tuple with {:ok, models} on success or {:error, reason} on failure.
  """
  def list_models(opts \\ []) do
    refresh = Keyword.get(opts, :refresh, false)
    models_file = get_models_file_path()

    cond do
      # If refresh requested, fetch from API
      refresh ->
        fetch_and_cache_models(opts)

      # If local file exists, try reading from it
      File.exists?(models_file) ->
        read_models_from_cache()

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
    - api_key: string - OpenRouter API key (optional)

  Returns a tuple with {:ok, model} on success or {:error, reason} on failure.
  """
  def model(model, opts \\ []) do
    refresh = Keyword.get(opts, :refresh, false)

    # Check if we should refresh or try to get from cache first
    if refresh do
      fetch_model_from_api(model, opts)
    else
      # Try to get from cache first, fallback to API if not found
      case fetch_model_from_cache(model, opts) do
        {:ok, model} ->
          {:ok, model}

        {:error, _reason} ->
          # If not found in cache, try API
          fetch_model_from_api(model, opts)
      end
    end
  end

  @impl true
  @doc """
  Normalizes a model ID to ensure it's in the correct format for OpenRouter.

  ## Options
    - No specific options for this method

  Returns a tuple with {:ok, normalized_id} on success or {:error, reason} on failure.
  """
  def normalize(model, _opts \\ []) do
    # OpenRouter model IDs are already in the format "author/slug"
    # This method ensures the ID is properly formatted
    if String.contains?(model, "/") do
      {:ok, model}
    else
      {:error, "Invalid model ID format. Expected 'author/slug' format."}
    end
  end

  @impl true
  def base_url() do
    @base_url
  end

  @impl true
  def request_headers(opts) do
    api_key =
      Keyword.get(opts, :api_key) || Jido.AI.Keyring.get(:openrouter_api_key)

    base_headers = %{
      "HTTP-Referer" => "https://agentjido.xyz",
      "X-Title" => "Jido AI",
      "Content-Type" => "application/json"
    }

    if api_key do
      Map.put(base_headers, "Authorization", "Bearer #{api_key}")
    else
      base_headers
    end
  end

  @impl true
  def validate_model_opts(opts) do
    {:ok,
     %Jido.AI.Model{
       id: opts[:model] || "openrouter_default",
       name: opts[:model_name] || "OpenRouter Model",
       provider: :openrouter
     }}
  end

  @impl true
  @doc """
  Builds a %Jido.AI.Model{} struct from the provided options.

  This function validates the options, sets defaults, and creates a fully populated
  model struct for the OpenRouter provider.

  ## Parameters
    - opts: Keyword list of options for building the model

  ## Returns
    - {:ok, %Jido.AI.Model{}} on success
    - {:error, reason} on failure
  """
  def build(opts) do
    # Extract or generate an API key
    api_key =
      Jido.AI.Provider.Helpers.get_api_key(opts, "OPENROUTER_API_KEY", :openrouter_api_key)

    # Get model from opts
    model = Keyword.get(opts, :model)

    # Validate model
    if is_nil(model) do
      {:error, "model is required for OpenRouter models"}
    else
      # Create the model struct with all necessary fields
      model = %Jido.AI.Model{
        id: Keyword.get(opts, :id, "openrouter_#{model}"),
        name: Keyword.get(opts, :name, "OpenRouter #{model}"),
        provider: :openrouter,
        model: model,
        base_url: Keyword.get(opts, :base_url, @base_url),
        api_key: api_key,
        temperature: Keyword.get(opts, :temperature, 0.7),
        max_tokens: Keyword.get(opts, :max_tokens, 1024),
        max_retries: Keyword.get(opts, :max_retries, 0),
        architecture: %Jido.AI.Model.Architecture{
          modality: Keyword.get(opts, :modality, "text"),
          tokenizer: Keyword.get(opts, :tokenizer, "unknown"),
          instruct_type: Keyword.get(opts, :instruct_type)
        },
        description: Keyword.get(opts, :description, "OpenRouter model"),
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

  defp get_models_file_path do
    base_dir = Jido.AI.Provider.base_dir()
    provider_path = Path.join(base_dir, @provider_path)
    Path.join(provider_path, "models.json")
  end

  defp get_model_file_path(model) do
    base_dir = Jido.AI.Provider.base_dir()
    provider_path = Path.join(base_dir, @provider_path)
    model_dir = Path.join(provider_path, "models")
    Path.join(model_dir, "#{model}.json")
  end

  defp read_models_from_cache do
    case File.read(get_models_file_path()) do
      {:ok, json} ->
        case Jason.decode(json) do
          {:ok, %{"data" => models}} ->
            {:ok, process_models(models)}

          {:error, reason} ->
            {:error, "Failed to parse cached models: #{inspect(reason)}"}
        end

      {:error, reason} ->
        {:error, "Failed to read models cache: #{inspect(reason)}"}
    end
  end

  defp fetch_model_from_cache(model, opts) do
    # First try to read from the dedicated model file
    model_file = get_model_file_path(model)

    if File.exists?(model_file) do
      case File.read(model_file) do
        {:ok, json} ->
          case Jason.decode(json) do
            {:ok, model_data} ->
              {:ok, process_single_model(model_data, model)}

            {:error, reason} ->
              {:error, "Failed to parse cached model: #{inspect(reason)}"}
          end

        {:error, reason} ->
          {:error, "Failed to read model cache: #{inspect(reason)}"}
      end
    else
      # If no dedicated file exists, try to find in the models list
      case list_models(Keyword.put(opts, :refresh, false)) do
        {:ok, models} ->
          case Enum.find(models, fn model -> model.id == model end) do
            nil -> {:error, "Model not found in cache: #{model}"}
            model -> {:ok, model}
          end

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp fetch_and_cache_models(opts) do
    url = base_url() <> "/models"
    headers = request_headers(opts)

    case Req.get(url, headers: headers) do
      {:ok, %{status: 200, body: %{"data" => models}}} ->
        # Ensure cache directory exists
        models_file = get_models_file_path()
        File.mkdir_p!(Path.dirname(models_file))

        # Cache the response
        json = Jason.encode!(%{"data" => models}, pretty: true)
        File.write!(models_file, json)

        # Return processed models
        {:ok, process_models(models)}

      {:ok, %{status: status, body: body}} ->
        {:error, "API request failed with status #{status}: #{inspect(body)}"}

      {:error, reason} ->
        {:error, "Failed to fetch models: #{inspect(reason)}"}
    end
  end

  defp fetch_model_from_api(model, opts) do
    url = base_url() <> "/models/#{model}/endpoints"
    headers = request_headers(opts)

    case Req.get(url, headers: headers) do
      {:ok, %{status: 200, body: %{"data" => model_data}}} ->
        # Process the model data
        processed_model = process_single_model(model_data, model)

        # Cache the model data if requested
        if Keyword.get(opts, :save_to_cache, true) do
          cache_single_model(model, model_data)
        end

        {:ok, processed_model}

      {:ok, %{status: status, body: body}} ->
        {:error, "API request failed with status #{status}: #{inspect(body)}"}

      {:error, reason} ->
        {:error, "Failed to fetch model: #{inspect(reason)}"}
    end
  end

  defp cache_single_model(model, model_data) do
    base_dir = Jido.AI.Provider.base_dir()
    provider_path = Path.join(base_dir, @provider_path)
    model_dir = Path.join(provider_path, "models")
    model_file = Path.join(model_dir, "#{model}.json")

    # Ensure directory exists
    File.mkdir_p!(model_dir)

    # Save model to file
    json = Jason.encode!(model_data, pretty: true)
    File.write!(model_file, json)
  end

  defp process_models(models) when is_list(models) do
    Enum.map(models, fn model ->
      %{
        id: model["id"],
        name: model["name"],
        description: model["description"],
        created: model["created"],
        architecture: process_architecture(model["architecture"]),
        endpoints: process_endpoints(model["endpoints"]),
        capabilities: extract_capabilities(model),
        tier: determine_tier(model)
      }
    end)
  end

  defp process_models(_), do: []

  defp process_single_model(model_data, model) when is_map(model_data) do
    # Extract model details from the endpoints response
    %{
      id: model,
      name: model_data["name"] || model,
      description: model_data["description"] || "",
      created: model_data["created"],
      architecture: process_architecture(model_data["architecture"]),
      endpoints: process_endpoints(model_data["endpoints"] || [model_data]),
      capabilities: extract_capabilities(model_data),
      tier: determine_tier(model_data)
    }
  end

  defp process_architecture(architecture) when is_map(architecture) do
    %{
      instruct_type: architecture["instruct_type"],
      modality: architecture["modality"],
      tokenizer: architecture["tokenizer"]
    }
  end

  defp process_architecture(_), do: %{}

  defp process_endpoints(endpoints) when is_list(endpoints) do
    Enum.map(endpoints, fn endpoint ->
      %{
        name: endpoint["name"],
        provider_name: endpoint["provider_name"],
        context_length: endpoint["context_length"],
        max_completion_tokens: endpoint["max_completion_tokens"],
        max_prompt_tokens: endpoint["max_prompt_tokens"],
        pricing: process_pricing(endpoint["pricing"]),
        quantization: endpoint["quantization"],
        supported_parameters: endpoint["supported_parameters"] || []
      }
    end)
  end

  defp process_endpoints(_), do: []

  defp process_pricing(pricing) when is_map(pricing) do
    %{
      completion: pricing["completion"],
      image: pricing["image"],
      prompt: pricing["prompt"],
      request: pricing["request"]
    }
  end

  defp process_pricing(_), do: %{}

  # Extract capabilities based on the model's architecture and other properties
  defp extract_capabilities(model) do
    modality = get_in(model, ["architecture", "modality"])

    %{
      # Assuming all OpenRouter models support chat
      chat: true,
      # OpenRouter doesn't typically expose embedding models
      embedding: false,
      image: String.contains?(to_string(modality), "image"),
      vision: String.contains?(to_string(modality), "image"),
      multimodal: String.contains?(to_string(modality), "+"),
      audio: String.contains?(to_string(modality), "audio"),
      # Heuristic for code capability
      code: model["name"] =~ ~r/code|codex|gpt-4|claude-3|llama-3/i
    }
  end

  # Determine the tier based on model characteristics
  defp determine_tier(model) do
    cond do
      # Advanced tier for top models
      model["name"] =~ ~r/gpt-4|claude-3.*opus|gemini-.*pro|mistral-.*large/i ->
        %{value: :advanced, description: "High-performance model"}

      # Standard tier for mid-range models
      model["name"] =~ ~r/gpt-3\.5|claude-3.*sonnet|gemini-.*flash|llama-3.*70b/i ->
        %{value: :standard, description: "Balanced performance and cost"}

      # Basic tier for everything else
      true ->
        %{value: :basic, description: "Entry-level model"}
    end
  end
end
