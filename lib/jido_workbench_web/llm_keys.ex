defmodule JidoWorkbenchWeb.LLMKeys do
  @moduledoc """
  Handles management and access of LLM API keys with session-level overrides.
  """

  require Logger
  alias JidoWorkbench.LLMKeys, as: KeyStore

  @doc """
  Returns the list of available LLM key settings.
  """
  def settings, do: KeyStore.settings()

  @doc """
  Gets an LLM API key, checking session first, then falling back to environment.
  """
  def get_key(key_type, session) when is_atom(key_type) do
    case Enum.find(settings(), &(&1.key == key_type)) do
      nil ->
        raise ArgumentError, "Unknown key type: #{inspect(key_type)}"

      setting ->
        # Check session first, then fall back to environment
        session[setting.session_key] ||
          KeyStore.get_env_key(key_type) ||
          setting.default
    end
  end

  @doc """
  Puts an LLM API key into the session.
  """
  def put_key(key_type, session, value) when is_atom(key_type) do
    case Enum.find(settings(), &(&1.key == key_type)) do
      nil ->
        raise ArgumentError, "Unknown key type: #{inspect(key_type)}"

      setting ->
        Map.put(session, setting.session_key, value)
    end
  end

  @doc """
  Validates if a key exists and is non-empty.
  """
  def has_valid_key?(key), do: KeyStore.has_valid_key?(key)

  @doc """
  Loads all settings with their current values from session and environment.
  """
  def load_settings(session) do
    Enum.map(settings(), fn setting ->
      value = get_key(setting.key, session)
      Map.put(setting, :value, value)
    end)
  end

  @doc """
  Tests a key by making an API request.
  Returns a tuple with :ok or :error and a message.
  """
  def test_key(key_type, key) do
    KeyStore.test_key(key_type, key)
  end
end
