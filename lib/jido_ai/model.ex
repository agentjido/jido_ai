defmodule Jido.AI.Model do
  @moduledoc """
  Module for managing AI models.

  This struct represents an AI model with capabilities, pricing, and limitations
  as defined by the models.dev schema specification.
  """
  use TypedStruct

  @type modality :: :text | :audio | :image | :video | :pdf
  @type cost :: %{
          input: float(),
          output: float(),
          cache_read: float() | nil,
          cache_write: float() | nil
        }
  @type limit :: %{
          context: non_neg_integer(),
          output: non_neg_integer()
        }

  typedstruct do
    # Runtime fields for API calls - provider reference only
    field(:provider, atom())
    field(:model, String.t())
    field(:temperature, float() | nil)
    field(:max_tokens, non_neg_integer() | nil)
    field(:max_retries, non_neg_integer() | nil)

    # Metadata fields from models.dev schema
    field(:id, String.t())
    field(:name, String.t())
    field(:attachment, boolean())
    field(:reasoning, boolean())
    field(:supports_temperature, boolean())
    field(:tool_call, boolean())
    field(:knowledge, String.t() | nil)
    field(:release_date, String.t())
    field(:last_updated, String.t())

    field(:modalities, %{
      input: [modality()],
      output: [modality()]
    })

    field(:open_weights, boolean())
    field(:cost, cost() | nil)
    field(:limit, limit())
  end

  @cost_schema NimbleOptions.new!(
                 input: [type: {:or, [:integer, :float]}, required: true],
                 output: [type: {:or, [:integer, :float]}, required: true],
                 cache_read: [type: {:or, [:integer, :float]}, required: false],
                 cache_write: [type: {:or, [:integer, :float]}, required: false]
               )

  @limit_schema NimbleOptions.new!(
                  context: [type: :non_neg_integer, required: true],
                  output: [type: :non_neg_integer, required: true]
                )

  @schema NimbleOptions.new!(
            provider: [type: :atom, required: true],
            model: [type: :string, required: true],
            temperature: [type: {:or, [:integer, :float]}, required: false],
            max_tokens: [type: :non_neg_integer, required: false],
            max_retries: [type: :non_neg_integer, required: false],
            id: [type: :string, required: true],
            name: [type: :string, required: true],
            attachment: [type: :boolean, required: true],
            reasoning: [type: :boolean, required: true],
            supports_temperature: [type: :boolean, required: true],
            tool_call: [type: :boolean, required: true],
            knowledge: [type: :string, required: false],
            release_date: [type: :string, required: true],
            last_updated: [type: :string, required: true],
            modalities: [type: :map, required: true],
            open_weights: [type: :boolean, required: true],
            cost: [type: {:custom, __MODULE__, :validate_cost, []}, required: false],
            limit: [type: {:custom, __MODULE__, :validate_limit, []}, required: true]
          )

  @doc """
  Validates that a model struct conforms to the schema requirements using NimbleOptions.
  """
  @spec validate(t()) :: {:ok, t()} | {:error, NimbleOptions.ValidationError.t()}
  def validate(%__MODULE__{} = model) do
    model_map = Map.from_struct(model)

    case NimbleOptions.validate(model_map, @schema) do
      {:ok, _validated} -> {:ok, model}
      error -> error
    end
  end

  @doc """
  Validates date format (YYYY-MM or YYYY-MM-DD).
  """
  @spec validate_date_format(String.t() | nil) :: {:ok, String.t() | nil} | {:error, String.t()}
  def validate_date_format(nil), do: {:ok, nil}

  def validate_date_format(value) when is_binary(value) do
    # Use Calendar.ISO for more robust date validation
    case String.split(value, "-") do
      [year, month] ->
        with {year_int, ""} <- Integer.parse(year),
             {month_int, ""} <- Integer.parse(month),
             true <- Calendar.ISO.valid_date?(year_int, month_int, 1) do
          {:ok, value}
        else
          _ -> {:error, "must be in valid YYYY-MM format"}
        end

      [year, month, day] ->
        with {year_int, ""} <- Integer.parse(year),
             {month_int, ""} <- Integer.parse(month),
             {day_int, ""} <- Integer.parse(day),
             true <- Calendar.ISO.valid_date?(year_int, month_int, day_int) do
          {:ok, value}
        else
          _ -> {:error, "must be in valid YYYY-MM-DD format"}
        end

      _ ->
        {:error, "must be in YYYY-MM or YYYY-MM-DD format"}
    end
  end

  def validate_date_format(_), do: {:error, "must be a string or nil"}

  @doc """
  Validates cost structure with required input/output and optional cache fields.
  """
  @spec validate_cost(map() | nil) :: {:ok, cost() | nil} | {:error, String.t()}
  def validate_cost(nil), do: {:ok, nil}

  def validate_cost(cost) when is_map(cost) do
    NimbleOptions.validate(cost, @cost_schema)
  end

  def validate_cost(_), do: {:error, "must be a map"}

  @doc """
  Validates limit structure with context and output fields.
  """
  @spec validate_limit(map()) :: {:ok, limit()} | {:error, String.t()}
  def validate_limit(limit) when is_map(limit) do
    NimbleOptions.validate(limit, @limit_schema)
  end

  def validate_limit(_), do: {:error, "must be a map"}

  @doc """
  Creates a model from various input formats.

  Supports:
  - Existing Model struct
  - Tuple format: `{provider, opts}` where provider is atom and opts is keyword list
  - String format: `"provider:model"` (e.g., "openrouter:anthropic/claude-3.5-sonnet")

  ## Examples

      Model.from(%Model{provider: :openai, model: "gpt-4"})
      Model.from({:openrouter, model: "anthropic/claude-3.5-sonnet", temperature: 0.7})
      Model.from("openrouter:anthropic/claude-3.5-sonnet")

  """
  @spec from(t() | {atom(), keyword()} | String.t()) :: {:ok, t()} | {:error, String.t()}
  def from(%__MODULE__{} = model), do: {:ok, model}

  def from({provider, opts}) when is_atom(provider) and is_list(opts) do
    model_name = Keyword.get(opts, :model)

    if is_nil(model_name) do
      {:error, "model is required in options"}
    else
      # Validate provider exists and get provider info
      case validate_provider(provider) do
        :ok ->
          case Jido.AI.Provider.Registry.fetch(provider) do
            {:ok, provider_module} ->
              provider_info = provider_module.provider_info()

              # Look up the model in the provider's models map
              models_map = Map.get(provider_info, :models, %{})

              case Map.get(models_map, model_name) do
                nil ->
                  # Model not found in registry, create with defaults
                  create_default_model(provider, model_name, opts)

                model_data ->
                  # Create model from registry data with runtime overrides
                  case model_data do
                    %__MODULE__{} ->
                      # Already a Model struct (e.g., from fake provider)
                      {:ok,
                       Map.merge(model_data, %{
                         temperature: Keyword.get(opts, :temperature) || model_data.temperature,
                         max_tokens: Keyword.get(opts, :max_tokens) || model_data.max_tokens,
                         max_retries: Keyword.get(opts, :max_retries) || model_data.max_retries || 3
                       })}

                    _ ->
                      # JSON data from models.dev
                      create_model_from_registry(provider, model_name, model_data, opts)
                  end
              end

            {:error, _} ->
              # Provider module not found, create with defaults
              create_default_model(provider, model_name, opts)
          end

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  def from(provider_model_string) when is_binary(provider_model_string) do
    case String.split(provider_model_string, ":", parts: 2) do
      [provider_str, model_name] ->
        case parse_provider(provider_str) do
          {:ok, provider} -> from({provider, [model: model_name]})
          {:error, reason} -> {:error, reason}
        end

      _ ->
        {:error, "Invalid model specification. Expected format: 'provider:model'"}
    end
  end

  def from(_), do: {:error, "Invalid model specification"}

  @doc """
  Creates a model from JSON data with validation.
  Raises an exception if validation fails.
  """
  @spec from_json!(map()) :: t()
  def from_json!(json_data) when is_map(json_data) do
    case from_json(json_data) do
      {:ok, model} -> model
      {:error, error} -> raise ArgumentError, "Invalid model JSON: #{error}"
    end
  end

  @doc """
  Creates a model from JSON data with validation.
  """
  @spec from_json(map()) :: {:ok, t()} | {:error, String.t()}
  def from_json(json_data) when is_map(json_data) do
    provider = json_data["provider"] && String.to_existing_atom(json_data["provider"])

    model = %__MODULE__{
      provider: provider,
      model: json_data["provider_model_id"],
      temperature: json_data["temperature"],
      max_tokens: json_data["max_tokens"],
      max_retries: json_data["max_retries"] || 3,
      id: json_data["id"],
      name: json_data["name"],
      attachment: json_data["attachment"] || false,
      reasoning: json_data["reasoning"] || false,
      supports_temperature: json_data["supports_temperature"] || true,
      tool_call: json_data["tool_call"] || false,
      knowledge: json_data["knowledge"],
      release_date: json_data["release_date"] || "2024-01",
      last_updated: json_data["last_updated"] || "2024-01",
      modalities: json_data["modalities"] || %{input: [:text], output: [:text]},
      open_weights: json_data["open_weights"] || false,
      cost: json_data["cost"],
      limit: json_data["limit"] || %{context: 128_000, output: 4096}
    }

    validate(model)
  rescue
    ArgumentError -> {:error, "Invalid provider: #{json_data["provider"]}"}
  end

  # Private helper to create a model with defaults when not found in registry
  defp create_default_model(provider, model_name, opts) do
    model = %__MODULE__{
      provider: provider,
      model: model_name,
      temperature: Keyword.get(opts, :temperature),
      max_tokens: Keyword.get(opts, :max_tokens),
      max_retries: Keyword.get(opts, :max_retries, 3),
      # Defaults for metadata fields
      id: to_string(model_name),
      name: to_string(model_name),
      attachment: false,
      reasoning: false,
      supports_temperature: true,
      tool_call: false,
      release_date: "2024-01",
      last_updated: "2024-01",
      modalities: %{input: [:text], output: [:text]},
      open_weights: false,
      limit: %{context: 128_000, output: 4096},
      cost: nil
    }

    {:ok, model}
  end

  # Private helper to create a model from registry data with runtime overrides
  defp create_model_from_registry(provider, model_name, model_data, opts) do
    # Convert string keys to atoms for modalities
    modalities =
      case model_data["modalities"] do
        %{"input" => input, "output" => output} ->
          %{
            input: Enum.map(input, &convert_to_atom/1),
            output: Enum.map(output, &convert_to_atom/1)
          }

        _ ->
          %{input: [:text], output: [:text]}
      end

    # Convert cost data to atoms
    cost =
      case model_data["cost"] do
        %{} = cost_map ->
          cost_map
          |> Map.new(fn {k, v} -> {convert_to_atom(k), v} end)

        _ ->
          nil
      end

    # Convert limit data to atoms
    limit =
      case model_data["limit"] do
        %{} = limit_map ->
          limit_map
          |> Map.new(fn {k, v} -> {convert_to_atom(k), v} end)

        _ ->
          %{context: 128_000, output: 4096}
      end

    model = %__MODULE__{
      provider: provider,
      model: model_name,
      # Runtime overrides from opts
      temperature: Keyword.get(opts, :temperature),
      max_tokens: Keyword.get(opts, :max_tokens),
      max_retries: Keyword.get(opts, :max_retries, 3),
      # Metadata from registry
      id: model_data["id"] || to_string(model_name),
      name: model_data["name"] || to_string(model_name),
      attachment: model_data["attachment"] || false,
      reasoning: model_data["reasoning"] || false,
      supports_temperature: model_data["temperature"] || true,
      tool_call: model_data["tool_call"] || false,
      knowledge: model_data["knowledge"],
      release_date: model_data["release_date"] || "2024-01",
      last_updated: model_data["last_updated"] || "2024-01",
      modalities: modalities,
      open_weights: model_data["open_weights"] || false,
      cost: cost,
      limit: limit
    }

    {:ok, model}
  end

  # Helper to safely convert strings to atoms
  defp convert_to_atom(str) when is_binary(str) do
    String.to_existing_atom(str)
  rescue
    ArgumentError -> String.to_atom(str)
  end

  defp convert_to_atom(atom) when is_atom(atom), do: atom

  @doc false
  defp validate_provider(provider) do
    case Jido.AI.Provider.Registry.fetch(provider) do
      {:ok, _} -> :ok
      {:error, _} -> {:error, "Unknown provider: #{provider}"}
    end
  end

  defp parse_provider(str) do
    case Jido.AI.Provider.Registry.list_providers()
         |> Enum.find(&(&1 |> Atom.to_string() == str)) do
      nil ->
        try do
          atom = String.to_existing_atom(str)

          validate_provider(atom)
          |> case do
            :ok -> {:ok, atom}
            {:error, reason} -> {:error, reason}
          end
        rescue
          ArgumentError -> {:error, "Unknown provider: #{str}"}
        end

      atom ->
        {:ok, atom}
    end
  end
end
