defmodule ReqLLM.Config do
  @moduledoc """
  Configuration management for ReqLLM with layered key resolution.

  Provides a unified configuration system that layers values from multiple sources:
  1. **Kagi keyring** - Runtime session configuration (highest priority)
  2. **Mix application config** - Project-level configuration
  3. **Environment variables** - System-level configuration (lowest priority)

  ## Key Storage

      # Store API keys in Kagi keyring (case-insensitive)
      ReqLLM.Config.put_key(:openai_api_key, "sk-...")
      ReqLLM.Config.put_key("ANTHROPIC_API_KEY", "sk-ant-...")

  ## Configuration Retrieval

      # Get layered configuration values
      api_key = ReqLLM.Config.config([:openai, :api_key], "default-key")
      
      # Direct API key access (case-insensitive)
      ReqLLM.Config.api_key(:openai_api_key)
      ReqLLM.Config.api_key("OPENAI_API_KEY")

  ## Configuration Layers

  The `config/2` function checks sources in this order:

  1. **Kagi keyring** - `Kagi.get(keyspace_key)`
  2. **Mix config** - `Application.get_env(:req_llm, provider_config)`
  3. **Environment variables** - `System.get_env(env_var_name)`
  4. **Default value** - Provided fallback

  """

  alias Kagi

  @doc """
  Stores a configuration key in the Kagi keyring.

  Keys are normalized to lowercase atoms for consistent storage and retrieval.
  This enables case-insensitive key access throughout the system.

  ## Parameters

    * `key` - Configuration key (atom or string, case-insensitive)
    * `value` - Value to store (any term)

  ## Examples

      ReqLLM.Config.put_key(:openai_api_key, "sk-...")
      ReqLLM.Config.put_key("ANTHROPIC_API_KEY", "sk-ant-...")
      ReqLLM.Config.put_key(:OpenAI_API_Key, "sk-...")  # stored as :openai_api_key

  """
  @spec put_key(atom() | String.t(), term()) :: :ok
  def put_key(key, value) when is_atom(key) do
    normalized_key = 
      key
      |> Atom.to_string()
      |> String.downcase()
      |> String.to_atom()

    Kagi.put(normalized_key, value)
  end

  def put_key(key, value) when is_binary(key) do
    normalized_key = 
      key
      |> String.downcase()
      |> String.to_atom()

    Kagi.put(normalized_key, value)
  end

  @doc """
  Gets an API key from the keyring.

  Key lookup is case-insensitive and accepts both atoms and strings.
  This is a direct accessor to the Kagi keyring without fallbacks.

  ## Parameters

    * `key` - The configuration key (atom or string, case-insensitive)

  ## Examples

      ReqLLM.Config.api_key(:openai_api_key)
      ReqLLM.Config.api_key("ANTHROPIC_API_KEY")
      ReqLLM.Config.api_key("OpenAI_API_Key")

  """
  @spec api_key(atom() | String.t()) :: String.t() | nil
  def api_key(key) when is_atom(key) do
    normalized_key = 
      key
      |> Atom.to_string()
      |> String.downcase()
      |> String.to_atom()

    Kagi.get(normalized_key, nil)
  end

  def api_key(key) when is_binary(key) do
    normalized_key = 
      key
      |> String.downcase()
      |> String.to_atom()

    Kagi.get(normalized_key, nil)
  end

  @doc """
  Gets a configuration value with layered resolution.

  Checks multiple configuration sources in priority order:
  1. **Kagi keyring** - Runtime session configuration
  2. **Mix application config** - Project-level configuration  
  3. **Environment variables** - System-level configuration
  4. **Default value** - Provided fallback

  ## Parameters

    * `keyspace` - Key path as atom list (e.g., [:openai, :api_key])
    * `default` - Default value if key not found

  ## Examples

      # Look for API key in all sources
      ReqLLM.Config.config([:openai, :api_key], "default-key")
      
      # Look for model configuration
      ReqLLM.Config.config([:anthropic, :max_tokens], 1000)

      # Complex keyspace resolution
      ReqLLM.Config.config([:providers, :openai, :temperature], 0.7)

  ## Configuration Sources

  For keyspace `[:openai, :api_key]`, checks:

  1. **Kagi**: `openai_api_key` (atom key)
  2. **Mix config**: `Application.get_env(:req_llm, :openai)[:api_key]`
  3. **Environment**: `OPENAI_API_KEY` (uppercase with underscores)
  4. **Default**: Returns provided default value

  """
  @spec config(list(atom()), term()) :: term()
  def config(keyspace, default \\ nil) when is_list(keyspace) do
    # Try Kagi keyring first (highest priority)
    kagi_key = keyspace_to_kagi_key(keyspace)
    case Kagi.get(kagi_key) do
      nil -> check_mix_config(keyspace, default)
      value -> value
    end
  end

  # Private helper functions

  @spec keyspace_to_kagi_key(list(atom())) :: atom()
  defp keyspace_to_kagi_key(keyspace) do
    keyspace
    |> Enum.map(&Atom.to_string/1)
    |> Enum.join("_")
    |> String.downcase()
    |> String.to_atom()
  end

  @spec check_mix_config(list(atom()), term()) :: term()
  defp check_mix_config(keyspace, default) do
    # Try Mix application config (medium priority)
    case get_nested_config(:req_llm, keyspace) do
      nil -> check_env_var(keyspace, default)
      value -> value
    end
  end

  @spec get_nested_config(atom(), list(atom())) :: term() | nil
  defp get_nested_config(app, [root | rest]) do
    case Application.get_env(app, root) do
      nil -> nil
      config when is_list(config) -> get_in(config, rest)
      _ -> nil
    end
  end

  @spec check_env_var(list(atom()), term()) :: term()
  defp check_env_var(keyspace, default) do
    # Try environment variable (lowest priority, before default)
    env_var_name = keyspace_to_env_var(keyspace)
    case System.get_env(env_var_name) do
      nil -> default
      value -> value
    end
  end

  @spec keyspace_to_env_var(list(atom())) :: String.t()
  defp keyspace_to_env_var(keyspace) do
    keyspace
    |> Enum.map(&Atom.to_string/1)
    |> Enum.join("_")
    |> String.upcase()
  end
end
