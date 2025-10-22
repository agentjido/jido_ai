defmodule Jido.AI.ReqLlmBridge.AuthenticationTest do
  use ExUnit.Case, async: false
  use Mimic

  alias Jido.AI.ReqLlmBridge.Authentication
  alias Jido.AI.Keyring

  # Note: async: false because we're manipulating session values

  setup :set_mimic_global

  @moduledoc """
  Tests for the Authentication module.

  Note: These tests focus on testable aspects of the authentication system:
  - Session-based authentication (which works reliably)
  - Error handling and validation
  - Authentication precedence when session values are set

  Provider-specific header formatting is tested indirectly through session authentication.
  Full integration with ReqLLM.Keys is covered by integration tests.
  """

  setup do
    # Copy modules for mocking
    copy(ReqLLM.Keys)
    copy(Jido.AI.Keyring)

    # Stub ReqLLM.Keys.get to return error by default
    # This ensures tests are isolated from global JidoKeys state
    stub(ReqLLM.Keys, :get, fn provider, _opts ->
      env_var = "#{String.upcase(to_string(provider))}_API_KEY"
      {:error, ":api_key option or #{env_var} env var (optionally via JidoKeys.put/2)"}
    end)

    # Stub Keyring.get_env_value to return nil by default
    # This prevents tests from finding real environment variables
    stub(Keyring, :get_env_value, fn _server, _key, default -> default end)

    # Clear any session values before each test
    Keyring.clear_all_session_values(Jido.AI.Keyring)

    on_exit(fn ->
      # Clean up session values after each test
      Keyring.clear_all_session_values(Jido.AI.Keyring)
    end)

    :ok
  end

  describe "1.1 Provider Authentication with Session Keys" do
    test "OpenAI uses session key with Bearer authorization header" do
      # Set session key for OpenAI
      test_key = "sk-test-openai-key-123"
      Keyring.set_session_value(Jido.AI.Keyring, :openai_api_key, test_key)

      # Authenticate
      {:ok, headers, key} = Authentication.authenticate_for_provider(:openai, %{})

      # Verify authorization header with Bearer prefix
      assert headers["authorization"] == "Bearer #{test_key}"
      # Note: key might be filtered for security, so just verify it's not nil
      assert is_binary(key)
      assert String.contains?(key, "key") or String.contains?(key, "FILTERED")
    end

    test "Anthropic uses session key with x-api-key header and version" do
      # Set session key for Anthropic
      test_key = "sk-ant-test-key-123"
      Keyring.set_session_value(Jido.AI.Keyring, :anthropic_api_key, test_key)

      # Authenticate
      {:ok, headers, key} = Authentication.authenticate_for_provider(:anthropic, %{})

      # Verify x-api-key header (no Bearer prefix)
      assert headers["x-api-key"] == test_key

      # Verify anthropic-version header is present
      assert headers["anthropic-version"] == "2023-06-01"

      # Key returned
      assert is_binary(key)
    end

    test "OpenRouter uses session key with Bearer authorization" do
      test_key = "sk-or-test-key-123"
      Keyring.set_session_value(Jido.AI.Keyring, :openrouter_api_key, test_key)

      {:ok, headers, key} = Authentication.authenticate_for_provider(:openrouter, %{})

      # OpenRouter uses Bearer token
      assert headers["authorization"] == "Bearer #{test_key}"
      assert is_binary(key)
    end

    test "Google uses session key with x-goog-api-key header" do
      test_key = "google-test-key-123"
      Keyring.set_session_value(Jido.AI.Keyring, :google_api_key, test_key)

      {:ok, headers, key} = Authentication.authenticate_for_provider(:google, %{})

      # Google uses x-goog-api-key with no prefix
      assert headers["x-goog-api-key"] == test_key
      assert is_binary(key)
    end

    test "Cloudflare uses session key with x-auth-key header" do
      test_key = "cloudflare-test-key-123"
      Keyring.set_session_value(Jido.AI.Keyring, :cloudflare_api_key, test_key)

      {:ok, headers, key} = Authentication.authenticate_for_provider(:cloudflare, %{})

      # Cloudflare uses x-auth-key with no prefix
      assert headers["x-auth-key"] == test_key
      assert is_binary(key)
    end
  end

  describe "1.2 Session-based Authentication" do
    test "session value is used for authentication" do
      # Set session key
      session_key = "sk-session-key-123"
      Keyring.set_session_value(Jido.AI.Keyring, :openai_api_key, session_key)

      # Authenticate
      {:ok, headers, key} = Authentication.authenticate_for_provider(:openai, %{})

      # Session key should be used in headers (may be filtered for security)
      assert String.starts_with?(headers["authorization"], "Bearer ")
      # Verify the header contains either the original key or filtered version
      auth_value = headers["authorization"]
      assert String.contains?(auth_value, "key") or String.contains?(auth_value, "FILTERED")
      # Key is returned (possibly filtered)
      assert is_binary(key)
    end

    test "different providers use their session keys independently" do
      # Set different keys for different providers
      openai_key = "sk-openai-123"
      anthropic_key = "sk-ant-456"

      Keyring.set_session_value(Jido.AI.Keyring, :openai_api_key, openai_key)
      Keyring.set_session_value(Jido.AI.Keyring, :anthropic_api_key, anthropic_key)

      # Each provider uses its own key
      {:ok, openai_headers, _} = Authentication.authenticate_for_provider(:openai, %{})
      {:ok, anthropic_headers, _} = Authentication.authenticate_for_provider(:anthropic, %{})

      # OpenAI uses authorization header with Bearer (may be filtered)
      assert String.starts_with?(openai_headers["authorization"], "Bearer ")
      # Anthropic uses x-api-key header directly (not filtered in header)
      assert anthropic_headers["x-api-key"] == anthropic_key
      # Verify anthropic-version is also present
      assert anthropic_headers["anthropic-version"] == "2023-06-01"
    end

    test "error when no session key is set and no other authentication available" do
      # Don't set any session keys
      # ReqLLM.Keys is stubbed to return error by default
      # Authenticate should fail
      result = Authentication.authenticate_for_provider(:openai, %{})

      # Should get error
      assert {:error, reason} = result
      assert is_binary(reason)

      assert String.contains?(String.downcase(reason), "api key") or
               String.contains?(String.downcase(reason), "authentication")
    end
  end

  describe "1.3 Authentication Validation" do
    test "validation succeeds with session key" do
      # Set valid API key via session
      test_key = "sk-session-key-123"
      Keyring.set_session_value(Jido.AI.Keyring, :openai_api_key, test_key)

      # Validate authentication
      result = Authentication.validate_authentication(:openai, %{})

      # Should return :ok
      assert result == :ok
    end

    test "validation fails with missing key" do
      # Don't set any session keys
      # ReqLLM.Keys is stubbed to return error by default
      # Validate authentication should fail
      result = Authentication.validate_authentication(:openai, %{})

      # Should get error
      assert {:error, reason} = result
      assert is_binary(reason)
    end

    test "validation works for multiple providers" do
      # Set keys for multiple providers
      Keyring.set_session_value(Jido.AI.Keyring, :openai_api_key, "sk-openai")
      Keyring.set_session_value(Jido.AI.Keyring, :anthropic_api_key, "sk-ant")

      # Both should validate successfully
      assert Authentication.validate_authentication(:openai, %{}) == :ok
      assert Authentication.validate_authentication(:anthropic, %{}) == :ok
    end
  end
end
