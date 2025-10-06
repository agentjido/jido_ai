defmodule Jido.AI.ReqLlmBridge.Authentication do
  @moduledoc """
  Authentication bridge between Jido AI and ReqLLM's provider-specific authentication system.

  This module acts as a translation layer between Jido's session-based
  authentication hierarchy and ReqLLM's unified provider plugin system,
  ensuring seamless integration without changing existing authentication
  behavior from the user's perspective.

  ## Key Features

  - **Unified Authentication Resolution**: Bridges Jido's session-based precedence with ReqLLM's per-request options
  - **Provider Authentication Mapping**: Automatic mapping between Jido keys and ReqLLM provider identifiers
  - **Backward Compatibility**: All existing authentication APIs work unchanged
  - **Session Preservation**: Maintains process-specific session isolation
  - **Error Message Preservation**: Maps ReqLLM errors to existing Jido error formats

  ## Authentication Precedence

  The bridge implements a unified precedence system:
  1. Jido session values (highest priority - process-specific)
  2. ReqLLM per-request options (request-specific)
  3. ReqLlmBridge.Keys delegation (env vars, app config, JidoKeys)
  4. Default values (lowest priority)

  ## Usage

      # Standard authentication (unchanged from existing API)
      {:ok, headers, key} = Authentication.authenticate_for_provider(:openai, %{})

      # With per-request override
      options = %{api_key: "override-key"}
      {:ok, headers, key} = Authentication.authenticate_for_provider(:openai, options)

      # Provider-specific authentication
      {:ok, headers, key} = Authentication.authenticate_for_provider(:anthropic, %{})
  """

  require Logger
  alias Jido.AI.Keyring

  # Provider authentication mappings between Jido and ReqLLM systems
  @provider_auth_mappings %{
    openai: %{
      jido_key: :openai_api_key,
      reqllm_provider: :openai,
      env_var: "OPENAI_API_KEY",
      header_name: "authorization",
      header_format: :bearer_token,
      header_prefix: "Bearer ",
      additional_headers: %{}
    },
    anthropic: %{
      jido_key: :anthropic_api_key,
      reqllm_provider: :anthropic,
      env_var: "ANTHROPIC_API_KEY",
      header_name: "x-api-key",
      header_format: :api_key,
      header_prefix: "",
      additional_headers: %{"anthropic-version" => "2023-06-01"}
    },
    openrouter: %{
      jido_key: :openrouter_api_key,
      reqllm_provider: :openrouter,
      env_var: "OPENROUTER_API_KEY",
      header_name: "authorization",
      header_format: :bearer_token,
      header_prefix: "Bearer ",
      additional_headers: %{}
    },
    google: %{
      jido_key: :google_api_key,
      reqllm_provider: :google,
      env_var: "GOOGLE_API_KEY",
      header_name: "x-goog-api-key",
      header_format: :api_key,
      header_prefix: "",
      additional_headers: %{}
    },
    cloudflare: %{
      jido_key: :cloudflare_api_key,
      reqllm_provider: :cloudflare,
      env_var: "CLOUDFLARE_API_KEY",
      header_name: "x-auth-key",
      header_format: :api_key,
      header_prefix: "",
      additional_headers: %{}
    }
  }

  @doc """
  Authenticates a request for a specific provider using unified precedence.

  This function implements the core authentication bridge logic, resolving
  authentication across both Jido session values and ReqLLM's authentication
  chain while preserving existing behavior and error messages.

  ## Parameters

    * `provider` - The provider atom (e.g., :openai, :anthropic)
    * `req_options` - Request options that may contain api_key overrides
    * `session_pid` - Process ID for session lookup (default: current process)

  ## Returns

    * `{:ok, headers, key}` - Authentication headers and resolved key
    * `{:error, reason}` - Authentication error in Jido format

  ## Examples

      # Session authentication takes precedence
      Jido.AI.set_session_value(:openai_api_key, "session-key")
      {:ok, headers, "session-key"} = authenticate_for_provider(:openai, %{})

      # Per-request override works
      {:ok, headers, "request-key"} = authenticate_for_provider(:openai, %{api_key: "request-key"})

      # Provider-specific headers preserved
      {:ok, headers, key} = authenticate_for_provider(:anthropic, %{})
      assert headers["x-api-key"] == key
      assert headers["anthropic-version"] == "2023-06-01"
  """
  @spec authenticate_for_provider(atom(), map(), pid()) ::
          {:ok, map(), String.t()} | {:error, String.t()}
  def authenticate_for_provider(provider, req_options \\ %{}, session_pid \\ self())
      when is_atom(provider) do
    case get_provider_mapping(provider) do
      nil ->
        # Unknown provider - use generic authentication
        authenticate_generic_provider(provider, req_options, session_pid)

      mapping ->
        # Known provider - use mapped authentication
        authenticate_mapped_provider(provider, mapping, req_options, session_pid)
    end
  end

  @doc """
  Gets authentication headers for a provider using Jido's existing patterns.

  This function preserves the exact header formatting that existing Jido
  provider modules expect, ensuring backward compatibility.

  ## Parameters

    * `provider` - The provider atom
    * `opts` - Options that may contain api_key (for backward compatibility)

  ## Returns

    * Map of authentication headers in the format expected by existing provider modules

  ## Examples

      opts = [api_key: "test-key"]
      headers = get_authentication_headers(:openai, opts)
      assert headers["Authorization"] == "Bearer test-key"

      headers = get_authentication_headers(:anthropic, opts)
      assert headers["x-api-key"] == "test-key"
      assert headers["anthropic-version"] == "2023-06-01"
  """
  @spec get_authentication_headers(atom(), keyword() | map()) :: map()
  def get_authentication_headers(provider, opts \\ []) when is_atom(provider) do
    # Convert keyword list to map if needed for consistency
    opts_map = if is_list(opts), do: Enum.into(opts, %{}), else: opts

    case authenticate_for_provider(provider, opts_map) do
      {:ok, headers, _key} -> headers
      {:error, _reason} -> get_base_headers(provider)
    end
  end

  @doc """
  Validates authentication for a provider using existing Jido validation logic.

  Preserves the exact validation behavior and error messages that existing
  Jido provider modules expect.

  ## Parameters

    * `provider` - The provider atom
    * `opts` - Options that may contain authentication parameters

  ## Returns

    * `:ok` if authentication is valid
    * `{:error, reason}` with Jido-compatible error message

  ## Examples

      opts = [api_key: "valid-key"]
      :ok = validate_authentication(:openai, opts)

      opts = [api_key: ""]
      {:error, "API key is empty"} = validate_authentication(:openai, opts)
  """
  @spec validate_authentication(atom(), keyword() | map()) :: :ok | {:error, String.t()}
  def validate_authentication(provider, opts \\ []) when is_atom(provider) do
    opts_map = if is_list(opts), do: Enum.into(opts, %{}), else: opts

    case authenticate_for_provider(provider, opts_map) do
      {:ok, _headers, key} when is_binary(key) and key != "" -> :ok
      {:ok, _headers, _key} -> {:error, "API key is empty"}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Resolves provider authentication using ReqLLM's key resolution as fallback.

  This function bridges Jido's session-based authentication with ReqLLM's
  unified key resolution while preserving Jido's precedence hierarchy.

  ## Parameters

    * `provider` - The provider atom
    * `req_options` - Request options for ReqLLM
    * `session_pid` - Process ID for session lookup

  ## Returns

    * `{:ok, key, source}` with source tracking
    * `{:error, reason}` if no authentication found
  """
  @spec resolve_provider_authentication(atom(), map(), pid()) ::
          {:ok, String.t(), atom()} | {:error, String.t()}
  def resolve_provider_authentication(provider, req_options \\ %{}, session_pid \\ self()) do
    case get_provider_mapping(provider) do
      nil ->
        # Unknown provider - use ReqLLM directly
        resolve_reqllm_authentication(provider, req_options)

      mapping ->
        # Known provider - use unified resolution with session precedence
        case Keyring.get_session_value(:default, mapping.jido_key, session_pid) do
          nil ->
            # No session value - delegate to ReqLLM
            case resolve_reqllm_authentication(mapping.reqllm_provider, req_options) do
              {:ok, key, source} -> {:ok, key, source}
              {:error, _} -> resolve_keyring_fallback(mapping, req_options)
            end

          session_key ->
            # Session value takes precedence
            {:ok, session_key, :session}
        end
    end
  end

  # Private helper functions

  # Gets provider mapping configuration
  defp get_provider_mapping(provider) do
    Map.get(@provider_auth_mappings, provider)
  end

  # Authenticates using provider mapping configuration
  defp authenticate_mapped_provider(provider, mapping, req_options, session_pid) do
    case resolve_provider_authentication(provider, req_options, session_pid) do
      {:ok, key, source} ->
        headers = format_authentication_headers(mapping, key)
        log_authentication_resolution(provider, key, source)
        {:ok, headers, key}

      {:error, reason} ->
        log_authentication_error(provider, reason)
        {:error, map_reqllm_error_to_jido(reason, mapping.env_var)}
    end
  end

  # Authenticates unknown provider using generic patterns
  defp authenticate_generic_provider(provider, req_options, session_pid) do
    # Use generic key pattern for unknown providers
    jido_key = :"#{provider}_api_key"
    env_var = String.upcase("#{provider}_api_key")

    case Keyring.get_session_value(:default, jido_key, session_pid) do
      nil ->
        # No session value - try ReqLLM
        case resolve_reqllm_authentication(provider, req_options) do
          {:ok, key, source} ->
            headers = %{"authorization" => "Bearer #{key}"}
            log_authentication_resolution(provider, key, source)
            {:ok, headers, key}

          {:error, reason} ->
            # Try Keyring fallback
            case Keyring.get_env_value(:default, jido_key, nil) do
              nil ->
                log_authentication_error(provider, reason)
                {:error, "API key not found: #{env_var}"}

              key ->
                headers = %{"authorization" => "Bearer #{key}"}
                log_authentication_resolution(provider, key, :keyring)
                {:ok, headers, key}
            end
        end

      session_key ->
        headers = %{"authorization" => "Bearer #{session_key}"}
        log_authentication_resolution(provider, session_key, :session)
        {:ok, headers, session_key}
    end
  end

  # Formats authentication headers according to provider requirements
  defp format_authentication_headers(mapping, key) do
    auth_header =
      case mapping.header_format do
        :bearer_token -> "#{mapping.header_prefix}#{key}"
        :api_key -> "#{mapping.header_prefix}#{key}"
      end

    base_headers = %{mapping.header_name => auth_header}
    Map.merge(base_headers, mapping.additional_headers)
  end

  # Gets base headers without authentication for a provider
  defp get_base_headers(provider) do
    case get_provider_mapping(provider) do
      nil -> %{"Content-Type" => "application/json"}
      mapping -> mapping.additional_headers
    end
  end

  # Resolves authentication using ReqLlmBridge.Keys
  defp resolve_reqllm_authentication(provider, req_options) do
    case ReqLLM.Keys.get(provider, req_options) do
      {:ok, key, source} -> {:ok, key, source}
      {:error, reason} -> {:error, reason}
    end
  rescue
    error -> {:error, "ReqLLM authentication error: #{inspect(error)}"}
  end

  # Resolves authentication using Keyring as fallback
  defp resolve_keyring_fallback(mapping, _req_options) do
    case Keyring.get_env_value(:default, mapping.jido_key, nil) do
      nil -> {:error, "API key not found: #{mapping.env_var}"}
      key -> {:ok, key, :keyring}
    end
  end

  # Maps ReqLLM errors to existing Jido error format
  defp map_reqllm_error_to_jido(reqllm_error, env_var) do
    case reqllm_error do
      ":api_key option or " <> _rest ->
        "API key not found: #{env_var}"

      error when is_binary(error) ->
        if String.contains?(error, "empty") do
          "API key is empty: #{env_var}"
        else
          "Authentication error: #{error}"
        end

      _ ->
        "API key not found: #{env_var}"
    end
  end

  # Optional logging for debugging authentication resolution
  defp log_authentication_resolution(provider, key, source) do
    if Application.get_env(:jido_ai, :debug_auth_resolution, false) do
      masked_key = mask_api_key(key)

      Logger.debug(
        "[Authentication] Resolved #{provider} authentication: #{masked_key} from #{source}"
      )
    end
  end

  # Optional logging for authentication errors
  defp log_authentication_error(provider, reason) do
    if Application.get_env(:jido_ai, :debug_auth_resolution, false) do
      Logger.debug("[Authentication] Failed to resolve #{provider} authentication: #{reason}")
    end
  end

  # Masks API key for safe logging
  defp mask_api_key(key) when is_binary(key) and byte_size(key) > 8 do
    prefix = String.slice(key, 0, 4)
    suffix = String.slice(key, -4, 4)
    "#{prefix}...#{suffix}"
  end

  defp mask_api_key(key) when is_binary(key), do: "***"
  defp mask_api_key(_), do: "nil"
end
