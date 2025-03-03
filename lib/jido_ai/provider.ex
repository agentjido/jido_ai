defmodule Jido.AI.Provider do
  use TypedStruct
  require Logger

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
  The path is relative to the project root and expands to `./priv/providers/`.
  """
  def base_dir do
    default = Application.app_dir(:jido_ai, "priv/provider")
    Application.get_env(:jido_ai, :provider_base_dir, default)
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
  Ensures that a provider ID is an atom.

  Converts strings to atoms if necessary.
  """
  def ensure_atom(id) when is_atom(id), do: id

  def ensure_atom(id) when is_binary(id) do
    case id do
      "openai" ->
        :openai

      "anthropic" ->
        :anthropic

      "openrouter" ->
        :openrouter

      _ ->
        try do
          String.to_existing_atom(id)
        rescue
          ArgumentError ->
            Logger.warning("Unknown provider ID: #{id}")
            String.to_atom(id)
        end
    end
  end

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

  def ensure_atom(id), do: id
end
