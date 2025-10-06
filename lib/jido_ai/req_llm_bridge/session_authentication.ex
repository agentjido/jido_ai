defmodule Jido.AI.ReqLlmBridge.SessionAuthentication do
  @moduledoc """
  Session-based authentication management for ReqLLM integration.

  This module bridges Jido's process-specific session authentication with
  ReqLLM's request-based authentication system, ensuring proper session
  isolation and per-process key management.

  ## Key Features

  - **Session Isolation**: Maintains strict process boundaries for session keys
  - **Per-Process Management**: Keys are isolated per-process with no leakage
  - **Session Precedence**: Session keys take priority over all other sources
  - **Process Cleanup**: Automatic cleanup on process termination

  ## Usage

      # Set session authentication for a provider
      SessionAuthentication.set_for_provider(:openai, "session-key")

      # Get session authentication with per-request override support
      {:session_auth, options} = SessionAuthentication.get_for_request(:openai, %{})

      # Clear session authentication
      SessionAuthentication.clear_for_provider(:openai)
  """

  alias Jido.AI.Keyring

  # Default Keyring server name
  @default_server :default

  @doc """
  Gets session authentication for a ReqLLM request.

  This function bridges session authentication with ReqLLM's per-request
  options, ensuring session keys take precedence while supporting overrides.

  ## Parameters

    * `provider` - The provider atom
    * `req_options` - Request options that may already contain api_key
    * `session_pid` - Process ID for session lookup (default: current process)

  ## Returns

    * `{:session_auth, options}` - Options with session key injected
    * `{:no_session_auth}` - No session authentication found

  ## Examples

      # Session authentication found
      set_for_provider(:openai, "session-key")
      {:session_auth, options} = get_for_request(:openai, %{})
      assert options[:api_key] == "session-key"

      # No session authentication
      clear_for_provider(:openai)
      {:no_session_auth} = get_for_request(:openai, %{})
  """
  @spec get_for_request(atom(), map(), pid(), GenServer.server()) ::
          {:session_auth, map()} | {:no_session_auth}
  def get_for_request(
        provider,
        req_options \\ %{},
        session_pid \\ self(),
        server \\ @default_server
      ) do
    case Keyring.get_session_value(server, provider_key(provider), session_pid) do
      nil ->
        {:no_session_auth}

      session_key ->
        # Session key overrides any per-request key
        updated_options = Map.put(req_options, :api_key, session_key)
        {:session_auth, updated_options}
    end
  end

  @doc """
  Sets session authentication for a provider.

  This function sets a process-specific authentication key that takes
  precedence over all other authentication sources.

  ## Parameters

    * `provider` - The provider atom
    * `key` - The API key to set
    * `session_pid` - Process ID for session (default: current process)

  ## Returns

    * `:ok` - Authentication set successfully

  ## Examples

      SessionAuthentication.set_for_provider(:openai, "sk-123456")
      :ok
  """
  @spec set_for_provider(atom(), String.t(), pid(), GenServer.server()) :: :ok
  def set_for_provider(provider, key, session_pid \\ self(), server \\ @default_server)
      when is_atom(provider) and is_binary(key) do
    Keyring.set_session_value(server, provider_key(provider), key, session_pid)
  end

  @doc """
  Clears session authentication for a provider.

  This function removes the process-specific authentication key for a provider.

  ## Parameters

    * `provider` - The provider atom
    * `session_pid` - Process ID for session (default: current process)

  ## Returns

    * `:ok` - Authentication cleared successfully

  ## Examples

      SessionAuthentication.clear_for_provider(:openai)
      :ok
  """
  @spec clear_for_provider(atom(), pid(), GenServer.server()) :: :ok
  def clear_for_provider(provider, session_pid \\ self(), server \\ @default_server)
      when is_atom(provider) do
    Keyring.clear_session_value(server, provider_key(provider), session_pid)
  end

  @doc """
  Checks if session authentication exists for a provider.

  ## Parameters

    * `provider` - The provider atom
    * `session_pid` - Process ID for session (default: current process)

  ## Returns

    * `true` if session authentication exists
    * `false` otherwise

  ## Examples

      SessionAuthentication.set_for_provider(:openai, "key")
      true = SessionAuthentication.has_session_auth?(:openai)

      SessionAuthentication.clear_for_provider(:openai)
      false = SessionAuthentication.has_session_auth?(:openai)
  """
  @spec has_session_auth?(atom(), pid(), GenServer.server()) :: boolean()
  def has_session_auth?(provider, session_pid \\ self(), server \\ @default_server)
      when is_atom(provider) do
    case Keyring.get_session_value(server, provider_key(provider), session_pid) do
      nil -> false
      _ -> true
    end
  end

  @doc """
  Gets all providers with session authentication for a process.

  ## Parameters

    * `session_pid` - Process ID for session (default: current process)

  ## Returns

    * List of provider atoms that have session authentication

  ## Examples

      SessionAuthentication.set_for_provider(:openai, "key1")
      SessionAuthentication.set_for_provider(:anthropic, "key2")
      providers = SessionAuthentication.list_providers_with_auth()
      assert :openai in providers
      assert :anthropic in providers
  """
  @spec list_providers_with_auth(pid(), GenServer.server()) :: [atom()]
  def list_providers_with_auth(session_pid \\ self(), server \\ @default_server) do
    # Get all session values and extract provider names
    [:openai, :anthropic, :openrouter, :google, :cloudflare]
    |> Enum.filter(&has_session_auth?(&1, session_pid, server))
  end

  @doc """
  Clears all session authentication for a process.

  This function removes all provider authentication keys for a process,
  useful for cleanup or testing.

  ## Parameters

    * `session_pid` - Process ID for session (default: current process)

  ## Returns

    * `:ok` - All authentication cleared successfully

  ## Examples

      SessionAuthentication.clear_all()
      :ok
  """
  @spec clear_all(pid(), GenServer.server()) :: :ok
  def clear_all(session_pid \\ self(), server \\ @default_server) do
    Keyring.clear_all_session_values(server, session_pid)
  end

  @doc """
  Transfers session authentication to another process.

  This function is useful for passing authentication context to child
  processes or tasks while maintaining isolation.

  ## Parameters

    * `provider` - The provider atom
    * `from_pid` - Source process ID
    * `to_pid` - Destination process ID

  ## Returns

    * `:ok` if transfer successful
    * `{:error, :no_auth}` if no authentication to transfer

  ## Examples

      SessionAuthentication.set_for_provider(:openai, "key", self())
      {:ok, pid} = Task.start(fn -> receive do :stop -> :ok end end)
      :ok = SessionAuthentication.transfer(:openai, self(), pid)
  """
  @spec transfer(atom(), pid(), pid(), GenServer.server()) :: :ok | {:error, :no_auth}
  def transfer(provider, from_pid, to_pid, server \\ @default_server) when is_atom(provider) do
    case Keyring.get_session_value(server, provider_key(provider), from_pid) do
      nil ->
        {:error, :no_auth}

      key ->
        Keyring.set_session_value(server, provider_key(provider), key, to_pid)
        :ok
    end
  end

  @doc """
  Inherits all session authentication from parent process.

  Useful for child processes that need the same authentication context
  as their parent.

  ## Parameters

    * `parent_pid` - Parent process ID
    * `child_pid` - Child process ID (default: current process)

  ## Returns

    * List of providers that were inherited

  ## Examples

      # In parent process
      SessionAuthentication.set_for_provider(:openai, "key")

      # In child process
      inherited = SessionAuthentication.inherit_from(parent_pid)
      assert :openai in inherited
  """
  @spec inherit_from(pid(), pid(), GenServer.server()) :: [atom()]
  def inherit_from(parent_pid, child_pid \\ self(), server \\ @default_server) do
    providers = list_providers_with_auth(parent_pid, server)

    Enum.each(providers, fn provider ->
      transfer(provider, parent_pid, child_pid, server)
    end)

    providers
  end

  # Private helper to get the keyring key for a provider
  defp provider_key(provider) do
    :"#{provider}_api_key"
  end
end
