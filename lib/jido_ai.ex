defmodule Jido.AI do
  @moduledoc """
  High-level AI interface with ergonomic APIs for chat, models, and configuration.

  This module provides a simplified facade for common AI operations, including:
  - Provider configuration and API key management
  - Model creation and configuration
  - Chat completion and streaming

  ## Configuration API

      # Get API keys for different providers
      Jido.AI.api_key(:openai)
      Jido.AI.api_key(:anthropic)

      # Get model names with defaults
      Jido.AI.model_name(:openai)  # "gpt-4o"
      Jido.AI.model_name(:anthropic)  # "claude-3-5-sonnet-20241022"

      # Get provider configuration
      Jido.AI.provider_config(:openai)

      # Get any configuration key
      Jido.AI.config(:max_tokens, 1000)

  ## Model and Chat API

      # Create models
      model = Jido.AI.model(:openai, model: "gpt-4o")

      # Chat completions
      Jido.AI.chat(model, messages)
      Jido.AI.stream(model, messages)

  """

  alias Jido.AI.Keyring

  # ===========================================================================
  # Configuration API - Simple facades for common operations
  # ===========================================================================

  @doc """
  Gets the API key for a specific provider.

  ## Parameters

    * `provider` - The AI provider (default: :openai)

  ## Examples

      Jido.AI.api_key(:openai)
      Jido.AI.api_key(:anthropic)

  """
  @spec api_key(atom()) :: String.t() | nil
  def api_key(provider \\ :openai) do
    Keyring.get(Keyring, {provider, :api_key})
  end

  @doc """
  Gets the default model name for a specific provider.

  ## Parameters

    * `provider` - The AI provider (default: :openai)

  ## Examples

      Jido.AI.model_name(:openai)     # "gpt-4o"
      Jido.AI.model_name(:anthropic)  # "claude-3-5-sonnet-20241022"

  """
  @spec model_name(atom()) :: String.t()
  def model_name(provider \\ :openai) do
    default_model =
      case provider do
        :openai -> "gpt-4o"
        :anthropic -> "claude-3-5-sonnet-20241022"
        :azure -> "gpt-4o"
        :ollama -> "llama3.2"
        _ -> "gpt-4o"
      end

    Keyring.get(Keyring, {provider, :model}, default_model)
  end

  @doc """
  Gets the complete configuration for a specific provider.

  ## Parameters

    * `provider` - The AI provider

  ## Examples

      Jido.AI.provider_config(:openai)
      # %{api_key: "sk-...", model: "gpt-4o", base_url: "https://api.openai.com/v1"}

  """
  @spec provider_config(atom()) :: map()
  def provider_config(provider) do
    Keyring.get(Keyring, provider, %{})
  end

  @doc """
  Gets a configuration value with an optional default.

  This is the most general configuration accessor.

  ## Parameters

    * `key` - The configuration key (atom)
    * `default` - Default value if key not found (default: nil)

  ## Examples

      Jido.AI.config(:max_tokens, 1000)
      Jido.AI.config(:temperature, 0.7)

  """
  @spec config(atom(), term()) :: term()
  def config(key, default \\ nil) do
    Keyring.get(Keyring, key, default)
  end

  # ===========================================================================
  # Session Management - Direct delegation to Keyring
  # ===========================================================================

  @doc """
  Sets a session-specific configuration value.

  ## Parameters

    * `key` - The configuration key (atom)
    * `value` - The value to store

  ## Examples

      Jido.AI.set_session_value(:temperature, 0.9)

  """
  @spec set_session_value(atom(), term()) :: :ok
  def set_session_value(key, value) do
    Keyring.set_session_value(Keyring, key, value)
  end

  @doc """
  Gets a session-specific configuration value.

  ## Parameters

    * `key` - The configuration key (atom)
    * `pid` - Process ID (default: current process)

  """
  @spec get_session_value(atom(), pid()) :: term() | nil
  def get_session_value(key, pid \\ self()) do
    Keyring.get_session_value(Keyring, key, pid)
  end

  @doc """
  Clears a session-specific configuration value.

  ## Parameters

    * `key` - The configuration key (atom)
    * `pid` - Process ID (default: current process)

  """
  @spec clear_session_value(atom(), pid()) :: :ok
  def clear_session_value(key, pid \\ self()) do
    Keyring.clear_session_value(Keyring, key, pid)
  end

  @doc """
  Clears all session-specific configuration values for the current process.

  ## Parameters

    * `pid` - Process ID (default: current process)

  """
  @spec clear_all_session_values(pid()) :: :ok
  def clear_all_session_values(pid \\ self()) do
    Keyring.clear_all_session_values(Keyring, pid)
  end

  # ===========================================================================
  # Backward compatibility with cleaner names
  # ===========================================================================

  @doc """
  Gets a configuration value (alias for config/2).

  ## Examples

      Jido.AI.get(:my_setting)
      Jido.AI.get(:my_setting, "default")

  """
  @spec get(atom(), term()) :: term()
  def get(key, default \\ nil) do
    config(key, default)
  end

  @doc """
  Lists all available configuration keys.

  Returns a list of atoms representing available configuration keys.
  """
  @spec list_keys() :: [atom()]
  def list_keys do
    Keyring.list(Keyring)
  end
end
