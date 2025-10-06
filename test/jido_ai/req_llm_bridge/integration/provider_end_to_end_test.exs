defmodule Jido.AI.ReqLlmBridge.Integration.ProviderEndToEndTest do
  use ExUnit.Case, async: false
  use Mimic

  @moduletag :capture_log

  alias Jido.AI.Keyring
  alias Jido.AI.ReqLlmBridge.Authentication
  alias Jido.AI.ReqLlmBridge.ProviderAuthRequirements
  alias Jido.AI.ReqLlmBridge.SessionAuthentication

  setup :set_mimic_global

  setup do
    # Start a unique Keyring for testing
    test_keyring_name = :"test_keyring_provider_#{:erlang.unique_integer([:positive])}"
    {:ok, _pid} = Keyring.start_link(name: test_keyring_name)

    on_exit(fn ->
      try do
        GenServer.stop(test_keyring_name)
      catch
        :exit, _ -> :ok
      end
    end)

    %{keyring: test_keyring_name}
  end

  describe "OpenAI complete authentication flow" do
    test "full session-based OpenAI authentication", %{keyring: _keyring} do
      # Set up session
      SessionAuthentication.set_for_provider(:openai, "sk-openai-session-complete")

      # Test provider requirements
      requirements = ProviderAuthRequirements.get_requirements(:openai)
      assert requirements.required_keys == [:openai_api_key]
      assert requirements.env_var == "OPENAI_API_KEY"
      assert requirements.header_format == :bearer_token

      # Test authentication validation
      assert :ok = ProviderAuthRequirements.validate_auth(:openai, "sk-openai-session-complete")

      # Test parameter resolution
      params = ProviderAuthRequirements.resolve_all_params(:openai)
      assert params.openai_api_key == "sk-openai-session-complete"

      # Test authentication bridge
      {:ok, headers, key} = Authentication.authenticate_for_provider(:openai, %{})
      assert key == "sk-openai-session-complete"
      assert headers["authorization"] == "Bearer sk-openai-session-complete"

      # Test header retrieval
      retrieved_headers = Authentication.get_authentication_headers(:openai, %{})
      assert retrieved_headers["authorization"] == "Bearer sk-openai-session-complete"

      # Test validation
      assert :ok = Authentication.validate_authentication(:openai, %{})

      # Test unified authentication function
      {:ok, {unified_key, unified_headers}} =
        Authentication.resolve_provider_authentication(:openai, %{})

      assert unified_key == "sk-openai-session-complete"
      assert unified_headers["authorization"] == "Bearer sk-openai-session-complete"
    end

    test "OpenAI fallback chain: session -> ReqLLM -> keyring -> failure", %{keyring: _keyring} do
      # Test 1: Session authentication (highest priority)
      SessionAuthentication.set_for_provider(:openai, "sk-session-priority")
      {:ok, headers, key} = Authentication.authenticate_for_provider(:openai, %{})
      assert key == "sk-session-priority"
      assert headers["authorization"] == "Bearer sk-session-priority"

      # Test 2: ReqLLM fallback when no session
      SessionAuthentication.clear_for_provider(:openai)

      expect(ReqLlmBridge.Keys, :get, fn :openai, %{} ->
        {:ok, "sk-reqllm-fallback", :environment}
      end)

      {:ok, headers, key} = Authentication.authenticate_for_provider(:openai, %{})
      assert key == "sk-reqllm-fallback"
      assert headers["authorization"] == "Bearer sk-reqllm-fallback"

      # Test 3: Keyring fallback when ReqLLM fails
      expect(ReqLlmBridge.Keys, :get, fn :openai, %{} ->
        {:error, "ReqLLM unavailable"}
      end)

      stub(Keyring, :get_env_value, fn :default, :openai_api_key, nil ->
        "sk-keyring-fallback"
      end)

      {:ok, headers, key} = Authentication.authenticate_for_provider(:openai, %{})
      assert key == "sk-keyring-fallback"
      assert headers["authorization"] == "Bearer sk-keyring-fallback"

      # Test 4: Complete failure when all sources unavailable
      stub(Keyring, :get_env_value, fn :default, :openai_api_key, nil ->
        nil
      end)

      {:error, reason} = Authentication.authenticate_for_provider(:openai, %{})
      assert reason == "API key not found: OPENAI_API_KEY"
    end
  end

  describe "Anthropic complete authentication flow" do
    test "full Anthropic authentication with version headers", %{keyring: _keyring} do
      # Set up session
      SessionAuthentication.set_for_provider(:anthropic, "sk-ant-complete-flow")

      # Test provider requirements
      requirements = ProviderAuthRequirements.get_requirements(:anthropic)
      assert requirements.required_keys == [:anthropic_api_key]
      assert requirements.headers["anthropic-version"] == "2023-06-01"
      assert requirements.header_format == :api_key

      # Test required headers
      required_headers = ProviderAuthRequirements.get_required_headers(:anthropic)
      assert required_headers["anthropic-version"] == "2023-06-01"

      # Test validation
      assert :ok = ProviderAuthRequirements.validate_auth(:anthropic, "sk-ant-complete-flow")

      # Test authentication bridge with headers
      {:ok, headers, key} = Authentication.authenticate_for_provider(:anthropic, %{})
      assert key == "sk-ant-complete-flow"
      assert headers["x-api-key"] == "sk-ant-complete-flow"
      assert headers["anthropic-version"] == "2023-06-01"

      # Test header retrieval maintains version
      retrieved_headers = Authentication.get_authentication_headers(:anthropic, %{})
      assert retrieved_headers["x-api-key"] == "sk-ant-complete-flow"
      assert retrieved_headers["anthropic-version"] == "2023-06-01"

      # Test validation
      assert :ok = Authentication.validate_authentication(:anthropic, %{})
    end

    test "Anthropic key validation requirements", %{keyring: _keyring} do
      # Valid key format
      valid_keys = [
        "sk-ant-abcdef123456789012345678",
        "sk-ant-xyz789012345678901234567890123456789"
      ]

      for valid_key <- valid_keys do
        assert :ok = ProviderAuthRequirements.validate_auth(:anthropic, valid_key)
        SessionAuthentication.set_for_provider(:anthropic, valid_key)
        assert :ok = Authentication.validate_authentication(:anthropic, %{})
      end

      # Invalid key formats
      invalid_keys = [
        "sk-wrong-prefix",
        "sk-ant-short",
        "",
        "not-anthropic-format"
      ]

      for invalid_key <- invalid_keys do
        {:error, _reason} = ProviderAuthRequirements.validate_auth(:anthropic, invalid_key)
        SessionAuthentication.set_for_provider(:anthropic, invalid_key)
        {:error, _reason} = Authentication.validate_authentication(:anthropic, %{})
      end
    end
  end

  describe "Cloudflare multi-factor authentication flow" do
    test "Cloudflare authentication with email and account ID", %{keyring: _keyring} do
      # Test basic key requirements
      requirements = ProviderAuthRequirements.get_requirements(:cloudflare)
      assert requirements.required_keys == [:cloudflare_api_key]
      assert requirements.optional_keys == [:cloudflare_email, :cloudflare_account_id]
      assert ProviderAuthRequirements.requires_multi_factor?(:cloudflare)

      # Set up session with basic key
      SessionAuthentication.set_for_provider(:cloudflare, "cf-test-key")

      # Test basic authentication
      {:ok, headers, key} = Authentication.authenticate_for_provider(:cloudflare, %{})
      assert key == "cf-test-key"
      assert headers["x-auth-key"] == "cf-test-key"

      # Test with optional headers
      required_headers =
        ProviderAuthRequirements.get_required_headers(
          :cloudflare,
          email: "test@cloudflare.com",
          account_id: "account-123"
        )

      assert required_headers["X-Auth-Email"] == "test@cloudflare.com"
      assert required_headers["CF-Account-ID"] == "account-123"

      # Test validation with map parameters
      auth_params = %{
        api_key: "cf-test-key",
        email: "test@cloudflare.com"
      }

      assert :ok = ProviderAuthRequirements.validate_auth(:cloudflare, auth_params)

      # Test invalid email format
      invalid_auth_params = %{
        api_key: "cf-test-key",
        email: "invalid-email-format"
      }

      {:error, reason} = ProviderAuthRequirements.validate_auth(:cloudflare, invalid_auth_params)
      assert reason == "Invalid email format"
    end

    test "Cloudflare environment variable integration", %{keyring: _keyring} do
      # Clear session
      SessionAuthentication.clear_for_provider(:cloudflare)

      # Mock environment variables
      stub(System, :get_env, fn
        "CLOUDFLARE_EMAIL" -> "env@cloudflare.com"
        "CLOUDFLARE_ACCOUNT_ID" -> "env-account-456"
        _ -> nil
      end)

      # Mock ReqLLM to provide key
      expect(ReqLlmBridge.Keys, :get, fn :cloudflare, %{} ->
        {:ok, "cf-env-key", :environment}
      end)

      # Test authentication picks up environment headers
      {:ok, headers, key} = Authentication.authenticate_for_provider(:cloudflare, %{})
      assert key == "cf-env-key"
      assert headers["x-auth-key"] == "cf-env-key"

      # Test required headers include environment values
      required_headers = ProviderAuthRequirements.get_required_headers(:cloudflare)
      assert required_headers["X-Auth-Email"] == "env@cloudflare.com"
      assert required_headers["CF-Account-ID"] == "env-account-456"
    end
  end

  describe "OpenRouter authentication with metadata" do
    test "OpenRouter with site metadata", %{keyring: _keyring} do
      # Test requirements
      requirements = ProviderAuthRequirements.get_requirements(:openrouter)
      assert requirements.required_keys == [:openrouter_api_key]
      assert requirements.optional_keys == [:openrouter_site_url, :openrouter_site_name]
      assert requirements.header_format == :bearer_token

      # Set up session
      SessionAuthentication.set_for_provider(:openrouter, "sk-or-test-key")

      # Test basic authentication
      {:ok, headers, key} = Authentication.authenticate_for_provider(:openrouter, %{})
      assert key == "sk-or-test-key"
      assert headers["authorization"] == "Bearer sk-or-test-key"

      # Test with metadata headers
      required_headers =
        ProviderAuthRequirements.get_required_headers(
          :openrouter,
          site_url: "https://myapp.example.com",
          site_name: "My AI App"
        )

      assert required_headers["HTTP-Referer"] == "https://myapp.example.com"
      assert required_headers["X-Title"] == "My AI App"

      # Test key validation - supports both OpenRouter format and generic
      assert :ok = ProviderAuthRequirements.validate_auth(:openrouter, "sk-or-v1-abcdef123456")

      assert :ok =
               ProviderAuthRequirements.validate_auth(:openrouter, "generic-api-key-123456789")

      {:error, _} = ProviderAuthRequirements.validate_auth(:openrouter, "short")
    end
  end

  describe "Google authentication flow" do
    test "Google API key authentication", %{keyring: _keyring} do
      # Test requirements
      requirements = ProviderAuthRequirements.get_requirements(:google)
      assert requirements.required_keys == [:google_api_key]
      assert requirements.header_format == :api_key

      # Set up session
      SessionAuthentication.set_for_provider(:google, "AIzaSyD-google-test-key")

      # Test authentication
      {:ok, headers, key} = Authentication.authenticate_for_provider(:google, %{})
      assert key == "AIzaSyD-google-test-key"
      assert headers["x-goog-api-key"] == "AIzaSyD-google-test-key"

      # Test validation
      assert :ok = ProviderAuthRequirements.validate_auth(:google, "AIzaSyD-google-test-key")
      {:error, _} = ProviderAuthRequirements.validate_auth(:google, "short-key")
      {:error, _} = ProviderAuthRequirements.validate_auth(:google, "")
    end
  end

  describe "unknown provider handling" do
    test "generic provider authentication", %{keyring: _keyring} do
      # Test unknown provider gets generic requirements
      requirements = ProviderAuthRequirements.get_requirements(:unknown_provider)
      assert requirements.required_keys == [:unknown_provider_api_key]
      assert requirements.env_var == "UNKNOWN_PROVIDER_API_KEY"
      assert requirements.header_format == :bearer_token

      # Set up session for unknown provider
      SessionAuthentication.set_for_provider(:unknown_provider, "generic-key")

      # Test authentication uses generic bearer token format
      {:ok, headers, key} = Authentication.authenticate_for_provider(:unknown_provider, %{})
      assert key == "generic-key"
      assert headers["authorization"] == "Bearer generic-key"

      # Test validation works with generic validation
      assert :ok = ProviderAuthRequirements.validate_auth(:unknown_provider, "any-non-empty-key")
      {:error, _} = ProviderAuthRequirements.validate_auth(:unknown_provider, "")
    end
  end

  describe "cross-provider authentication scenarios" do
    test "multiple providers simultaneously", %{keyring: _keyring} do
      # Set up multiple providers
      provider_configs = [
        {:openai, "sk-multi-openai-key", "authorization", "Bearer sk-multi-openai-key"},
        {:anthropic, "sk-ant-multi-key", "x-api-key", "sk-ant-multi-key"},
        {:google, "AIzaSyD-multi-google", "x-goog-api-key", "AIzaSyD-multi-google"},
        {:cloudflare, "cf-multi-key", "x-auth-key", "cf-multi-key"},
        {:openrouter, "sk-or-multi-key", "authorization", "Bearer sk-or-multi-key"}
      ]

      # Set up all sessions
      for {provider, key, _header, _value} <- provider_configs do
        SessionAuthentication.set_for_provider(provider, key)
      end

      # Test each provider works correctly
      for {provider, expected_key, expected_header, expected_value} <- provider_configs do
        # Requirements
        requirements = ProviderAuthRequirements.get_requirements(provider)

        assert expected_key in [
                 requirements.required_keys |> List.first() |> to_string() |> (&"#{&1}").()
               ]

        # Authentication
        {:ok, headers, key} = Authentication.authenticate_for_provider(provider, %{})
        assert key == expected_key
        assert headers[expected_header] == expected_value

        # Validation
        assert :ok = Authentication.validate_authentication(provider, %{})
      end

      # Test isolation - clearing one doesn't affect others
      SessionAuthentication.clear_for_provider(:openai)

      # OpenAI should fail
      expect(ReqLlmBridge.Keys, :get, fn :openai, %{} ->
        {:error, "No key"}
      end)

      stub(Keyring, :get_env_value, fn :default, :openai_api_key, nil ->
        nil
      end)

      {:error, _} = Authentication.authenticate_for_provider(:openai, %{})

      # Others should still work
      remaining_configs = provider_configs |> Enum.reject(&(elem(&1, 0) == :openai))

      for {provider, expected_key, expected_header, expected_value} <- remaining_configs do
        {:ok, headers, key} = Authentication.authenticate_for_provider(provider, %{})
        assert key == expected_key
        assert headers[expected_header] == expected_value
      end
    end

    test "provider switching within single session", %{keyring: _keyring} do
      # Set up multiple providers
      providers = [:openai, :anthropic, :google]

      for provider <- providers do
        key = "#{provider}-switch-test"
        SessionAuthentication.set_for_provider(provider, key)
      end

      # Test rapid switching between providers
      for _iteration <- 1..10 do
        for provider <- Enum.shuffle(providers) do
          expected_key = "#{provider}-switch-test"
          {:ok, _headers, key} = Authentication.authenticate_for_provider(provider, %{})
          assert key == expected_key
        end
      end

      # Test concurrent provider access
      tasks =
        for provider <- providers do
          Task.async(fn ->
            expected_key = "#{provider}-switch-test"

            results =
              for _i <- 1..5 do
                {:ok, headers, key} = Authentication.authenticate_for_provider(provider, %{})
                {key, headers}
              end

            # All results should be consistent
            for {key, _headers} <- results do
              assert key == expected_key
            end

            :consistent
          end)
        end

      results = Task.await_many(tasks, 5000)
      assert Enum.all?(results, &(&1 == :consistent))
    end
  end

  describe "provider-specific error handling and recovery" do
    test "provider-specific error messages", %{keyring: _keyring} do
      # Clear all sessions
      SessionAuthentication.clear_all()

      # Mock external systems to fail
      expect(ReqLlmBridge.Keys, :get, 5, fn provider, %{} ->
        {:error,
         ":api_key option or #{String.upcase("#{provider}")}_API_KEY environment variable required"}
      end)

      stub(Keyring, :get_env_value, fn :default, _key, nil ->
        nil
      end)

      # Test each provider gets appropriate error message
      provider_errors = [
        {:openai, "API key not found: OPENAI_API_KEY"},
        {:anthropic, "API key not found: ANTHROPIC_API_KEY"},
        {:google, "API key not found: GOOGLE_API_KEY"},
        {:cloudflare, "API key not found: CLOUDFLARE_API_KEY"},
        {:openrouter, "API key not found: OPENROUTER_API_KEY"}
      ]

      for {provider, expected_error} <- provider_errors do
        {:error, actual_error} = Authentication.authenticate_for_provider(provider, %{})
        assert actual_error == expected_error
      end
    end

    test "partial provider recovery scenarios", %{keyring: _keyring} do
      # Scenario: Some providers work, others fail at different stages

      # Provider 1: Session works
      SessionAuthentication.set_for_provider(:openai, "working-session-key")

      # Provider 2: Session fails, ReqLLM works
      SessionAuthentication.clear_for_provider(:anthropic)

      expect(ReqLlmBridge.Keys, :get, fn :anthropic, %{} ->
        {:ok, "working-reqllm-key", :environment}
      end)

      # Provider 3: Session and ReqLLM fail, keyring works
      SessionAuthentication.clear_for_provider(:google)

      expect(ReqLlmBridge.Keys, :get, fn :google, %{} ->
        {:error, "ReqLLM service unavailable"}
      end)

      stub(Keyring, :get_env_value, fn :default, :google_api_key, nil ->
        "working-keyring-key"
      end)

      # Provider 4: Everything fails
      SessionAuthentication.clear_for_provider(:cloudflare)

      expect(ReqLlmBridge.Keys, :get, fn :cloudflare, %{} ->
        {:error, "All systems down"}
      end)

      stub(Keyring, :get_env_value, fn :default, :cloudflare_api_key, nil ->
        nil
      end)

      # Test results
      {:ok, _headers, key1} = Authentication.authenticate_for_provider(:openai, %{})
      assert key1 == "working-session-key"

      {:ok, _headers, key2} = Authentication.authenticate_for_provider(:anthropic, %{})
      assert key2 == "working-reqllm-key"

      {:ok, _headers, key3} = Authentication.authenticate_for_provider(:google, %{})
      assert key3 == "working-keyring-key"

      {:error, _reason} = Authentication.authenticate_for_provider(:cloudflare, %{})
    end
  end
end
