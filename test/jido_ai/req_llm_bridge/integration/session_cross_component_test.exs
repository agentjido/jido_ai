defmodule Jido.AI.ReqLlmBridge.Integration.SessionCrossComponentTest do
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
    test_keyring_name = :"test_keyring_session_#{:erlang.unique_integer([:positive])}"
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

  describe "session data flow across all components" do
    test "keyring -> session authentication -> authentication bridge -> provider requirements", %{
      keyring: _keyring
    } do
      # Set up initial session data
      SessionAuthentication.set_for_provider(:cloudflare, "cf-session-key")

      # 1. Session Authentication should have the value
      assert SessionAuthentication.has_session_auth?(:cloudflare)
      {:session_auth, session_opts} = SessionAuthentication.get_for_request(:cloudflare, %{})
      assert session_opts[:api_key] == "cf-session-key"

      # 2. Authentication bridge should use the session value
      {:ok, auth_headers, auth_key} = Authentication.authenticate_for_provider(:cloudflare, %{})
      assert auth_key == "cf-session-key"
      assert auth_headers["x-auth-key"] == "cf-session-key"

      # 3. Provider requirements should validate the session value
      assert :ok = ProviderAuthRequirements.validate_auth(:cloudflare, "cf-session-key")

      # 4. All components should work together for complex providers
      requirements = ProviderAuthRequirements.get_requirements(:cloudflare)
      assert requirements.required_keys == [:cloudflare_api_key]
      assert requirements.optional_keys == [:cloudflare_email, :cloudflare_account_id]

      # Test with optional parameters
      required_headers =
        ProviderAuthRequirements.get_required_headers(:cloudflare, email: "test@example.com")

      assert required_headers["X-Auth-Email"] == "test@example.com"
    end

    test "session precedence maintained across all components", %{keyring: keyring} do
      # Set session value
      SessionAuthentication.set_for_provider(:openai, "session-priority-key")

      # Mock ReqLLM to provide different value
      expect(ReqLlmBridge.Keys, :get, fn :openai, %{api_key: "request-override"} ->
        {:ok, "reqllm-key", :request_options}
      end)

      # Mock keyring to provide different value
      stub(Keyring, :get_env_value, fn :default, :openai_api_key, nil ->
        "keyring-env-key"
      end)

      # Session should take precedence everywhere
      {:session_auth, session_opts} =
        SessionAuthentication.get_for_request(:openai, %{api_key: "request-override"})

      assert session_opts[:api_key] == "session-priority-key"

      {:ok, auth_headers, auth_key} =
        Authentication.authenticate_for_provider(:openai, %{api_key: "request-override"})

      assert auth_key == "session-priority-key"
      assert auth_headers["authorization"] == "Bearer session-priority-key"

      # Provider requirements should work with session value
      params = ProviderAuthRequirements.resolve_all_params(:openai, api_key: "request-override")
      assert params.openai_api_key == "session-priority-key"
    end

    test "component interaction under concurrent access", %{keyring: keyring} do
      # Set up multiple providers with different session values
      providers_and_keys = [
        {:openai, "concurrent-openai"},
        {:anthropic, "concurrent-anthropic"},
        {:google, "concurrent-google"}
      ]

      for {provider, key} <- providers_and_keys do
        SessionAuthentication.set_for_provider(provider, key)
      end

      # Test concurrent access across all components
      tasks =
        for {provider, expected_key} <- providers_and_keys do
          Task.async(fn ->
            # Session authentication
            session_result = SessionAuthentication.get_for_request(provider, %{})

            # Authentication bridge
            {:ok, auth_headers, auth_key} =
              Authentication.authenticate_for_provider(provider, %{})

            # Provider requirements
            params = ProviderAuthRequirements.resolve_all_params(provider)
            provider_key = params[:"#{provider}_api_key"]

            # Validation
            validation_result = ProviderAuthRequirements.validate_auth(provider, expected_key)

            {provider, session_result, auth_key, provider_key, validation_result}
          end)
        end

      # Collect all results
      results = Task.await_many(tasks, 5000)

      # Verify each provider maintained its isolation
      for {{expected_provider, expected_key},
           {actual_provider, session_result, auth_key, provider_key, validation_result}} <-
            Enum.zip(providers_and_keys, results) do
        assert expected_provider == actual_provider
        assert {:session_auth, session_opts} = session_result
        assert session_opts[:api_key] == expected_key
        assert auth_key == expected_key
        assert provider_key == expected_key
        assert validation_result == :ok
      end
    end
  end

  describe "cross-process session synchronization" do
    test "session transfer affects all components in target process", %{keyring: keyring} do
      # Set up authentication in parent process
      SessionAuthentication.set_for_provider(:openai, "transfer-sync-key")
      current_pid = self()

      task =
        Task.async(fn ->
          # Initially no authentication in child process
          refute SessionAuthentication.has_session_auth?(:openai)

          # Mock external calls that would fail without session
          expect(ReqLlmBridge.Keys, :get, fn :openai, %{} ->
            {:error, "No key available"}
          end)

          stub(Keyring, :get_env_value, fn :default, :openai_api_key, nil ->
            nil
          end)

          # Authentication should fail without session
          {:error, _} = Authentication.authenticate_for_provider(:openai, %{})

          # Transfer session from parent
          transferred = SessionAuthentication.inherit_from(current_pid)
          assert :openai in transferred

          # Now all components should work
          assert SessionAuthentication.has_session_auth?(:openai)
          {:session_auth, session_opts} = SessionAuthentication.get_for_request(:openai, %{})
          assert session_opts[:api_key] == "transfer-sync-key"

          {:ok, auth_headers, auth_key} = Authentication.authenticate_for_provider(:openai, %{})
          assert auth_key == "transfer-sync-key"

          params = ProviderAuthRequirements.resolve_all_params(:openai)
          assert params.openai_api_key == "transfer-sync-key"

          :ok
        end)

      assert Task.await(task) == :ok
    end

    test "session isolation prevents cross-contamination", %{keyring: keyring} do
      # Set up different authentication in parent
      SessionAuthentication.set_for_provider(:openai, "parent-isolated-key")
      SessionAuthentication.set_for_provider(:anthropic, "parent-anthropic-key")

      parent_pid = self()

      task =
        Task.async(fn ->
          # Set different authentication in child
          SessionAuthentication.set_for_provider(:openai, "child-isolated-key")
          SessionAuthentication.set_for_provider(:google, "child-google-key")

          # Each process should see only its own values
          {:session_auth, child_openai_opts} = SessionAuthentication.get_for_request(:openai, %{})
          assert child_openai_opts[:api_key] == "child-isolated-key"

          {:session_auth, child_google_opts} = SessionAuthentication.get_for_request(:google, %{})
          assert child_google_opts[:api_key] == "child-google-key"

          # Child should not see parent's anthropic key
          assert {:no_session_auth} == SessionAuthentication.get_for_request(:anthropic, %{})

          # Test authentication isolation
          {:ok, child_headers, child_key} = Authentication.authenticate_for_provider(:openai, %{})
          assert child_key == "child-isolated-key"

          # Return child's view for verification
          {child_key, SessionAuthentication.list_providers_with_auth()}
        end)

      {child_openai_key, child_providers} = Task.await(task)

      # Verify child isolation
      assert child_openai_key == "child-isolated-key"
      assert :openai in child_providers
      assert :google in child_providers
      assert :anthropic not in child_providers

      # Verify parent still has its values
      {:session_auth, parent_openai_opts} = SessionAuthentication.get_for_request(:openai, %{})
      assert parent_openai_opts[:api_key] == "parent-isolated-key"

      {:session_auth, parent_anthropic_opts} =
        SessionAuthentication.get_for_request(:anthropic, %{})

      assert parent_anthropic_opts[:api_key] == "parent-anthropic-key"

      parent_providers = SessionAuthentication.list_providers_with_auth()
      assert :openai in parent_providers
      assert :anthropic in parent_providers
      assert :google not in parent_providers
    end

    test "complex session inheritance with multiple providers", %{keyring: keyring} do
      # Set up complex authentication state in parent
      providers_and_keys = [
        {:openai, "parent-openai-complex"},
        {:anthropic, "parent-anthropic-complex"},
        {:cloudflare, "parent-cf-complex"},
        {:google, "parent-google-complex"}
      ]

      for {provider, key} <- providers_and_keys do
        SessionAuthentication.set_for_provider(provider, key)
      end

      current_pid = self()

      task =
        Task.async(fn ->
          # Inherit all authentication
          inherited = SessionAuthentication.inherit_from(current_pid)
          expected_providers = Enum.map(providers_and_keys, &elem(&1, 0))

          # Verify all providers were inherited
          for expected_provider <- expected_providers do
            assert expected_provider in inherited
          end

          # Test that all components work with inherited values
          component_results =
            for {provider, expected_key} <- providers_and_keys do
              # Session authentication
              {:session_auth, session_opts} = SessionAuthentication.get_for_request(provider, %{})
              session_key = session_opts[:api_key]

              # Authentication bridge
              {:ok, auth_headers, auth_key} =
                Authentication.authenticate_for_provider(provider, %{})

              # Provider requirements
              params = ProviderAuthRequirements.resolve_all_params(provider)
              provider_key = params[:"#{provider}_api_key"]

              {provider, session_key, auth_key, provider_key, expected_key}
            end

          # Verify all components have consistent values
          for {provider, session_key, auth_key, provider_key, expected_key} <- component_results do
            assert session_key == expected_key, "Session key mismatch for #{provider}"
            assert auth_key == expected_key, "Auth key mismatch for #{provider}"
            assert provider_key == expected_key, "Provider key mismatch for #{provider}"
          end

          :all_consistent
        end)

      assert Task.await(task) == :all_consistent
    end
  end

  describe "error propagation across components" do
    test "component errors properly cascade through system", %{keyring: keyring} do
      # Clear all session values
      SessionAuthentication.clear_all()

      # Mock all external systems to fail
      expect(ReqLlmBridge.Keys, :get, 3, fn _provider, %{} ->
        {:error, "External system unavailable"}
      end)

      stub(Keyring, :get_env_value, fn :default, _key, nil ->
        nil
      end)

      # Test error cascade through all components
      providers = [:openai, :anthropic, :google]

      for provider <- providers do
        # Session authentication should indicate no auth
        assert {:no_session_auth} == SessionAuthentication.get_for_request(provider, %{})

        # Authentication bridge should fail gracefully
        {:error, error_msg} = Authentication.authenticate_for_provider(provider, %{})
        assert String.contains?(error_msg, "API key not found")

        # Authentication headers should return base headers
        headers = Authentication.get_authentication_headers(provider, %{})
        assert is_map(headers)

        # Validation should fail appropriately
        {:error, validation_error} = Authentication.validate_authentication(provider, %{})
        assert String.contains?(validation_error, "API key not found")
      end
    end

    test "partial system failure with graceful degradation", %{keyring: keyring} do
      # Set session for some providers
      SessionAuthentication.set_for_provider(:openai, "working-openai-key")

      # Mock ReqLLM to fail for one provider but work for others
      expect(ReqLlmBridge.Keys, :get, fn
        :anthropic, %{} -> {:error, "Anthropic service down"}
        :google, %{} -> {:ok, "google-reqllm-key", :reqllm_direct}
      end)

      stub(Keyring, :get_env_value, fn
        :default, :anthropic_api_key, nil -> "anthropic-fallback-key"
        :default, _key, nil -> nil
      end)

      # OpenAI should work (session value)
      {:ok, openai_headers, openai_key} = Authentication.authenticate_for_provider(:openai, %{})
      assert openai_key == "working-openai-key"
      assert openai_headers["authorization"] == "Bearer working-openai-key"

      # Google should work (ReqLLM direct)
      SessionAuthentication.clear_for_provider(:google)
      {:ok, google_headers, google_key} = Authentication.authenticate_for_provider(:google, %{})
      assert google_key == "google-reqllm-key"
      assert google_headers["x-goog-api-key"] == "google-reqllm-key"

      # Anthropic should fall back to keyring
      SessionAuthentication.clear_for_provider(:anthropic)

      {:ok, anthropic_headers, anthropic_key} =
        Authentication.authenticate_for_provider(:anthropic, %{})

      assert anthropic_key == "anthropic-fallback-key"
      assert anthropic_headers["x-api-key"] == "anthropic-fallback-key"
    end
  end

  describe "resource cleanup and lifecycle management" do
    test "session cleanup propagates through all components", %{keyring: keyring} do
      # Set up authentication across multiple providers
      providers = [:openai, :anthropic, :google, :cloudflare]

      for provider <- providers do
        SessionAuthentication.set_for_provider(provider, "cleanup-test-key")
      end

      # Verify all components see the authentication
      for provider <- providers do
        assert SessionAuthentication.has_session_auth?(provider)
        {:ok, _headers, _key} = Authentication.authenticate_for_provider(provider, %{})
        params = ProviderAuthRequirements.resolve_all_params(provider)
        assert params[:"#{provider}_api_key"] == "cleanup-test-key"
      end

      # Clear all sessions
      SessionAuthentication.clear_all()

      # Mock external systems for fallback testing
      expect(ReqLlmBridge.Keys, :get, length(providers), fn _provider, %{} ->
        {:error, "No external auth"}
      end)

      stub(Keyring, :get_env_value, fn :default, _key, nil ->
        nil
      end)

      # Verify cleanup affected all components
      for provider <- providers do
        refute SessionAuthentication.has_session_auth?(provider)
        {:error, _} = Authentication.authenticate_for_provider(provider, %{})

        params = ProviderAuthRequirements.resolve_all_params(provider)
        refute Map.has_key?(params, :"#{provider}_api_key")
      end
    end

    test "component state consistency during concurrent cleanup", %{keyring: keyring} do
      # Set up initial state
      providers = [:openai, :anthropic, :google]

      for provider <- providers do
        SessionAuthentication.set_for_provider(provider, "concurrent-cleanup-key")
      end

      # Spawn multiple tasks that will cleanup concurrently
      cleanup_tasks =
        for i <- 1..5 do
          Task.async(fn ->
            # Random delay
            :timer.sleep(Enum.random(1..10))

            if rem(i, 2) == 0 do
              # Even tasks clear all
              SessionAuthentication.clear_all()
            else
              # Odd tasks clear individual providers
              for provider <- providers do
                SessionAuthentication.clear_for_provider(provider)
              end
            end

            :cleaned
          end)
        end

      # Wait for all cleanup tasks
      Task.await_many(cleanup_tasks, 5000)

      # Mock external systems
      expect(ReqLlmBridge.Keys, :get, length(providers), fn _provider, %{} ->
        {:error, "No external auth after cleanup"}
      end)

      stub(Keyring, :get_env_value, fn :default, _key, nil ->
        nil
      end)

      # Verify consistent final state across all components
      for provider <- providers do
        refute SessionAuthentication.has_session_auth?(provider)
        {:error, _} = Authentication.authenticate_for_provider(provider, %{})
      end

      # Verify no leftover authentication
      assert [] = SessionAuthentication.list_providers_with_auth()
    end
  end
end
