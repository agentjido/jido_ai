defmodule Jido.AI.ReqLlmBridge.KeyringIntegration do
  @moduledoc """
  Integration module for bridging Jido.AI.Keyring with ReqLLM's key management system.

  This module provides seamless integration between Jido's hierarchical key management
  and ReqLLM's provider-specific key resolution while maintaining full backward
  compatibility with existing Keyring APIs.

  ## Key Features

  - **Unified Key Precedence**: Integrates Jido session values with ReqLLM's key hierarchy
  - **Provider Key Mapping**: Automatic mapping between Jido keys and ReqLLM provider keys
  - **Session Preservation**: Maintains process-specific session isolation
  - **Per-Request Overrides**: Supports ReqLLM's per-request key overrides
  - **Backward Compatibility**: All existing Keyring APIs work unchanged

  ## Architecture

  The integration implements a unified key precedence system:
  1. Jido session values (highest priority - process-specific)
  2. ReqLLM per-request options (request-specific)
  3. ReqLlmBridge.Keys delegation (env vars, app config, JidoKeys)
  4. Default values (lowest priority)

  ## Usage

      # Standard Keyring usage works unchanged
      api_key = Jido.AI.Keyring.get(:openai_api_key, "default")

      # Per-request overrides work with ReqLLM calls
      options = %{api_key: "override-key"}
      key = KeyringIntegration.get_key_for_request(:openai, options)

      # Provider mapping works transparently
      key = KeyringIntegration.resolve_provider_key(:openai_api_key, :openai)
  """

  require Logger
  alias Jido.AI.Keyring

  # Provider key mappings between Jido keys and ReqLLM provider identifiers
  @provider_key_mappings %{
    openai_api_key: %{
      jido_key: :openai_api_key,
      reqllm_provider: :openai,
      env_var: "OPENAI_API_KEY",
      reqllm_key: :openai_api_key
    },
    anthropic_api_key: %{
      jido_key: :anthropic_api_key,
      reqllm_provider: :anthropic,
      env_var: "ANTHROPIC_API_KEY",
      reqllm_key: :anthropic_api_key
    },
    openrouter_api_key: %{
      jido_key: :openrouter_api_key,
      reqllm_provider: :openrouter,
      env_var: "OPENROUTER_API_KEY",
      reqllm_key: :openrouter_api_key
    },
    google_api_key: %{
      jido_key: :google_api_key,
      reqllm_provider: :google,
      env_var: "GOOGLE_API_KEY",
      reqllm_key: :google_api_key
    },
    cloudflare_api_key: %{
      jido_key: :cloudflare_api_key,
      reqllm_provider: :cloudflare,
      env_var: "CLOUDFLARE_API_KEY",
      reqllm_key: :cloudflare_api_key
    }
  }

  @doc """
  Gets a key using unified precedence across Jido.AI.Keyring and ReqLLM systems.

  This function implements the core integration logic, checking multiple key sources
  in the correct precedence order while maintaining backward compatibility.

  ## Parameters

    * `server` - The Keyring server (default: Jido.AI.Keyring)
    * `key` - The key to look up (atom)
    * `default` - Default value if not found
    * `pid` - Process ID for session lookup (default: current process)
    * `req_options` - Per-request options that may contain key overrides

  ## Returns

    * The key value if found, otherwise the default value

  ## Examples

      # Standard usage (unchanged from existing API)
      api_key = get(Jido.AI.Keyring, :openai_api_key, "default")

      # With per-request override
      options = %{api_key: "override-key"}
      api_key = get(Jido.AI.Keyring, :openai_api_key, "default", self(), options)
  """
  @spec get(GenServer.server(), atom(), term(), pid(), map()) :: term()
  def get(server \\ Keyring, key, default \\ nil, pid \\ self(), req_options \\ %{})
      when is_atom(key) do
    # Step 1: Check Jido session values first (highest precedence)
    case Keyring.get_session_value(server, key, pid) do
      nil ->
        # Step 2: Check per-request overrides for ReqLLM calls
        case get_per_request_key(key, req_options) do
          nil ->
            # Step 3: Delegate to unified key resolution
            resolve_unified_key(key, default)

          value ->
            log_key_resolution(key, :per_request_override)
            value
        end

      session_value ->
        log_key_resolution(key, :session_value)
        session_value
    end
  end

  @doc """
  Gets environment-only values with ReqLLM integration.

  Maintains the existing get_env_value API while adding ReqLLM awareness
  for better integration with provider-specific environment variables.

  ## Parameters

    * `server` - The Keyring server
    * `key` - The key to look up
    * `default` - Default value if not found

  ## Returns

    * Environment value if found, otherwise default
  """
  @spec get_env_value(GenServer.server(), atom(), term()) :: term()
  def get_env_value(server \\ Keyring, key, default \\ nil) when is_atom(key) do
    # First try standard Jido.AI.Keyring environment lookup
    case Keyring.get_env_value(server, key, default) do
      ^default ->
        # If not found, try ReqLLM environment variable resolution
        resolve_reqllm_env_key(key, default)

      value ->
        value
    end
  end

  @doc """
  Resolves provider-specific keys for ReqLLM integration.

  Maps Jido key names to ReqLLM provider-specific keys and resolves
  them using ReqLLM's key resolution system.

  ## Parameters

    * `jido_key` - The Jido key name (e.g., :openai_api_key)
    * `reqllm_provider` - The ReqLLM provider atom (e.g., :openai)
    * `default` - Default value if not found

  ## Returns

    * Resolved key value or default

  ## Examples

      key = resolve_provider_key(:openai_api_key, :openai, "fallback")
  """
  @spec resolve_provider_key(atom(), atom(), term()) :: term()
  def resolve_provider_key(jido_key, reqllm_provider, default \\ nil) do
    case Map.get(@provider_key_mappings, jido_key) do
      nil ->
        # If no mapping exists, fall back to direct ReqLLM lookup
        resolve_reqllm_key(reqllm_provider, default)

      _mapping ->
        # Use ReqLLM key resolution with provider mapping
        case resolve_reqllm_key(reqllm_provider, nil) do
          nil -> default
          value -> value
        end
    end
  end

  @doc """
  Gets key for ReqLLM request with full precedence integration.

  This function is designed to be called from ReqLLM request functions
  to ensure proper key resolution with Jido session values taking precedence.

  ## Parameters

    * `reqllm_provider` - ReqLLM provider atom
    * `req_options` - Request options that may contain api_key override
    * `default` - Default value

  ## Returns

    * Resolved key value for the ReqLLM request
  """
  @spec get_key_for_request(atom(), map(), term()) :: term()
  def get_key_for_request(reqllm_provider, req_options \\ %{}, default \\ nil) do
    # Find the corresponding Jido key for this provider
    jido_key = provider_to_jido_key(reqllm_provider)

    # Use unified resolution with per-request options
    get(Keyring, jido_key, default, self(), req_options)
  end

  @doc """
  Lists all available keys with ReqLLM provider information.

  Extends the standard list function to include ReqLLM provider mappings
  and additional metadata about key sources and availability.

  ## Parameters

    * `server` - The Keyring server

  ## Returns

    * List of available keys with optional ReqLLM metadata
  """
  @spec list_with_providers(GenServer.server()) :: [atom()]
  def list_with_providers(server \\ Keyring) do
    # Get standard Keyring keys
    jido_keys = Keyring.list(server)

    # Add any ReqLLM-specific keys that might be available
    reqllm_keys = get_additional_reqllm_keys()

    # Combine and deduplicate
    (jido_keys ++ reqllm_keys)
    |> Enum.uniq()
    |> Enum.sort()
  end

  @doc """
  Validates key availability across both Jido and ReqLLM systems.

  Checks if a key is available in any of the integrated systems and
  provides information about the source and availability.

  ## Parameters

    * `key` - The key to validate
    * `reqllm_provider` - Optional ReqLLM provider for validation

  ## Returns

    * `{:ok, source}` if key is available with source information
    * `{:error, :not_found}` if key is not available in any system
  """
  @spec validate_key_availability(atom(), atom() | nil) :: {:ok, atom()} | {:error, :not_found}
  def validate_key_availability(key, reqllm_provider \\ nil) do
    cond do
      # Check if available in Jido session values
      Keyring.get_session_value(key) != nil ->
        {:ok, :session}

      # Check if available in Jido environment
      Keyring.get_env_value(key) != nil ->
        {:ok, :environment}

      # Check ReqLLM availability if provider specified
      reqllm_provider && resolve_reqllm_key(reqllm_provider, nil) != nil ->
        {:ok, :reqllm}

      true ->
        {:error, :not_found}
    end
  end

  # Private helper functions

  # Gets per-request key override from options
  defp get_per_request_key(_key, %{api_key: api_key}) when is_binary(api_key) and api_key != "" do
    api_key
  end

  defp get_per_request_key(_key, _options), do: nil

  # Resolves key using unified approach across systems
  defp resolve_unified_key(key, default) do
    case Map.get(@provider_key_mappings, key) do
      nil ->
        # No provider mapping, use standard resolution
        resolve_standard_key(key, default)

      mapping ->
        # Try ReqLLM resolution first, then fall back
        case resolve_reqllm_key(mapping.reqllm_provider, nil) do
          nil ->
            resolve_standard_key(key, default)

          value ->
            log_key_resolution(key, :reqllm)
            value
        end
    end
  end

  # Standard key resolution (existing Keyring behavior)
  defp resolve_standard_key(key, default) do
    case Keyring.get_env_value(Keyring, key, nil) do
      nil ->
        log_key_resolution(key, :default)
        default

      value ->
        log_key_resolution(key, :environment)
        value
    end
  end

  # ReqLLM environment variable resolution
  defp resolve_reqllm_env_key(key, default) do
    case Map.get(@provider_key_mappings, key) do
      nil -> default
      mapping -> System.get_env(mapping.env_var) || default
    end
  end

  # ReqLLM key resolution using ReqLlmBridge.Keys
  defp resolve_reqllm_key(provider, default) do
    # Use ReqLlmBridge.Keys with provider atom, falling back to default
    case ReqLLM.Keys.get(provider, default) do
      {:ok, key, _source} -> key
      key when is_binary(key) -> key
      _ -> default
    end
  rescue
    _ -> default
  end

  # Maps ReqLLM provider atom to corresponding Jido key
  defp provider_to_jido_key(reqllm_provider) do
    case Enum.find(@provider_key_mappings, fn {_jido_key, mapping} ->
           mapping.reqllm_provider == reqllm_provider
         end) do
      {jido_key, _mapping} -> jido_key
      # fallback pattern
      nil -> :"#{reqllm_provider}_api_key"
    end
  end

  # Gets additional keys that might be available through ReqLLM
  defp get_additional_reqllm_keys do
    @provider_key_mappings
    |> Map.values()
    |> Enum.map(& &1.jido_key)
  end

  # Optional logging for debugging key resolution
  defp log_key_resolution(key, source) do
    if Application.get_env(:jido_ai, :debug_key_resolution, false) do
      Logger.debug("[KeyringIntegration] Resolved #{key} from #{source}")
    end
  end
end
