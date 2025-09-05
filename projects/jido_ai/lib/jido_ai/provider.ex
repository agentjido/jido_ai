defmodule Jido.AI.Provider do
  @moduledoc """
  Module for managing AI providers.

  This struct represents an AI provider with configuration and models
  as defined by the models.dev schema specification.
  """
  use TypedStruct

  alias Jido.AI.Error.Invalid
  alias Jido.AI.Model
  alias Kagi

  @derive {Jason.Encoder, only: [:id, :name, :base_url, :env, :doc]}

  typedstruct do
    field(:id, atom())
    field(:name, String.t())
    field(:base_url, String.t())
    field(:env, [atom()])
    field(:doc, String.t())
    field(:models, %{String.t() => Model.t()})
  end

  @schema NimbleOptions.new!(
            id: [type: :atom, required: true],
            name: [type: :string, required: true],
            base_url: [type: :string, required: true],
            env: [type: {:list, :atom}, required: true],
            doc: [type: :string, required: true],
            models: [type: :map, required: true]
          )

  @doc """
  Validates that a provider struct conforms to the schema requirements using NimbleOptions.
  """
  @spec validate(t()) :: {:ok, t()} | {:error, NimbleOptions.ValidationError.t()}
  def validate(%__MODULE__{} = provider) do
    provider_map = Map.from_struct(provider)

    case NimbleOptions.validate(provider_map, @schema) do
      {:ok, _validated} -> {:ok, provider}
      error -> error
    end
  end

  @doc """
  Gets an environment variable value for a provider using the Keyring.

  Uses the provider's `env` field to determine which environment variable names to check.
  Returns the first non-nil value found from the list of environment variable names.

  ## Parameters

    * `provider` - The provider struct
    * `keyring_server` - The Keyring server to query (default: Jido.AI.Keyring)

  Returns `{:ok, value}` if found, `{:error, Error.t()}` if not found.
  """
  @spec get_key(t(), GenServer.server()) :: {:ok, String.t()} | {:error, Exception.t()}
  def get_key(%__MODULE__{env: env_vars, id: provider_id}, keyring_server \\ Kagi) do
    case find_env_value(env_vars, keyring_server) do
      nil ->
        {:error,
         Invalid.Parameter.exception(
           parameter:
             "Environment variable for provider '#{provider_id}'. Expected one of: #{Enum.join(env_vars, ", ")}"
         )}

      value ->
        {:ok, value}
    end
  end

  @doc """
  Validates that a provider has its required environment variable set.

  ## Parameters

    * `provider` - The provider struct
    * `keyring_server` - The Keyring server to query (default: Jido.AI.Keyring)

  Returns `{:ok, provider}` if valid, `{:error, Error.t()}` if invalid.
  """
  @spec validate_key(t(), GenServer.server()) :: {:ok, t()} | {:error, Exception.t()}
  def validate_key(%__MODULE__{} = provider, keyring_server \\ Kagi) do
    case get_key(provider, keyring_server) do
      {:ok, _value} -> {:ok, provider}
      {:error, _} = error -> error
    end
  end

  @doc """
  Validates that a provider has its required environment variable set.
  Raises an exception if validation fails.

  ## Parameters

    * `provider` - The provider struct
    * `keyring_server` - The Keyring server to query (default: Jido.AI.Keyring)

  Returns the provider if valid, raises exception if invalid.
  """
  @spec validate_key!(t(), GenServer.server()) :: t()
  def validate_key!(provider, keyring_server \\ Kagi) do
    case validate_key(provider, keyring_server) do
      {:ok, provider} -> provider
      {:error, error} -> raise error
    end
  end

  @doc false
  @spec find_env_value([atom()], GenServer.server()) :: String.t() | nil
  defp find_env_value(env_vars, keyring_server) do
    Enum.find_value(env_vars, fn env_var ->
      case Kagi.get_env_value(keyring_server, env_var) do
        nil -> nil
        value when is_binary(value) and value != "" -> value
        _ -> nil
      end
    end)
  end
end
