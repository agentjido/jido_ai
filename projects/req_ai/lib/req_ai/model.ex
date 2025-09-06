defmodule ReqAI.Model do
  @moduledoc """
  Represents an AI model configuration for ReqAI.

  This module provides a simplified model structure focused on essential
  fields needed for AI interactions: provider information, model name,
  and runtime parameters like temperature and token limits.

  ## Examples

      # Create a model with provider and options tuple
      {:ok, model} = ReqAI.Model.from({:openai, model: "gpt-4", temperature: 0.7})

      # Create a model from string specification
      {:ok, model} = ReqAI.Model.from("openai:gpt-4")

      # Create a model directly
      model = ReqAI.Model.new(:anthropic, "claude-3-sonnet", temperature: 0.5, max_tokens: 1000)

  """

  use TypedStruct

  @type modality :: :text | :audio | :image | :video | :pdf
  @type cost :: %{input: float(), output: float()}
  @type limit :: %{context: non_neg_integer(), output: non_neg_integer()}
  @type capabilities :: %{
          reasoning?: boolean(),
          tool_call?: boolean(),
          supports_temperature?: boolean()
        }

  typedstruct do
    @typedoc "An AI model configuration"

    # Required runtime fields
    field(:provider, atom(), enforce: true)
    field(:model, String.t(), enforce: true)
    field(:temperature, float() | nil)
    field(:max_tokens, non_neg_integer() | nil)
    field(:max_retries, non_neg_integer() | nil, default: 3)

    # Optional metadata fields
    field(:limit, limit() | nil)
    field(:modalities, %{input: [modality()], output: [modality()]} | nil)
    field(:capabilities, capabilities() | nil)
    field(:cost, cost() | nil)
  end

  @doc """
  Creates a new model with the specified provider and model name.

  ## Parameters

  - `provider` - The provider atom (e.g., `:openai`, `:anthropic`)
  - `model` - The model name string (e.g., `"gpt-4"`, `"claude-3-sonnet"`)
  - `opts` - Optional keyword list of parameters

  ## Options

  - `:temperature` - Temperature for generation (0.0 to 2.0)
  - `:max_tokens` - Maximum tokens to generate
  - `:max_retries` - Maximum retry attempts (default: 3)
  - `:limit` - Token limits map with `:context` and `:output` keys
  - `:modalities` - Input/output modalities map with lists of supported types
  - `:capabilities` - Model capabilities like `:reasoning?`, `:tool_call?`, `:supports_temperature?`
  - `:cost` - Pricing information with `:input` and `:output` cost per 1K tokens

  ## Examples

      iex> ReqAI.Model.new(:openai, "gpt-4")
      %ReqAI.Model{provider: :openai, model: "gpt-4", max_retries: 3}

      iex> ReqAI.Model.new(:anthropic, "claude-3-sonnet", temperature: 0.7, max_tokens: 1000)
      %ReqAI.Model{provider: :anthropic, model: "claude-3-sonnet", temperature: 0.7, max_tokens: 1000, max_retries: 3}

  """
  @spec new(atom(), String.t(), keyword()) :: t()
  def new(provider, model, opts \\ []) when is_atom(provider) and is_binary(model) do
    %__MODULE__{
      provider: provider,
      model: model,
      temperature: Keyword.get(opts, :temperature),
      max_tokens: Keyword.get(opts, :max_tokens),
      max_retries: Keyword.get(opts, :max_retries, 3),
      limit: Keyword.get(opts, :limit),
      modalities: Keyword.get(opts, :modalities),
      capabilities: Keyword.get(opts, :capabilities),
      cost: Keyword.get(opts, :cost)
    }
  end

  @doc """
  Creates a model from various input formats.

  Supports:
  - Existing Model struct (returned as-is)
  - Tuple format: `{provider, opts}` where provider is atom and opts is keyword list
  - String format: `"provider:model"` (e.g., `"openai:gpt-4"`)

  ## Examples

      # From existing struct
      {:ok, model} = ReqAI.Model.from(%ReqAI.Model{provider: :openai, model: "gpt-4"})

      # From tuple with options (including metadata)
      {:ok, model} = ReqAI.Model.from({:openai, model: "gpt-4", temperature: 0.7, max_tokens: 1000,
                                       capabilities: %{reasoning?: true, tool_call?: true}})

      # From string specification
      {:ok, model} = ReqAI.Model.from("anthropic:claude-3-sonnet")

  """
  @spec from(t() | {atom(), keyword()} | String.t()) :: {:ok, t()} | {:error, term()}
  def from(%__MODULE__{} = model), do: {:ok, model}

  def from({provider, opts}) when is_atom(provider) and is_list(opts) do
    case Keyword.get(opts, :model) do
      nil ->
        {:error,
         ReqAI.Error.validation_error(:missing_model, "model is required in options",
           provider: provider
         )}

      model_name when is_binary(model_name) ->
        {:ok, new(provider, model_name, opts)}

      _ ->
        {:error,
         ReqAI.Error.validation_error(:invalid_model_type, "model must be a string",
           model: Keyword.get(opts, :model)
         )}
    end
  end

  def from(provider_model_string) when is_binary(provider_model_string) do
    case String.split(provider_model_string, ":", parts: 2) do
      [provider_str, model_name] when provider_str != "" and model_name != "" ->
        provider = parse_provider(provider_str)
        {:ok, new(provider, model_name)}

      _ ->
        {:error,
         ReqAI.Error.validation_error(
           :invalid_model_spec,
           "Invalid model specification. Expected format: 'provider:model'",
           spec: provider_model_string
         )}
    end
  end

  def from(input) do
    {:error,
     ReqAI.Error.validation_error(:invalid_model_spec, "Invalid model specification",
       input: input
     )}
  end

  @doc """
  Creates a model from input, raising an exception on error.

  ## Examples

      iex> ReqAI.Model.from!("openai:gpt-4")
      %ReqAI.Model{provider: :openai, model: "gpt-4", max_retries: 3}

  """
  @spec from!(t() | {atom(), keyword()} | String.t()) :: t()
  def from!(input) do
    case from(input) do
      {:ok, model} -> model
      {:error, error} -> raise error
    end
  end

  @doc """
  Validates that a model struct has required fields.

  ## Examples

      iex> model = %ReqAI.Model{provider: :openai, model: "gpt-4", max_retries: 3}
      iex> ReqAI.Model.valid?(model)
      true

      iex> ReqAI.Model.valid?(%{provider: :openai, model: "gpt-4"})
      false

  """
  @spec valid?(t()) :: boolean()
  def valid?(%__MODULE__{provider: provider, model: model, max_retries: max_retries})
      when is_atom(provider) and is_binary(model) and model != "" and is_integer(max_retries) and
             max_retries >= 0 do
    true
  end

  def valid?(_), do: false

  @doc """
  Returns a model with sensible defaults for missing metadata fields.

  This helper fills in common defaults for models that don't have complete metadata.

  ## Examples

      iex> model = ReqAI.Model.new(:openai, "gpt-4")
      iex> ReqAI.Model.with_defaults(model).capabilities
      %{reasoning?: false, tool_call?: false, supports_temperature?: true}

  """
  @spec with_defaults(t()) :: t()
  def with_defaults(%__MODULE__{} = model) do
    default_limit = %{context: 128_000, output: 4_096}
    default_modalities = %{input: [:text], output: [:text]}
    default_capabilities = %{reasoning?: false, tool_call?: false, supports_temperature?: true}

    %{
      model
      | limit: merge_with_defaults(model.limit, default_limit),
        modalities: merge_with_defaults(model.modalities, default_modalities),
        capabilities: merge_with_defaults(model.capabilities, default_capabilities)
    }
  end

  defp merge_with_defaults(nil, defaults), do: defaults
  defp merge_with_defaults(existing, defaults), do: Map.merge(defaults, existing)

  defp parse_provider(str) when is_binary(str) do
    try do
      String.to_existing_atom(str)
    rescue
      ArgumentError -> String.to_atom(str)
    end
  end
end
