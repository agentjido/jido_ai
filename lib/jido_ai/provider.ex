defmodule Jido.AI.Provider do
  use TypedStruct
  require Logger
  alias Jido.AI.Provider.Helpers

  @providers [
    {:openrouter, Jido.AI.Provider.OpenRouter},
    {:anthropic, Jido.AI.Provider.Anthropic},
    {:openai, Jido.AI.Provider.OpenAI},
    {:cloudflare, Jido.AI.Provider.Cloudflare}
  ]

  @type provider_id :: atom()
  @type provider_type :: :direct | :proxy

  typedstruct do
    @typedoc "An AI model provider"
    field(:id, atom(), enforce: true)
    field(:name, String.t(), enforce: true)
    field(:description, String.t())
    field(:type, provider_type(), default: :direct)
    field(:api_base_url, String.t())
    field(:requires_api_key, boolean(), default: true)
    field(:endpoints, map(), default: %{})
    field(:models, list(), default: [])
    field(:proxy_for, list(String.t()))
  end

  @doc """
  Returns the base directory path for provider-specific files.

  This is where provider configuration, models, and other data files are stored.
  The path is relative to the project root and expands to `./priv/provider/`.
  """
  def base_dir do
    default = Path.join([File.cwd!(), "priv", "provider"])
    Application.get_env(:jido_ai, :provider_base_dir, default)
  end

  @doc """
  Standardizes a model name across providers by removing version numbers and dates.
  This helps match equivalent models from different providers.

  ## Examples
      iex> standardize_model_name("claude-3.7-sonnet-20250219")
      "claude-3.7-sonnet"
      iex> standardize_model_name("gpt-4-0613")
      "gpt-4"
  """
  def standardize_model_name(model_id) do
    Helpers.standardize_name(model_id)
  end

  def providers do
    @providers
  end

  def list do
    Enum.map(@providers, fn {_id, module} ->
      module.definition()
    end)
  end

  def models(provider, opts \\ []) do
    case get_adapter_module(provider) do
      {:ok, adapter} ->
        adapter.models(provider, opts)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Gets a specific model from a provider by its ID or name.

  ## Parameters

  * `provider` - The provider struct or ID
  * `model_id` - The ID or name of the model to fetch
  * `opts` - Additional options for the request

  ## Returns

  * `{:ok, model}` - The model was found
  * `{:error, reason}` - The model was not found or an error occurred
  """
  @spec get_model(t() | atom(), String.t(), keyword()) :: {:ok, map()} | {:error, String.t()}
  def get_model(provider, model_id, opts \\ [])

  def get_model(%__MODULE__{} = provider, model_id, opts) do
    case get_adapter_module(provider) do
      {:ok, adapter} ->
        if function_exported?(adapter, :get_model, 3) do
          adapter.get_model(provider, model_id, opts)
        else
          # Fallback implementation if the adapter doesn't implement get_model
          fallback_get_model(provider, model_id, opts)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  def get_model(provider_id, model_id, opts)
      when is_atom(provider_id) or is_binary(provider_id) do
    provider_id_atom = ensure_atom(provider_id)

    case get_adapter_by_id(provider_id_atom) do
      {:ok, adapter} ->
        if function_exported?(adapter, :get_model, 3) do
          # Create a minimal provider struct for the adapter
          provider = %__MODULE__{
            id: provider_id_atom,
            name: Atom.to_string(provider_id_atom)
          }

          adapter.get_model(provider, model_id, opts)
        else
          # Fallback implementation
          {:error, "Provider adapter does not implement get_model/3"}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Fallback implementation for get_model when the adapter doesn't implement it
  defp fallback_get_model(provider, model_id, opts) do
    case models(provider, opts) do
      {:ok, models} ->
        case Enum.find(models, fn model -> model.id == model_id end) do
          nil -> {:error, "Model not found: #{model_id}"}
          model -> {:ok, model}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  def get_adapter_module(%__MODULE__{id: provider_id}) do
    # Ensure provider_id is an atom
    provider_id_atom = ensure_atom(provider_id)

    case Enum.find(@providers, fn {id, _module} -> id == provider_id_atom end) do
      {_id, module} ->
        if Code.ensure_loaded?(module) and function_exported?(module, :models, 1) do
          {:ok, module}
        else
          {:error, "Adapter module #{module} exists but does not implement required functions"}
        end

      nil ->
        {:error, "No adapter found for provider: #{provider_id}"}
    end
  end

  @doc """
  Gets an adapter module by provider ID.

  This is a helper function for getting the adapter module directly by ID.
  """
  def get_adapter_by_id(provider_id) do
    # Ensure provider_id is an atom
    provider_id_atom = ensure_atom(provider_id)

    case Enum.find(@providers, fn {id, _module} -> id == provider_id_atom end) do
      {_id, module} -> {:ok, module}
      nil -> {:error, "No adapter found for provider: #{provider_id}"}
    end
  end

  @doc """
  Ensures the given value is an atom.
  """
  @spec ensure_atom(atom() | String.t() | term()) :: atom() | term()
  def ensure_atom(id) when is_atom(id), do: id
  def ensure_atom(id) when is_binary(id), do: String.to_atom(id)
  def ensure_atom(id), do: id

  def call_provider_callback(provider, callback, args) do
    impl = module_for(provider)

    if function_exported?(impl, callback, length(args)) do
      apply(impl, callback, args)
    else
      {:error, "#{inspect(impl)} does not implement callback #{callback}/#{length(args)}"}
    end
  end

  defp module_for(:anthropic), do: Jido.AI.Provider.Anthropic
  defp module_for(:cloudflare), do: Jido.AI.Provider.Cloudflare
  defp module_for(:openai), do: Jido.AI.Provider.OpenAI
  defp module_for(:openrouter), do: Jido.AI.Provider.OpenRouter

  @doc """
  Lists all cached models across all providers.

  ## Returns
    - List of model maps, each containing provider information
  """
  def list_all_cached_models do
    # Ensure the base directory exists
    File.mkdir_p!(base_dir())

    # Find all provider directories
    provider_dirs =
      case File.ls(base_dir()) do
        {:ok, dirs} -> Enum.filter(dirs, &File.dir?(Path.join(base_dir(), &1)))
        {:error, _} -> []
      end

    # Collect models from each provider
    provider_dirs
    |> Enum.flat_map(fn provider_dir ->
      provider_id = String.to_atom(provider_dir)
      models_file = Path.join([base_dir(), provider_dir, "models.json"])

      if File.exists?(models_file) do
        case File.read(models_file) do
          {:ok, json} ->
            case Jason.decode(json) do
              {:ok, %{"data" => models}} when is_list(models) ->
                Enum.map(models, &Map.put(&1, :provider, provider_id))

              {:ok, models} when is_list(models) ->
                Enum.map(models, &Map.put(&1, :provider, provider_id))

              _ ->
                []
            end

          _ ->
            []
        end
      else
        []
      end
    end)
  end

  @doc """
  Retrieves combined information for a model across all providers.

  ## Parameters
    - model_name: The name of the model to search for

  ## Returns
    - {:ok, model_info} - Combined model information
    - {:error, reason} - Error if model not found
  """
  def get_combined_model_info(model_name) do
    models =
      list_all_cached_models()
      |> Enum.filter(fn model ->
        model_id = Map.get(model, :id) || Map.get(model, "id")
        standardized_name = standardize_model_name(model_id)
        standardized_name == model_name
      end)

    if Enum.empty?(models) do
      {:error, "No model found with name: #{model_name}"}
    else
      # Merge information from all matching models
      merged_model = Helpers.merge_model_information(models)
      {:ok, merged_model}
    end
  end
end
