defmodule ReqLLM.Provider.Registry do
  @moduledoc """
  Registry for AI providers and their supported models.

  The registry uses `:persistent_term` for efficient, read-heavy access patterns typical
  in AI applications. Providers are registered at compile time through the DSL, ensuring
  all available providers and models are known at startup.

  ## Storage Format

  The registry stores providers as:

      %{
        provider_id => %{
          module: Module,
          metadata: %{models: [...], capabilities: [...], ...}
        }
      }

  ## Usage Examples

      # Get a provider module
      {:ok, module} = ReqLLM.Provider.Registry.get_provider(:anthropic)
      module #=> ReqLLM.Providers.Anthropic

      # Get model information  
      {:ok, model} = ReqLLM.Provider.Registry.get_model(:anthropic, "claude-3-sonnet")
      model.metadata.context_length #=> 200000

      # Check if a model exists
      ReqLLM.Provider.Registry.model_exists?("anthropic:claude-3-sonnet") #=> true

      # List all providers
      ReqLLM.Provider.Registry.list_providers() #=> [:anthropic, :openai, :github_models]

      # List models for a provider
      ReqLLM.Provider.Registry.list_models(:anthropic) #=> ["claude-3-sonnet", "claude-3-haiku", ...]

  ## Integration

  The registry is automatically populated by providers using `ReqLLM.Provider.DSL`:

      defmodule MyProvider do
        use ReqLLM.Provider.DSL,
          id: :my_provider,
          base_url: "https://api.example.com/v1",
          metadata: "priv/models_dev/my_provider.json"

        # Provider implementation...
      end

  The DSL calls `register/3` during compilation to add the provider to the registry.

  """

  @registry_key :req_llm_providers

  @doc """
  Registers a provider in the global registry.

  Called automatically by the DSL during compilation. Should not be called manually.

  ## Parameters

    * `provider_id` - Unique identifier for the provider (atom)
    * `module` - The provider module implementing Req plugin pattern  
    * `metadata` - Provider metadata including supported models

  ## Examples

      ReqLLM.Provider.Registry.register(:my_provider, MyProvider, %{
        models: ["model-1", "model-2"],
        capabilities: [:text_generation, :embeddings]
      })

  """
  @spec register(atom(), module(), map()) :: :ok | {:error, {:already_registered, module()}}
  def register(provider_id, module, metadata) when is_atom(provider_id) and is_atom(module) do
    current_providers = get_registry()

    case Map.get(current_providers, provider_id) do
      nil ->
        updated_registry =
          Map.put(current_providers, provider_id, %{
            module: module,
            metadata: metadata || %{}
          })

        :persistent_term.put(@registry_key, updated_registry)
        :ok

      %{module: ^module} ->
        # Idempotent registration
        :ok

      %{module: other} ->
        require Logger
        Logger.warning(
          "Attempted to overwrite provider #{provider_id}: existing=#{inspect(other)}, attempted=#{inspect(module)}"
        )

        {:error, {:already_registered, other}}
    end
  end

  @doc """
  Retrieves a provider module by ID.

  ## Parameters

    * `provider_id` - The provider identifier (atom)

  ## Returns

    * `{:ok, module}` - Provider module found
    * `{:error, :not_found}` - Provider not registered

  ## Examples

      {:ok, module} = ReqLLM.Provider.Registry.get_provider(:anthropic)
      module #=> ReqLLM.Providers.Anthropic

      ReqLLM.Provider.Registry.get_provider(:unknown)
      #=> {:error, :not_found}

  """
  @spec get_provider(atom()) :: {:ok, module()} | {:error, :not_found}
  def get_provider(provider_id) when is_atom(provider_id) do
    case get_registry() do
      %{^provider_id => %{module: module}} -> {:ok, module}
      _ -> {:error, :not_found}
    end
  end

  @doc """
  Alias for get_provider/1 to match legacy API expectations.
  """
  @spec fetch(atom()) :: {:ok, module()} | {:error, :not_found}
  def fetch(provider_id), do: get_provider(provider_id)

  @doc """
  Retrieves model information for a specific provider and model.

  ## Parameters

    * `provider_id` - The provider identifier (atom)
    * `model_name` - The model name (string)

  ## Returns

    * `{:ok, model}` - ReqLLM.Model struct with metadata
    * `{:error, :provider_not_found}` - Provider not registered
    * `{:error, :model_not_found}` - Model not supported by provider

  ## Examples

      {:ok, model} = ReqLLM.Provider.Registry.get_model(:anthropic, "claude-3-sonnet")
      model.metadata.context_length #=> 200000
      model.metadata.pricing.input  #=> 0.003

      ReqLLM.Provider.Registry.get_model(:anthropic, "unknown-model")
      #=> {:error, :model_not_found}

  """
  @spec get_model(atom(), String.t()) ::
          {:ok, ReqLLM.Model.t()} | {:error, :provider_not_found | :model_not_found}
  def get_model(provider_id, model_name) when is_atom(provider_id) and is_binary(model_name) do
    with {:ok, provider_info} <- get_provider_info(provider_id),
         {:ok, model_metadata} <- find_model_metadata(provider_info, model_name) do
      # Create model with basic fields, metadata is stored in provider registry
      model = %ReqLLM.Model{
        provider: provider_id,
        model: model_name
      }

      # Add metadata separately for backward compatibility
      model_with_metadata = Map.put(model, :_metadata, model_metadata)
      {:ok, model_with_metadata}
    end
  end

  @doc """
  Retrieves model information with bang syntax (raises on error).

  Same as `get_model/2` but raises `ArgumentError` instead of returning error tuples.

  ## Parameters

    * `model_spec` - Model specification string (e.g., "anthropic:claude-3-sonnet")

  ## Examples

      model = ReqLLM.Provider.Registry.get_model!("anthropic:claude-3-sonnet")
      model.metadata.context_length #=> 200000

      ReqLLM.Provider.Registry.get_model!("unknown:model")
      #=> ** (ArgumentError) Provider not found: unknown

  """
  @spec get_model!(String.t()) :: ReqLLM.Model.t()
  def get_model!(model_spec) when is_binary(model_spec) do
    case parse_model_spec(model_spec) do
      {:ok, provider_id, model_name} ->
        case get_model(provider_id, model_name) do
          {:ok, model} ->
            model

          {:error, :provider_not_found} ->
            raise ArgumentError, "Provider not found: #{provider_id}"

          {:error, :model_not_found} ->
            raise ArgumentError, "Model not found: #{provider_id}:#{model_name}"
        end

      {:error, reason} ->
        raise ArgumentError, "Invalid model specification '#{model_spec}': #{reason}"
    end
  end

  @doc """
  Lists all registered provider IDs.

  ## Returns

  List of provider atoms in registration order.

  ## Examples

      ReqLLM.Provider.Registry.list_providers()
      #=> [:anthropic, :openai, :github_models]

  """
  @spec list_providers() :: [atom()]
  def list_providers do
    get_registry()
    |> Map.keys()
    |> Enum.sort()
  end

  @doc """
  Retrieves complete provider metadata by ID.

  ## Parameters

    * `provider_id` - The provider identifier (atom)

  ## Returns

    * `{:ok, metadata}` - Provider metadata map
    * `{:error, :not_found}` - Provider not registered

  ## Examples

      {:ok, metadata} = ReqLLM.Provider.Registry.get_provider_metadata(:anthropic)
      env_vars = get_in(metadata, ["provider", "env"])
      env_vars #=> ["ANTHROPIC_API_KEY"]

  """
  @spec get_provider_metadata(atom()) :: {:ok, map()} | {:error, :not_found}
  def get_provider_metadata(provider_id) when is_atom(provider_id) do
    case get_provider_info(provider_id) do
      {:ok, %{metadata: metadata}} -> {:ok, metadata}
      error -> error
    end
  end

  @doc """
  Lists all model names supported by a provider.

  ## Parameters

    * `provider_id` - The provider identifier (atom)

  ## Returns

    * `{:ok, models}` - List of model name strings
    * `{:error, :not_found}` - Provider not registered

  ## Examples

      {:ok, models} = ReqLLM.Provider.Registry.list_models(:anthropic)
      models #=> ["claude-3-sonnet", "claude-3-haiku", "claude-3-opus"]

      ReqLLM.Provider.Registry.list_models(:unknown)
      #=> {:error, :not_found}

  """
  @spec list_models(atom()) :: {:ok, [String.t()]} | {:error, :not_found}
  def list_models(provider_id) when is_atom(provider_id) do
    case get_provider_info(provider_id) do
      {:ok, %{metadata: %{models: models}}} when is_list(models) ->
        model_names =
          Enum.map(models, fn
            %{"id" => id} -> id
            %{id: id} -> id
            model when is_binary(model) -> model
            _ -> nil
          end)
          |> Enum.filter(&is_binary/1)
          |> Enum.sort()

        {:ok, model_names}

      {:ok, _} ->
        {:ok, []}

      error ->
        error
    end
  end

  @doc """
  Checks if a model specification exists in the registry.

  ## Parameters

    * `model_spec` - Model specification string (e.g., "anthropic:claude-3-sonnet")

  ## Returns

  Boolean indicating if the model exists.

  ## Examples

      ReqLLM.Provider.Registry.model_exists?("anthropic:claude-3-sonnet") #=> true
      ReqLLM.Provider.Registry.model_exists?("unknown:model") #=> false

  """
  @spec model_exists?(String.t()) :: boolean()
  def model_exists?(model_spec) when is_binary(model_spec) do
    case parse_model_spec(model_spec) do
      {:ok, provider_id, model_name} ->
        case get_model(provider_id, model_name) do
          {:ok, _} -> true
          {:error, _} -> false
        end

      {:error, _} ->
        false
    end
  end

  @doc """
  Initializes the provider registry by discovering and registering all provider modules.

  This function scans for modules that implement the `ReqLLM.Provider` behaviour
  and registers them automatically.
  """
  @spec initialize() :: :ok
  def initialize do
    require Logger

    providers = discover_providers()

    # Use Task.async_stream for parallel provider info extraction
    {registry_map, failed_modules} =
      providers
      |> Task.async_stream(&extract_provider_info/1, ordered: false, timeout: 5000)
      |> Enum.reduce({%{}, []}, fn
        {:ok, {:ok, {id, module, metadata}}}, {acc, failed} ->
          {Map.put(acc, id, %{module: module, metadata: metadata}), failed}

        {:ok, {:error, {module, error}}}, {acc, failed} ->
          {acc, [{module, error} | failed]}

        {:exit, reason}, {acc, failed} ->
          {acc, [{:unknown_module, reason} | failed]}
      end)

    # Log any failures in a batch
    if !Enum.empty?(failed_modules) do
      Logger.warning("Failed to register #{length(failed_modules)} providers: #{inspect(failed_modules)}")
    end

    # Store in persistent_term
    :persistent_term.put(@registry_key, registry_map)
    Logger.debug("Provider registry initialized with #{map_size(registry_map)} providers")

    :ok
  end

  @spec reload() :: :ok
  def reload, do: initialize()

  @doc """
  Clears the provider registry.

  Mainly useful for testing.
  """
  @spec clear() :: :ok
  def clear do
    :persistent_term.erase(@registry_key)
    :ok
  end

  # Private helper functions

  @doc false
  @spec extract_provider_info(module()) ::
          {:ok, {atom(), module(), map()}} | {:error, {module(), term()}}
  def extract_provider_info(module) do
    # Get provider metadata from DSL compilation
    metadata = if Code.ensure_loaded?(module) and function_exported?(module, :metadata, 0) do
      module.metadata()
    else
      %{}
    end

    # Get provider ID from DSL function or fallback methods
    provider_id = cond do
      function_exported?(module, :provider_id, 0) ->
        module.provider_id()
      
      function_exported?(module, :provider_info, 0) ->
        module.provider_info().id

      true ->
        # Fallback: extract from module name
        extract_provider_id_from_module_name(module)
    end

    {:ok, {provider_id, module, metadata}}
  rescue
    error ->
      {:error, {module, Exception.message(error)}}
  catch
    :exit, reason ->
      {:error, {module, reason}}
  end

  @doc false
  @spec discover_providers() :: [module()]
  def discover_providers do
    case :application.get_key(:req_llm, :modules) do
      {:ok, modules} -> Enum.filter(modules, &provider_module?/1)
      :undefined -> []
    end
  end

  @doc false
  @spec provider_module?(module()) :: boolean()
  def provider_module?(module) do
    behaviours = module.__info__(:attributes)[:behaviour] || []
    ReqLLM.Provider in behaviours
  rescue
    _ -> false
  end

  defp extract_provider_id_from_module_name(module) do
    module
    |> Atom.to_string()
    |> String.split(".")
    |> List.last()
    |> String.downcase()
    |> String.to_atom()
  end

  defp get_registry do
    :persistent_term.get(@registry_key, %{})
  end

  defp get_provider_info(provider_id) do
    case get_registry() do
      %{^provider_id => provider_info} -> {:ok, provider_info}
      _ -> {:error, :provider_not_found}
    end
  end

  defp find_model_metadata(%{metadata: %{models: models}}, model_name) when is_list(models) do
    model_data =
      Enum.find(models, fn
        %{"id" => ^model_name} -> true
        %{id: ^model_name} -> true
        ^model_name -> true
        _ -> false
      end)

    case model_data do
      nil -> {:error, :model_not_found}
      %{"id" => _} = data -> {:ok, data}
      %{id: _} = data -> {:ok, data}
      ^model_name -> {:ok, %{"id" => model_name}}
    end
  end

  defp find_model_metadata(%{metadata: metadata}, _model_name) do
    # Provider has no models list, return basic metadata
    {:ok, metadata}
  end

  defp parse_model_spec(model_spec) when is_binary(model_spec) do
    case String.split(model_spec, ":", parts: 2) do
      [provider_str, model_name] ->
        provider_id = String.to_existing_atom(provider_str)
        {:ok, provider_id, model_name}

      [_single_part] ->
        {:error, "Model specification must be in format 'provider:model'"}
    end
  rescue
    ArgumentError ->
      {:error, "Unknown provider in specification"}
  end
end
