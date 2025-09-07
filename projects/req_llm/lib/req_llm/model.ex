defmodule ReqLLM.Model do
  @moduledoc """
  Represents an AI model configuration for ReqLLM.

  This module provides a simplified model structure focused on essential
  fields needed for AI interactions: provider information, model name,
  and runtime parameters like temperature and token limits.

  ## Examples

      # Create a model with provider and options tuple
      {:ok, model} = ReqLLM.Model.from({:openai, model: "gpt-4", temperature: 0.7})

      # Create a model from string specification
      {:ok, model} = ReqLLM.Model.from("openai:gpt-4")

      # Create a model directly
      model = ReqLLM.Model.new(:anthropic, "claude-3-sonnet", temperature: 0.5, max_tokens: 1000)

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

      iex> ReqLLM.Model.new(:openai, "gpt-4")
      %ReqLLM.Model{provider: :openai, model: "gpt-4", max_retries: 3}

      iex> ReqLLM.Model.new(:anthropic, "claude-3-sonnet", temperature: 0.7, max_tokens: 1000)
      %ReqLLM.Model{provider: :anthropic, model: "claude-3-sonnet", temperature: 0.7, max_tokens: 1000, max_retries: 3}

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
      {:ok, model} = ReqLLM.Model.from(%ReqLLM.Model{provider: :openai, model: "gpt-4"})

      # From tuple with options (including metadata)
      {:ok, model} = ReqLLM.Model.from({:openai, model: "gpt-4", temperature: 0.7, max_tokens: 1000,
                                       capabilities: %{reasoning?: true, tool_call?: true}})

      # From string specification
      {:ok, model} = ReqLLM.Model.from("anthropic:claude-3-sonnet")

  """
  @spec from(t() | {atom(), keyword()} | String.t()) :: {:ok, t()} | {:error, term()}
  def from(%__MODULE__{} = model), do: {:ok, model}

  def from({provider, opts}) when is_atom(provider) and is_list(opts) do
    case Keyword.get(opts, :model) do
      nil ->
        {:error,
         ReqLLM.Error.validation_error(:missing_model, "model is required in options",
           provider: provider
         )}

      model_name when is_binary(model_name) ->
        {:ok, new(provider, model_name, opts)}

      _ ->
        {:error,
         ReqLLM.Error.validation_error(:invalid_model_type, "model must be a string",
           model: Keyword.get(opts, :model)
         )}
    end
  end

  def from(provider_model_string) when is_binary(provider_model_string) do
    case String.split(provider_model_string, ":", parts: 2) do
      [provider_str, model_name] when provider_str != "" and model_name != "" ->
        case parse_provider(provider_str) do
          {:ok, provider} ->
            {:ok, new(provider, model_name)}

          {:error, reason} ->
            {:error,
             ReqLLM.Error.validation_error(
               :invalid_provider,
               reason,
               provider: provider_str
             )}
        end

      _ ->
        {:error,
         ReqLLM.Error.validation_error(
           :invalid_model_spec,
           "Invalid model specification. Expected format: 'provider:model'",
           spec: provider_model_string
         )}
    end
  end

  def from(input) do
    {:error,
     ReqLLM.Error.validation_error(:invalid_model_spec, "Invalid model specification",
       input: input
     )}
  end

  @doc """
  Creates a model from input, raising an exception on error.

  ## Examples

      iex> ReqLLM.Model.from!("openai:gpt-4")
      %ReqLLM.Model{provider: :openai, model: "gpt-4", max_retries: 3}

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

      iex> model = %ReqLLM.Model{provider: :openai, model: "gpt-4", max_retries: 3}
      iex> ReqLLM.Model.valid?(model)
      true

      iex> ReqLLM.Model.valid?(%{provider: :openai, model: "gpt-4"})
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

      iex> model = ReqLLM.Model.new(:openai, "gpt-4")
      iex> ReqLLM.Model.with_defaults(model).capabilities
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

  @doc """
  Loads a model with full metadata from the models_dev directory.

  This is useful for capability verification and other scenarios requiring
  detailed model information beyond what's needed for API calls.

  ## Examples

      {:ok, model_with_metadata} = ReqLLM.Model.with_metadata("anthropic:claude-3-sonnet")
      model_with_metadata.cost
      #=> %{"input" => 3.0, "output" => 15.0, ...}

  """
  @spec with_metadata(String.t()) :: {:ok, t()} | {:error, String.t()}
  def with_metadata(model_spec) when is_binary(model_spec) do
    with {:ok, base_model} <- from(model_spec),
         {:ok, full_metadata} <- load_full_metadata(model_spec) do
      enhanced_model = %{
        base_model
        | limit: get_in(full_metadata, ["limit"]) |> map_string_keys_to_atoms(),
          modalities: get_in(full_metadata, ["modalities"]) |> map_string_keys_to_atoms(),
          capabilities: build_capabilities_from_metadata(full_metadata),
          cost: get_in(full_metadata, ["cost"]) |> map_string_keys_to_atoms()
      }

      {:ok, enhanced_model}
    end
  end

  defp merge_with_defaults(nil, defaults), do: defaults
  defp merge_with_defaults(existing, defaults), do: Map.merge(defaults, existing)

  # Define a whitelist of valid provider atoms based on currently supported providers
  # These atoms are safe because they're defined at compile time, not from user input
  @valid_providers [
    :openai,
    :anthropic,
    :openrouter,
    :google,
    :mistral,
    :togetherai,
    :cerebras,
    :deepseek,
    :inference,
    :submodel,
    :venice,
    :v0,
    :zhipuai,
    :alibaba,
    :fastrouter
  ]

  defp parse_provider(str) when is_binary(str) do
    # Only use String.to_existing_atom to prevent atom table leaks
    try do
      atom = String.to_existing_atom(str)

      if atom in @valid_providers do
        {:ok, atom}
      else
        {:error, "Unsupported provider: #{str}"}
      end
    rescue
      ArgumentError -> {:error, "Unknown provider: #{str}"}
    end
  end

  # Load full metadata from JSON files for enhanced model creation
  defp load_full_metadata(model_spec) do
    priv_dir = Application.app_dir(:req_llm, "priv")

    case String.split(model_spec, ":", parts: 2) do
      [provider_id, specific_model_id] ->
        provider_path = Path.join([priv_dir, "models_dev", "#{provider_id}.json"])
        load_model_from_provider_file(provider_path, specific_model_id)

      [single_model_id] ->
        metadata_path = Path.join([priv_dir, "models_dev", "#{single_model_id}.json"])
        load_individual_model_file(metadata_path)
    end
  end

  defp load_model_from_provider_file(provider_path, specific_model_id) do
    with {:ok, content} <- File.read(provider_path),
         {:ok, %{"models" => models}} <- Jason.decode(content),
         %{} = model_data <- Enum.find(models, &(&1["id"] == specific_model_id)) do
      {:ok, model_data}
    else
      {:error, :enoent} ->
        {:error, "Provider metadata not found: #{provider_path}"}

      {:error, %Jason.DecodeError{} = error} ->
        {:error, "Invalid JSON in #{provider_path}: #{Exception.message(error)}"}

      nil ->
        {:error, "Model #{specific_model_id} not found in provider file"}

      _ ->
        {:error, "Failed to load model metadata"}
    end
  end

  defp load_individual_model_file(metadata_path) do
    with {:ok, content} <- File.read(metadata_path),
         {:ok, data} <- Jason.decode(content) do
      {:ok, data}
    else
      {:error, :enoent} ->
        {:error, "Model metadata not found: #{metadata_path}"}

      {:error, %Jason.DecodeError{} = error} ->
        {:error, "Invalid JSON in #{metadata_path}: #{Exception.message(error)}"}
    end
  end

  # Whitelist of safe metadata keys to convert to atoms
  @safe_metadata_keys ~w[
    input output context text image reasoning tool_call temperature
    cache_read cache_write limit modalities capabilities cost
  ]

  defp map_string_keys_to_atoms(nil), do: nil

  defp map_string_keys_to_atoms(map) when is_map(map) do
    Map.new(map, fn
      {key, value} when is_binary(key) and key in @safe_metadata_keys ->
        atom_key = String.to_existing_atom(key)
        {atom_key, value}

      {key, value} when is_binary(key) ->
        # Keep unsafe keys as strings to prevent atom leakage
        {key, value}

      {key, value} ->
        {key, value}
    end)
  rescue
    ArgumentError ->
      # If any safe key doesn't exist as an atom, just return the map as-is
      map
  end

  defp build_capabilities_from_metadata(metadata) do
    %{
      reasoning?: Map.get(metadata, "reasoning", false),
      tool_call?: Map.get(metadata, "tool_call", false),
      supports_temperature?: Map.get(metadata, "temperature", false)
    }
  end
end
