defmodule JidoKeys do
  @moduledoc """
  Easy access to LLM API keys and environment configuration.

  Provides fast lookups with hierarchical resolution from session values,
  environment variables (via Dotenvy), application config, and defaults.

  ## Basic Usage

      # Returns value or `nil`
      JidoKeys.get(:openai_api_key)

      # Provide a default
      JidoKeys.get(:openai_api_key, "demo-key")

      # Bang variant raises ArgumentError
      JidoKeys.get!(:openai_api_key)

      # Boolean predicate
      JidoKeys.has?(:openai_api_key)

      # Inspect available keys (strings, already normalised)
      JidoKeys.list()

  """

  @type key :: atom() | String.t()
  @type value :: String.t() | nil

  @doc """
  Returns the value or `default` when the key is missing.

  ## Examples

      iex> JidoKeys.get(:my_api_key)
      "secret_value"

      iex> JidoKeys.get(:missing_key, "fallback")
      "fallback"

  """
  @spec get(key(), value()) :: value()
  def get(key, default \\ nil) do
    GenServer.call(JidoKeys.Server, {:get, key, default})
  end

  @doc """
  Returns the value or raises ArgumentError when the key is missing.

  ## Examples

      iex> JidoKeys.get!(:my_api_key)
      "secret_value"

      iex> JidoKeys.get!(:missing)
      ** (ArgumentError) Configuration key :missing not found

  """
  @spec get!(key()) :: String.t() | no_return()
  def get!(key) do
    case get(key) do
      nil -> raise ArgumentError, "Configuration key #{inspect(key)} not found"
      value -> value
    end
  end

  @doc """
  Returns `true` when the key exists and the value is non-empty.

  ## Examples

      iex> JidoKeys.has?(:my_api_key)
      true

      iex> JidoKeys.has?(:missing_key)
      false

  """
  @spec has?(key()) :: boolean()
  def has?(key) do
    get(key) != nil
  end

  @doc """
  Returns the list of all loaded environment keys (as strings).

  ## Examples

      iex> JidoKeys.list()
      ["openai_api_key", "database_url", "secret_key_base"]

  """
  @spec list() :: [String.t()]
  def list do
    GenServer.call(JidoKeys.Server, :list)
  end

  @doc """
  Returns true when the key is present **and** its value is not nil or an empty string.

  ## Examples

      iex> JidoKeys.has_value?(:my_api_key)
      true

      iex> JidoKeys.has_value?(:empty_key)
      false

  """
  @spec has_value?(key()) :: boolean()
  def has_value?(key) do
    get(key)
    |> not_empty?()
  end

  @doc false
  @spec not_empty?(any()) :: boolean()
  defp not_empty?(nil), do: false
  defp not_empty?(""), do: false
  defp not_empty?(_), do: true

  @doc """
  Sets a configuration value in the session store.

  ## Examples

      iex> JidoKeys.put(:my_test_key, "test_value")
      :ok

      iex> JidoKeys.put("another_key", "another_value")
      :ok

  """
  @spec put(key(), String.t()) :: :ok
  def put(key, value) when is_binary(value) do
    GenServer.call(JidoKeys.Server, {:put, key, value})
  end

  @doc """
  Reloads configuration from environment variables and files.

  Optional opts can be provided for future extensions.

  ## Examples

      iex> JidoKeys.reload()
      :ok

      iex> JidoKeys.reload(force: true)
      :ok

  """
  @spec reload(keyword()) :: :ok
  def reload(opts \\ []) do
    GenServer.cast(JidoKeys.Server, {:reload, opts})
  end

  @doc """
  Safely converts a normalized string key to an atom if it's a known LLM key.

  This prevents memory leaks by only allowing predefined LLM keys to be converted to atoms.
  Unknown keys are returned as strings.

  ## Examples

      iex> JidoKeys.to_llm_atom("openai_api_key")
      :openai_api_key

      iex> JidoKeys.to_llm_atom("anthropic_api_key")
      :anthropic_api_key

      iex> JidoKeys.to_llm_atom("unknown_key")
      "unknown_key"

  """
  @spec to_llm_atom(String.t()) :: atom() | String.t()
  def to_llm_atom(key) when is_binary(key) do
    JidoKeys.Server.to_llm_atom(key)
  end
end
