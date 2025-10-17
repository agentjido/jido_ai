defmodule Jido.AI.Model.Provider.Adapter do
  @moduledoc """
  Defines the behavior that any provider adapter must implement.

  This allows for extending the system with new providers without modifying
  the core Provider module.
  """

  @doc """
  Returns the base URL for the provider's API.

  ## Parameters
    - provider: The provider struct

  ## Returns
    - The base URL as a string
  """
  @callback base_url() :: String.t()

  @doc """
  Fetches models from the provider's API.

  ## Parameters
    - opts: Options for the fetch operation (like API key, etc.)

  ## Returns
    * `{:ok, models}` - on success
    * `{:error, reason}` - on failure
  """
  @callback list_models(opts :: keyword()) ::
              {:ok, list(map())} | {:error, any()}

  @doc """
  Fetches a specific model by ID from the provider's API.

  ## Parameters
    - model: The ID of the model to fetch
    - opts: Options for the fetch operation (like API key, etc.)

  ## Returns
    * `{:ok, model}` - on success
    * `{:error, reason}` - on failure
  """
  @callback model(model :: String.t(), opts :: keyword()) ::
              {:ok, map()} | {:error, any()}

  @doc """
  Normalizes a model ID to ensure it's in the correct format for the provider.

  ## Parameters
    - id: The ID to normalize
    - opts: Options for normalization

  ## Returns
    * `{:ok, normalized_id}` - on success
    * `{:error, reason}` - on failure
  """
  @callback normalize(model :: String.t(), opts :: keyword()) ::
              {:ok, String.t()} | {:error, any()}

  @doc """
  Returns the headers required for API requests to the provider.

  ## Parameters
    - provider: The provider struct
    - opts: Options for the request (like API key, etc.)

  ## Returns
    - A map of headers
  """
  @callback request_headers(opts :: keyword()) :: map()

  @doc """
  Returns the provider definition.

  ## Returns
    - A provider struct
  """
  @callback definition() :: Jido.AI.Provider.t()

  @doc """
  Validates the options for creating a Jido.AI.Model specific to this provider.

  Providers can parse and verify that `opts` is valid. Returns:
    - `{:ok, %Jido.AI.Model{}}` if validation succeeds
    - `{:error, reason}` otherwise.
  """
  @callback validate_model_opts(opts :: keyword()) ::
              {:ok, Jido.AI.Model.t()} | {:error, any()}

  @doc """
  Transforms a generic `Jido.AI.Model` struct into a provider-specific client model.

  For example, `transform_model_to_clientmodel(:langchain, model)` might produce a
  config map specialized for LangChain usage.
  """
  @callback transform_model_to_clientmodel(client_atom :: atom(), model :: Jido.AI.Model.t()) ::
              {:ok, any()} | {:error, any()}

  @doc """
  Builds a %Jido.AI.Model{} struct from the provided options.

  This is the main entry point for creating a model struct from provider-specific options.
  Each provider implements this to handle its own validation, defaults, and API key retrieval.

  ## Parameters
    - opts: Keyword list of options for building the model

  ## Returns
    * `{:ok, %Jido.AI.Model{}}` - on success
    * `{:error, reason}` - on failure
  """
  @callback build(opts :: keyword()) :: {:ok, Jido.AI.Model.t()} | {:error, String.t()}
end
