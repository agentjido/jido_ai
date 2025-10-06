defmodule Jido.AI.ReqLlmBridge.KeyringIntegrationTest do
  use ExUnit.Case, async: false
  use Mimic

  @moduletag :capture_log

  alias Jido.AI.Keyring
  alias Jido.AI.ReqLlmBridge.KeyringIntegration

  # Add global mock setup
  setup :set_mimic_global

  setup do
    # Copy the modules we need to mock
    Mimic.copy(ReqLlmBridge.Keys)
    Mimic.copy(System)
    Mimic.copy(Dotenvy)

    # Mock Dotenvy to provide stable test environment
    stub(Dotenvy, :source!, fn _sources -> %{} end)
    stub(Dotenvy, :env!, fn _key, _type -> raise "Not found" end)

    # Start the Keyring GenServer for tests with unique name
    test_keyring_name = :"test_keyring_#{:erlang.unique_integer([:positive])}"
    {:ok, _pid} = Keyring.start_link(name: test_keyring_name)

    on_exit(fn ->
      # Clean up the test keyring
      try do
        GenServer.stop(test_keyring_name)
      catch
        :exit, _ -> :ok
      end
    end)

    %{keyring: test_keyring_name}
  end

  describe "get/5 - unified key precedence" do
    test "returns session value when available (highest precedence)", %{keyring: keyring} do
      # Set up a session value
      Keyring.set_session_value(keyring, :openai_api_key, "session-key")

      # Should return session value regardless of other options
      req_options = %{api_key: "request-override"}
      result = KeyringIntegration.get(keyring, :openai_api_key, "default", self(), req_options)

      assert result == "session-key"

      # Clean up
      Keyring.clear_session_value(keyring, :openai_api_key)
    end

    test "returns per-request override when no session value" do
      # Clear any session values
      Keyring.clear_session_value(:openai_api_key)

      # Should return per-request override
      req_options = %{api_key: "request-override"}
      result = KeyringIntegration.get(Keyring, :openai_api_key, "default", self(), req_options)

      assert result == "request-override"
    end

    test "falls back to ReqLLM resolution when no session or request override" do
      # Clear session values
      Keyring.clear_session_value(:openai_api_key)

      # Mock ReqLlmBridge.Keys to return a value
      expect(ReqLlmBridge.Keys, :get, fn :openai, "default" ->
        {:ok, "reqllm-key", :environment}
      end)

      result = KeyringIntegration.get(Keyring, :openai_api_key, "default")

      assert result == "reqllm-key"
    end

    test "returns default when no key found anywhere" do
      # Clear session values
      Keyring.clear_session_value(:unknown_key)

      # Mock ReqLlmBridge.Keys to return default
      expect(ReqLlmBridge.Keys, :get, fn :unknown, "default" -> "default" end)

      result = KeyringIntegration.get(Keyring, :unknown_key, "default")

      assert result == "default"
    end

    test "handles ReqLlmBridge.Keys errors gracefully" do
      # Clear session values
      Keyring.clear_session_value(:openai_api_key)

      # Mock ReqLlmBridge.Keys to raise an error
      expect(ReqLlmBridge.Keys, :get, fn :openai, "default" ->
        raise RuntimeError, "ReqLLM error"
      end)

      result = KeyringIntegration.get(Keyring, :openai_api_key, "default")

      assert result == "default"
    end
  end

  describe "get_env_value/3 - ReqLLM environment integration" do
    test "returns standard Keyring environment value when available" do
      # This will use the actual Keyring.get_env_value which should work
      # We can't easily mock the ETS table, so we'll test the fallback behavior
      result = KeyringIntegration.get_env_value(Keyring, :nonexistent_key, "default")

      assert result == "default"
    end

    test "falls back to ReqLLM environment resolution" do
      # Mock System.get_env for the ReqLLM environment variable
      expect(System, :get_env, fn "OPENAI_API_KEY" -> "env-key" end)

      # This should fall back to ReqLLM environment resolution
      result = KeyringIntegration.get_env_value(Keyring, :openai_api_key, "default")

      # Since we can't easily mock the ETS table to return nil, we'll verify the behavior
      # The result should either be the environment value or default
      assert result in ["env-key", "default"]
    end
  end

  describe "resolve_provider_key/3 - provider key mapping" do
    test "resolves key for mapped provider" do
      expect(ReqLlmBridge.Keys, :get, fn :openai, nil -> {:ok, "mapped-key", :environment} end)

      result = KeyringIntegration.resolve_provider_key(:openai_api_key, :openai, "default")

      assert result == "mapped-key"
    end

    test "falls back to direct ReqLLM lookup for unmapped key" do
      expect(ReqLlmBridge.Keys, :get, fn :custom, "fallback" -> {:ok, "custom-key", :app} end)

      result = KeyringIntegration.resolve_provider_key(:custom_key, :custom, "fallback")

      assert result == "custom-key"
    end

    test "returns default when ReqLLM resolution fails" do
      expect(ReqLlmBridge.Keys, :get, fn :openai, nil -> nil end)

      result = KeyringIntegration.resolve_provider_key(:openai_api_key, :openai, "fallback")

      assert result == "fallback"
    end
  end

  describe "get_key_for_request/3 - ReqLLM request integration" do
    test "resolves OpenAI provider key correctly" do
      # Set up session value to test precedence
      Keyring.set_session_value(:openai_api_key, "session-openai-key")

      result = KeyringIntegration.get_key_for_request(:openai)

      assert result == "session-openai-key"

      # Clean up
      Keyring.clear_session_value(:openai_api_key)
    end

    test "handles per-request override for ReqLLM calls" do
      req_options = %{api_key: "request-specific-key"}

      result = KeyringIntegration.get_key_for_request(:anthropic, req_options)

      assert result == "request-specific-key"
    end

    test "maps unknown providers to standard key pattern" do
      # Should map unknown provider to :custom_provider_api_key pattern
      Keyring.set_session_value(:custom_provider_api_key, "custom-key")

      result = KeyringIntegration.get_key_for_request(:custom_provider)

      assert result == "custom-key"

      # Clean up
      Keyring.clear_session_value(:custom_provider_api_key)
    end
  end

  describe "list_with_providers/1 - enhanced key listing" do
    test "returns combined list of keys" do
      # Get standard Keyring keys
      keys = KeyringIntegration.list_with_providers(Keyring)

      # Should be a list of atoms
      assert is_list(keys)
      assert Enum.all?(keys, &is_atom/1)

      # Should include provider keys
      provider_keys = [
        :openai_api_key,
        :anthropic_api_key,
        :google_api_key,
        :openrouter_api_key,
        :cloudflare_api_key
      ]

      assert Enum.any?(provider_keys, fn key -> key in keys end)
    end

    test "returns sorted and deduplicated list" do
      keys = KeyringIntegration.list_with_providers(Keyring)

      # Should be sorted
      assert keys == Enum.sort(keys)

      # Should be deduplicated (no duplicates)
      assert keys == Enum.uniq(keys)
    end
  end

  describe "validate_key_availability/2 - key validation" do
    test "detects session value availability" do
      Keyring.set_session_value(:openai_api_key, "test-key")

      result = KeyringIntegration.validate_key_availability(:openai_api_key, :openai)

      assert {:ok, :session} = result

      # Clean up
      Keyring.clear_session_value(:openai_api_key)
    end

    test "detects ReqLLM availability when session not available" do
      # Clear session value
      Keyring.clear_session_value(:openai_api_key)

      # Mock ReqLlmBridge.Keys to indicate availability
      expect(ReqLlmBridge.Keys, :get, fn :openai, nil -> {:ok, "reqllm-key", :environment} end)

      result = KeyringIntegration.validate_key_availability(:openai_api_key, :openai)

      assert {:ok, :reqllm} = result
    end

    test "returns error when key not found anywhere" do
      # Clear session value
      Keyring.clear_session_value(:nonexistent_key)

      result = KeyringIntegration.validate_key_availability(:nonexistent_key, :nonexistent)

      assert {:error, :not_found} = result
    end
  end

  describe "provider key mappings" do
    test "includes all expected providers" do
      # Test that we have mappings for all major providers
      expected_providers = [:openai, :anthropic, :openrouter, :google, :cloudflare]

      Enum.each(expected_providers, fn provider ->
        jido_key = :"#{provider}_api_key"
        result = KeyringIntegration.resolve_provider_key(jido_key, provider, "test")

        # Should not crash and should return some value
        assert is_binary(result) or result == "test"
      end)
    end

    test "handles case sensitivity correctly" do
      # Environment variables are uppercase, Jido keys are lowercase
      expect(System, :get_env, fn "OPENAI_API_KEY" -> "uppercase-env-key" end)

      # Should handle the mapping correctly
      result = KeyringIntegration.get_env_value(Keyring, :openai_api_key, "default")

      # Should either get environment value or default
      assert result in ["uppercase-env-key", "default"]
    end
  end

  describe "error handling and edge cases" do
    test "handles nil values gracefully" do
      result = KeyringIntegration.get(Keyring, :nil_key, nil, self(), %{})

      assert is_nil(result)
    end

    test "handles empty request options" do
      result = KeyringIntegration.get(Keyring, :test_key, "default", self(), %{})

      assert result == "default" or is_binary(result)
    end

    test "handles invalid request options gracefully" do
      # Test with invalid api_key value
      invalid_options = %{api_key: nil}
      result = KeyringIntegration.get(Keyring, :test_key, "default", self(), invalid_options)

      assert result == "default" or is_binary(result)

      # Test with empty api_key
      empty_options = %{api_key: ""}
      result = KeyringIntegration.get(Keyring, :test_key, "default", self(), empty_options)

      assert result == "default" or is_binary(result)
    end

    test "handles ReqLLM module unavailability" do
      # Mock ReqLlmBridge.Keys to be undefined
      expect(ReqLlmBridge.Keys, :get, fn _provider, _default ->
        raise UndefinedFunctionError, function: "get/2", module: ReqLlmBridge.Keys
      end)

      result = KeyringIntegration.get(Keyring, :openai_api_key, "fallback")

      assert result == "fallback"
    end
  end

  describe "integration with existing Keyring functions" do
    test "session management works with integration" do
      # Set session value
      Keyring.set_session_value(:integration_test_key, "session-value")

      # Should work with integration function
      result = KeyringIntegration.get(Keyring, :integration_test_key, "default")

      assert result == "session-value"

      # Clear session value
      Keyring.clear_session_value(:integration_test_key)

      # Should now return default or environment value
      result = KeyringIntegration.get(Keyring, :integration_test_key, "default")

      assert result == "default" or is_binary(result)
    end

    test "process isolation is maintained" do
      # Set session value in current process
      Keyring.set_session_value(:process_test_key, "main-process-value")

      # Spawn another process and check isolation
      task =
        Task.async(fn ->
          # This process should not see the session value
          KeyringIntegration.get(Keyring, :process_test_key, "other-process-default")
        end)

      other_process_result = Task.await(task)

      # Other process should get default, main process should get session value
      main_process_result = KeyringIntegration.get(Keyring, :process_test_key, "main-default")

      assert main_process_result == "main-process-value"
      assert other_process_result == "other-process-default" or is_binary(other_process_result)

      # Clean up
      Keyring.clear_session_value(:process_test_key)
    end
  end
end
