defmodule Jido.AI.Provider.Google do
  @moduledoc """
  Adapter for the Google Gemini API provider.

  Implements the ProviderBehavior for Google's OpenAI-compatible API.
  """
  @behaviour Jido.AI.Model.Provider.Adapter
  alias Jido.AI.Provider

  @base_url "https://generativelanguage.googleapis.com/v1beta/models/"

  # List Models
  # curl https://generativelanguage.googleapis.com/v1beta/models

  # Get Model
  # curl https://generativelanguage.googleapis.com/v1beta/models/{model}

  @models %{
    "gemini-2.5-pro-exp-03-25" => %{
      name: "Gemini 2.5 Pro Experimental",
      description: "Enhanced thinking and reasoning, multimodal understanding, advanced coding",
      modality: "audio+image+video+text->text",
      max_tokens: 2048,
      temperature: 0.7
    },
    "gemini-2.0-flash" => %{
      name: "Gemini 2.0 Flash",
      description:
        "Next generation features, speed, thinking, realtime streaming, and multimodal generation",
      modality: "audio+image+video+text->text+image",
      max_tokens: 2048,
      temperature: 0.7
    },
    "gemini-2.0-flash-lite" => %{
      name: "Gemini 2.0 Flash-Lite",
      description: "Cost efficiency and low latency",
      modality: "audio+image+video+text->text",
      max_tokens: 1024,
      temperature: 0.7
    },
    "gemini-1.5-flash" => %{
      name: "Gemini 1.5 Flash",
      description: "Fast and versatile performance across a diverse variety of tasks",
      modality: "audio+image+video+text->text",
      max_tokens: 1024,
      temperature: 0.7
    },
    "gemini-1.5-flash-8b" => %{
      name: "Gemini 1.5 Flash-8B",
      description: "High volume and lower intelligence tasks",
      modality: "audio+image+video+text->text",
      max_tokens: 1024,
      temperature: 0.7
    },
    "gemini-1.5-pro" => %{
      name: "Gemini 1.5 Pro",
      description: "Complex reasoning tasks requiring more intelligence",
      modality: "audio+image+video+text->text",
      max_tokens: 2048,
      temperature: 0.7
    },
    "gemini-embedding-exp" => %{
      name: "Gemini Embedding",
      description: "Measuring the relatedness of text strings",
      modality: "text->embedding",
      max_tokens: 1024,
      temperature: 0.0
    },
    "imagen-3.0-generate-002" => %{
      name: "Imagen 3",
      description: "Our most advanced image generation model",
      modality: "text->image",
      max_tokens: nil,
      temperature: 0.7
    }
  }

  @provider_id :google
  @provider_path "google"

  @impl true
  def definition do
    %Provider{
      id: @provider_id,
      name: "Google",
      description: "Google Gemini API with OpenAI-compatible interface",
      type: :direct,
      api_base_url: @base_url
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
    - api_key: string - Google Gemini API key (optional)

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
    - api_key: string - Google Gemini API key (optional)

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
  Normalizes a model ID to ensure it's in the correct format for Google Gemini.

  ## Options
    - No specific options for this method

  Returns a tuple with {:ok, normalized_id} on success or {:error, reason} on failure.
  """
  def normalize(model, _opts \\ []) do
    # Google Gemini models have format like "models/gemini-2.0-flash" or "gemini-2.0-flash"
    model = String.replace(model, "models/", "")

    if Map.has_key?(@models, model) do
      {:ok, model}
    else
      {:error, "Invalid model ID. Expected one of: #{inspect(Map.keys(@models))}"}
    end
  end

  @impl true
  def base_url() do
    @base_url
  end

  @impl true
  def request_headers(opts) do
    api_key =
      Keyword.get(opts, :api_key) || Jido.AI.Keyring.get(:google_api_key)

    if api_key do
      %{
        "Content-Type" => "application/json",
        "x-goog-api-key" => api_key
      }
    else
      %{"Content-Type" => "application/json"}
    end
  end

  @impl true
  def validate_model_opts(opts) do
    {:ok,
     %Jido.AI.Model{
       id: opts[:model] || "google_default",
       name: opts[:model_name] || "Google Gemini Model",
       provider: :google
     }}
  end

  @impl true
  @doc """
  Builds a %Jido.AI.Model{} struct from the provided options.

  This function validates the options, sets defaults, and creates a fully populated
  model struct for the Google provider.

  ## Parameters
    - opts: Map or keyword list of options for building the model

  ## Returns
    - {:ok, %Jido.AI.Model{}} on success
    - {:error, reason} on failure
  """
  def build(opts) when is_list(opts) do
    # Convert keyword list to map
    build(Map.new(opts))
  end

  def build(opts) when is_map(opts) do
    # Extract or generate an API key
    api_key = Map.get(opts, "api_key") || Map.get(opts, :api_key)

    # Get model from opts
    model = Map.get(opts, "name") || Map.get(opts, :model)

    # Validate model
    if is_nil(model) do
      {:error, "model is required for Google Gemini models"}
    else
      # Strip models/ prefix if present
      model = String.replace(model, "models/", "")

      # Create the model struct with all necessary fields
      model = %Jido.AI.Model{
        id: model,
        name: Map.get(opts, "displayName") || Map.get(opts, :name, "Google #{model}"),
        provider: :google,
        model: model,
        base_url: Keyword.get(opts, :base_url, @base_url),
        api_key: api_key,
        temperature: Map.get(opts, "temperature", 0.7),
        max_tokens: Map.get(opts, "outputTokenLimit", 1024),
        max_retries: Map.get(opts, :max_retries, 0),
        architecture: %Jido.AI.Model.Architecture{
          modality: Map.get(opts, :modality, "text+image->text"),
          tokenizer: Map.get(opts, :tokenizer, "gemini"),
          instruct_type: Map.get(opts, :instruct_type, "gemini")
        },
        description:
          Map.get(opts, "description") || Map.get(opts, :description, "Google Gemini model"),
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
              {:ok, process_single_model(model_data, opts)}

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
          case Enum.find(models, fn m -> m.id == model end) do
            nil -> {:error, "Model not found in cache: #{model}"}
            found_model -> {:ok, found_model}
          end

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp fetch_and_cache_models(opts) do
    url = base_url() <> "models"
    headers = request_headers(opts)

    case Req.get(url, headers: headers) do
      {:ok, %{status: 200, body: body}} ->
        models = extract_models_from_response(body)

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

  defp extract_models_from_response(%{"data" => models}) when is_list(models), do: models
  defp extract_models_from_response(models) when is_list(models), do: models
  defp extract_models_from_response(%{"models" => models}) when is_list(models), do: models
  defp extract_models_from_response(other), do: [other]

  defp fetch_model_from_api(model, opts) do
    url = base_url() <> "models/#{model}"
    headers = request_headers(opts)

    case Req.get(url, headers: headers) do
      {:ok, %{status: 200, body: model_data}} ->
        # Process the model data
        processed_model = process_single_model(model_data, opts)

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
      {:ok, processed_model} = process_single_model(model, [])
      processed_model
    end)
  end

  defp process_single_model(model_data, opts) do
    # Strip models/ prefix from model ID
    model_id = String.replace(model_data["name"] || model_data["id"] || "", "models/", "")

    # Get model info from our predefined models
    model_info =
      Map.get(@models, model_id) ||
        %{
          name: model_data["displayName"] || "Google #{model_id}",
          description: model_data["description"] || "Google model",
          modality: "text->text",
          max_tokens: 1024,
          temperature: 0.7
        }

    # Create the model struct with all necessary fields
    model = %Jido.AI.Model{
      id: model_id,
      name: model_info.name,
      provider: :google,
      model: model_id,
      base_url: Keyword.get(opts || [], :base_url, @base_url),
      api_key: Keyword.get(opts || [], :api_key),
      temperature: Map.get(model_data, "temperature", model_info.temperature),
      max_tokens: Map.get(model_data, "outputTokenLimit", model_info.max_tokens),
      max_retries: 0,
      architecture: %Jido.AI.Model.Architecture{
        modality: model_info.modality,
        tokenizer: "gemini",
        instruct_type: "gemini"
      },
      description: model_info.description,
      created: System.system_time(:second),
      endpoints: []
    }

    {:ok, model}
  end
end
