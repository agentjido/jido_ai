defmodule Jido.AI.Model do
  use TypedStruct
  require Logger

  typedstruct module: Architecture do
    field(:instruct_type, String.t() | nil)
    field(:modality, String.t())
    field(:tokenizer, String.t())
  end

  typedstruct module: Pricing do
    field(:completion, String.t())
    field(:image, String.t())
    field(:prompt, String.t())
    field(:request, String.t())
  end

  typedstruct module: Endpoint do
    field(:context_length, integer())
    field(:max_completion_tokens, integer())
    field(:max_prompt_tokens, integer() | nil)
    field(:name, String.t())
    field(:pricing, Pricing.t())
    field(:provider_name, String.t())
    field(:quantization, String.t() | nil)
    field(:supported_parameters, list(String.t()))
  end

  typedstruct do
    field(:id, String.t())
    field(:name, String.t())
    field(:provider, atom())
    field(:architecture, Architecture.t())
    field(:created, integer())
    field(:description, String.t())
    field(:endpoints, list(Endpoint.t()))
    # New fields for LLM calls
    field(:base_url, String.t())
    field(:api_key, String.t())
    field(:model, String.t())
    field(:temperature, float(), default: 0.7)
    field(:max_tokens, non_neg_integer(), default: 1024)
    field(:max_retries, non_neg_integer(), default: 0)
    # ReqLLM integration field
    field(:reqllm_id, String.t())
    # Enhanced ReqLLM metadata fields
    field(:capabilities, map())
    field(:modalities, map())
    field(:cost, map())
  end

  @doc """
  Creates a model struct from various input formats.

  This is the main entry point for creating a model struct. It handles:
  - An existing %Jido.AI.Model{} struct (pass-through)
  - A tuple of {provider, opts} where provider is an atom and opts is a keyword list
  - A category tuple of {:category, category, class}

  The function automatically computes and sets the `reqllm_id` field for ReqLLM integration.

  ## Parameters
    - input: The input to create a model from

  ## Returns
    * `{:ok, %Jido.AI.Model{}}` - on success
    * `{:error, reason}` - on failure

  ## Examples

      iex> Jido.AI.Model.from({:anthropic, [model: "claude-3-5-haiku"]})
      {:ok, %Jido.AI.Model{provider: :anthropic, model: "claude-3-5-haiku", reqllm_id: "anthropic:claude-3-5-haiku", ...}}

      iex> Jido.AI.Model.from(%Jido.AI.Model{provider: :openai, model: "gpt-4"})
      {:ok, %Jido.AI.Model{provider: :openai, model: "gpt-4", ...}}
  """
  @spec from(term()) :: {:ok, ReqLLM.Model.t()} | {:error, String.t()}
  def from(input) do
    case input do
      # Already a ReqLLM.Model struct
      %ReqLLM.Model{} = model ->
        {:ok, model}

      # Already a Jido.AI.Model struct - convert to ReqLLM.Model
      %__MODULE__{provider: provider, model: model_name} ->
        ReqLLM.Model.from("#{provider}:#{model_name}")

      # A provider tuple
      {provider, opts} when is_atom(provider) and is_list(opts) ->
        model_name = Keyword.get(opts, :model)

        if model_name do
          # Use ReqLLM.Model directly
          ReqLLM.Model.from({provider, model_name, opts})
        else
          {:error, "model option is required for provider #{provider}"}
        end

      # A string specification like "openai:gpt-4"
      model_spec when is_binary(model_spec) ->
        ReqLLM.Model.from(model_spec)

      # A category tuple - not supported directly by ReqLLM
      {:category, category, class} when is_atom(category) and is_atom(class) ->
        {:error, "Category-based models not supported. Use provider:model format instead."}

      other ->
        {:error, "Invalid model specification: #{inspect(other)}"}
    end
  end

  # Define the schema for model options
  @model_options_schema NimbleOptions.new!(
                          # Core model identification
                          id: [
                            type: :string,
                            doc: "Unique identifier for the model"
                          ],
                          name: [
                            type: :string,
                            doc: "Human-readable name for the model"
                          ],
                          description: [
                            type: :string,
                            doc: "Description of the model's capabilities and use cases"
                          ],

                          # Model specification - at least one of these must be provided
                          model: [
                            type: :string,
                            doc: "The specific model identifier (e.g., 'claude-3-5-haiku')"
                          ],
                          capabilities: [
                            type: {:list, :atom},
                            doc:
                              "List of capabilities the model supports (e.g., [:chat, :embeddings])"
                          ],
                          tier: [
                            type: :atom,
                            doc: "Performance tier of the model (e.g., :small, :medium, :large)"
                          ],

                          # Architecture details
                          modality: [
                            type: :string,
                            default: "text",
                            doc:
                              "The primary modality of the model (e.g., 'text', 'vision', 'multimodal')"
                          ],
                          tokenizer: [
                            type: :string,
                            default: "unknown",
                            doc: "The tokenizer used by the model"
                          ],
                          instruct_type: [
                            type: :string,
                            doc: "The instruction format used by the model"
                          ],

                          # Routing options
                          via: [
                            type: :atom,
                            doc: "Route the request through a different provider"
                          ],

                          # Additional options
                          temperature: [
                            type: :float,
                            doc: "Temperature setting for generation"
                          ],
                          max_tokens: [
                            type: :integer,
                            doc: "Maximum number of tokens to generate"
                          ]
                        )

  @doc """
  Validates model options for use in an action.

  ## Parameters
    - opts: The options to validate

  ## Returns
    * `{:ok, %Jido.AI.Model{}}` - on success
    * `{:error, reason}` - on failure
  """
  @spec validate_model_opts(term()) :: {:ok, __MODULE__.t()} | {:error, String.t()}
  def validate_model_opts(opts) do
    case from(opts) do
      {:ok, model} ->
        {:ok, model}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Creates a new model configuration with the given provider and options.

  ## Parameters

  * `provider_or_tuple` - Either an atom representing the provider (e.g., `:openrouter`)
    or a tuple with provider and options.
  * `opts` - Keyword list of options for the model (optional when using tuple format).

  ## Examples

      # Using provider atom and options separately
      iex> Jido.AI.Model.new!(:openrouter, model: "anthropic/claude-3.5-haiku")

      # Using tuple shorthand
      iex> Jido.AI.Model.new!({:anthropic, capabilities: [:chat], tier: :small})

  ## Returns

  A model configuration that can be used with Jido.AI.Agent.

  @deprecated Use Jido.AI.Model.from/1 instead
  """
  @spec new!(atom() | {atom(), keyword()}, keyword()) :: atom() | {atom(), keyword()}
  def new!(provider_or_tuple, opts \\ [])

  # Handle tuple format: {provider_atom, options}
  def new!({provider, options}, _opts) when is_atom(provider) and is_list(options) do
    # Get the list of valid providers from Jido.AI.Provider
    valid_providers = get_valid_providers()

    # Check if the provider is valid
    if provider in valid_providers do
      # If the provider is valid, return it as is
      {provider, options}
    else
      # If the provider is not valid, map it to a compatible provider
      # This is a temporary solution until the deprecated validation is removed
      case provider do
        :openrouter ->
          # For OpenRouter, we'll use Anthropic as the base provider
          # and add the original provider info in the options
          {:anthropic, Keyword.merge(options, via: :openrouter)}

        :cloudflare ->
          # For Cloudflare, we'll use OpenAI as the base provider
          # and add the original provider info in the options
          {:openai, Keyword.merge(options, via: :cloudflare)}

        # For any other provider, default to OpenAI
        _ ->
          Logger.warning("Unknown provider #{inspect(provider)}, defaulting to :openai")
          {:openai, Keyword.merge(options, original_provider: provider)}
      end
    end
  end

  # Handle provider atom with options
  def new!(provider, opts) when is_atom(provider) and is_list(opts) do
    new!({provider, opts}, [])
  end

  # Handle invalid input
  def new!(invalid_input, opts) do
    raise ArgumentError,
          "Invalid input for Model.new!: #{inspect(invalid_input)} with options #{inspect(opts)}"
  end

  @doc """
  Validates a model configuration.

  ## Parameters

  * `model_config` - The model configuration to validate.

  ## Returns

  * `{:ok, model_config}` - The model configuration is valid.
  * `{:error, reason}` - The model configuration is invalid.

  @deprecated Use Jido.AI.Model.from/1 instead
  """
  @spec validate(term()) :: {:ok, term()} | {:error, String.t()}
  def validate({provider, opts}) when is_atom(provider) and is_list(opts) do
    # Get the list of valid providers from Jido.AI.Provider
    valid_providers = get_valid_providers()

    # Check if the provider is valid
    if provider in valid_providers do
      # Validate options using NimbleOptions
      case validate_options_with_schema(opts) do
        {:ok, _validated_opts} -> {:ok, {provider, opts}}
        {:error, reason} -> {:error, reason}
      end
    else
      {:error,
       "Invalid provider: #{inspect(provider)}. Valid providers are: #{inspect(valid_providers)}"}
    end
  end

  def validate(provider) when is_atom(provider) do
    # Get the list of valid providers from Jido.AI.Provider
    valid_providers = get_valid_providers()

    # Check if the provider is valid
    if provider in valid_providers do
      {:ok, provider}
    else
      {:error,
       "Invalid provider: #{inspect(provider)}. Valid providers are: #{inspect(valid_providers)}"}
    end
  end

  def validate(invalid_input) do
    {:error,
     "Invalid model configuration: #{inspect(invalid_input)}. Expected a provider atom or a {provider, opts} tuple."}
  end

  # Validate options using NimbleOptions schema
  defp validate_options_with_schema(opts) when is_list(opts) do
    # First, validate against the schema
    case NimbleOptions.validate(opts, @model_options_schema) do
      {:ok, validated_opts} ->
        # Then check if at least one of model, capabilities, or tier is present
        if has_required_model_specification?(validated_opts) do
          {:ok, validated_opts}
        else
          {:error, "At least one of :model, :capabilities, or :tier must be specified"}
        end

      {:error, %NimbleOptions.ValidationError{} = error} ->
        {:error, Exception.message(error)}
    end
  end

  # Check if at least one of the required model specification options is present
  defp has_required_model_specification?(opts) do
    Keyword.has_key?(opts, :model) or Keyword.has_key?(opts, :capabilities) or
      Keyword.has_key?(opts, :tier)
  end

  # Helper function to get valid providers
  # This is a temporary solution for testing
  defp get_valid_providers do
    # For testing purposes, we'll return a list of known providers
    # In production, this would be replaced with a call to Jido.AI.Provider.providers()
    [:anthropic, :openai, :openrouter, :cloudflare, :mistral, :google]
  end
end
