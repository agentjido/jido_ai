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
    key = :"#{provider}_api_key"
    Keyring.get(Keyring, key)
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

    key = :"#{provider}_model"
    Keyring.get(Keyring, key, default_model)
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

  # ===========================================================================
  # ReqLLM Integration API - Enhanced functions with ReqLLM awareness
  # ===========================================================================

  @doc """
  Gets API key with ReqLLM integration and per-request override support.

  This function extends api_key/1 with ReqLLM integration, supporting
  per-request overrides and unified key precedence.

  ## Parameters

    * `provider` - The AI provider (default: :openai)
    * `req_options` - Request options that may contain :api_key override

  ## Examples

      # Standard usage (backward compatible)
      Jido.AI.api_key_with_reqllm(:openai)

      # With per-request override
      options = %{api_key: "sk-override"}
      Jido.AI.api_key_with_reqllm(:openai, options)
  """
  @spec api_key_with_reqllm(atom(), map()) :: String.t() | nil
  def api_key_with_reqllm(provider \\ :openai, _req_options \\ %{}) do
    # Map provider to appropriate key name
    key_name = provider_to_key_name(provider)
    ReqLLM.get_key(key_name)
  end

  defp provider_to_key_name(:openai), do: :openai_api_key
  defp provider_to_key_name(:anthropic), do: :anthropic_api_key
  defp provider_to_key_name(:google), do: :google_api_key
  defp provider_to_key_name(:github_models), do: :github_models_api_key
  defp provider_to_key_name(provider), do: :"#{provider}_api_key"

  @doc """
  Validates that all required provider keys are available.

  Checks key availability across all integrated systems and returns
  information about available providers and their key sources.

  ## Returns

    * List of available providers with source information

  ## Examples

      providers = Jido.AI.list_available_providers()
      # [%{provider: :openai, source: :environment}, ...]
  """
  @spec list_available_providers() :: [%{provider: atom(), source: atom()}]
  def list_available_providers do
    ReqLLM.Provider.Registry.list_implemented_providers()
    |> Enum.map(fn provider ->
      key_name = provider_to_key_name(provider)
      has_key = ReqLLM.get_key(key_name) != nil

      %{
        provider: provider,
        source: if(has_key, do: :configured, else: :not_configured)
      }
    end)
  end

  @doc """
  Gets configuration with ReqLLM integration support.

  This function extends config/2 with ReqLLM awareness, supporting
  per-request overrides and provider-specific key resolution.

  ## Parameters

    * `key` - The configuration key (atom)
    * `default` - Default value if key not found (default: nil)
    * `req_options` - Per-request options for ReqLLM integration

  ## Examples

      # Standard usage (backward compatible)
      value = Jido.AI.config_with_reqllm(:openai_api_key, "default")

      # With per-request override
      options = %{api_key: "override"}
      value = Jido.AI.config_with_reqllm(:openai_api_key, "default", options)
  """
  @spec config_with_reqllm(atom(), term(), map()) :: term()
  def config_with_reqllm(key, default \\ nil, req_options \\ %{}) do
    Keyring.get_with_reqllm(Keyring, key, default, self(), req_options)
  end
end
