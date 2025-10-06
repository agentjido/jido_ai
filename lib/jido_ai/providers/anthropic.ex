defmodule Jido.AI.Provider.Anthropic do
  @moduledoc """
  Adapter for the Anthropic AI provider.

  Implements the ProviderBehavior for Anthropic's specific API.
  """
  @behaviour Jido.AI.Model.Provider.Adapter
  alias Jido.AI.Model
  alias Jido.AI.Provider
  alias Jido.AI.Provider.Helpers

  @base_url "https://api.anthropic.com/v1"
  @api_version "2023-06-01"

  # List models
  # curl https://api.anthropic.com/v1/models \
  #    --header "x-api-key: $ANTHROPIC_API_KEY" \
  #    --header "anthropic-version: 2023-06-01"

  # Retrieve Model
  # curl https://api.anthropic.com/v1/models/{model} \
  # --header "x-api-key: $ANTHROPIC_API_KEY" \
  # --header "anthropic-version: 2023-06-01"

  @provider_id :anthropic

  @impl true
  def request_headers(_opts) do
    # Headers are now handled internally by ReqLLM
    # This function is kept for adapter behavior compatibility
    %{
      "Content-Type" => "application/json",
      "anthropic-version" => @api_version
    }
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
  Lists available models from the Model Registry.

  This function delegates to the Model Registry which provides access to
  Anthropic models through ReqLLM integration.

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
  Normalizes a model ID to ensure it's in the correct format for Anthropic.

  ## Options
    - No specific options for this method

  Returns a tuple with {:ok, normalized_id} on success or {:error, reason} on failure.
  """
  def normalize(model, _opts \\ []) do
    # Anthropic model IDs are simple strings like "claude-3-opus-20240229"
    # This method ensures the ID is properly formatted
    if String.match?(model, ~r/^claude-[a-zA-Z0-9\-]+$/) do
      {:ok, model}
    else
      {:error, "Invalid model ID format for Anthropic. Expected 'claude-*' format."}
    end
  end

  @impl true
  def base_url do
    @base_url
  end

  @impl true
  def validate_model_opts(opts) do
    %Jido.AI.Model{
      id: opts[:model],
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

    # Get model from opts
    model = Keyword.get(opts, :model)

    # Validate model
    if is_nil(model) do
      {:error, "model is required for Anthropic models"}
    else
      # Create the model struct with all necessary fields
      model_struct = %Model{
        id: Keyword.get(opts, :id, "anthropic_#{model}"),
        name: Keyword.get(opts, :name, "Anthropic #{model}"),
        provider: :anthropic,
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
        description: Keyword.get(opts, :description, "Anthropic Claude model"),
        created: System.system_time(:second),
        endpoints: [],
        reqllm_id: Model.compute_reqllm_id(:anthropic, model)
      }

      {:ok, model_struct}
    end
  end

  @impl true
  def transform_model_to_clientmodel(_client_atom, _model) do
    {:error, "Not implemented yet"}
  end
end
