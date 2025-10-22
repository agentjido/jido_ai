defmodule Jido.AI.Provider.OpenRouter do
  @moduledoc """
  Adapter for the OpenRouter AI provider.

  Implements the ProviderBehavior for OpenRouter's specific API.
  """
  @behaviour Jido.AI.Model.Provider.Adapter
  alias Jido.AI.Model
  alias Jido.AI.Provider
  alias Jido.AI.Provider.Helpers

  @base_url "https://openrouter.ai/api/v1"
  @provider_id :openrouter

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
  Lists available models from the Model Registry.

  This function delegates to the Model Registry which provides access to
  OpenRouter models through ReqLLM integration.

  ## Options
    - refresh: boolean - Ignored (models come from ReqLLM)

  Returns a tuple with {:ok, models} on success or {:error, reason} on failure.
  """
  def list_models(_opts \\ []) do
    # Delegate to Model Registry which gets models from ReqLLM
    alias Jido.AI.Model.Registry
    Registry.list_models(@provider_id)
  end

  @impl true
  @doc """
  Fetches a specific model by ID from the Model Registry.

  ## Options
    - refresh: boolean - Ignored (models come from ReqLLM)

  Returns a tuple with {:ok, model} on success or {:error, reason} on failure.
  """
  def model(model_id, _opts \\ []) do
    # Delegate to Model Registry
    alias Jido.AI.Model.Registry

    case Registry.list_models(@provider_id) do
      {:ok, models} ->
        case Enum.find(models, fn m -> m.id == model_id or m.name == model_id end) do
          nil -> {:error, "Model not found: #{model_id}"}
          model -> {:ok, model}
        end

      {:error, reason} ->
        {:error, reason}
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
  def base_url do
    @base_url
  end

  @impl true
  def request_headers(_opts) do
    # Headers are now handled internally by ReqLLM
    # This function is kept for adapter behavior compatibility
    %{
      "HTTP-Referer" => "https://agentjido.xyz",
      "X-Title" => "Jido AI",
      "Content-Type" => "application/json"
    }
  end

  @impl true
  def validate_model_opts(opts) do
    {:ok,
     %Model{
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
      Helpers.get_api_key(opts, "OPENROUTER_API_KEY", :openrouter_api_key)

    # Get model from opts
    model = Keyword.get(opts, :model)

    # Validate model
    if is_nil(model) do
      {:error, "model is required for OpenRouter models"}
    else
      # Create the model struct with all necessary fields
      model_struct = %Model{
        id: Keyword.get(opts, :id, "openrouter_#{model}"),
        name: Keyword.get(opts, :name, "OpenRouter #{model}"),
        provider: :openrouter,
        model: model,
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
        description: Keyword.get(opts, :description, "OpenRouter model"),
        created: System.system_time(:second),
        endpoints: [],
        reqllm_id: Model.compute_reqllm_id(:openrouter, model)
      }

      {:ok, model_struct}
    end
  end

  @impl true
  def transform_model_to_clientmodel(_client_atom, _model) do
    {:error, "Not implemented yet"}
  end
end
