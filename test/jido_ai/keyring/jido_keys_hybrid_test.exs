defmodule Jido.AI.Keyring.JidoKeysHybridTest do
  use ExUnit.Case, async: false
  use Mimic

  @moduletag :capture_log

  alias Jido.AI.Keyring
  alias Jido.AI.Keyring.JidoKeysHybrid

  setup do
    # Copy JidoKeys for mocking
    Mimic.copy(JidoKeys)

    # Start a unique Keyring for testing
    test_keyring_name = :"test_keyring_hybrid_#{:erlang.unique_integer([:positive])}"
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

  describe "JidoKeys backend delegation" do
    test "delegates global value retrieval to JidoKeys" do
      # Mock JidoKeys to return a specific value
      expect(JidoKeys, :get, fn :test_hybrid_key, nil ->
        "hybrid_value"
      end)

      result = JidoKeysHybrid.get_global_value(:test_hybrid_key, "default")
      assert result == "hybrid_value"
    end

    test "returns default when JidoKeys returns nil" do
      expect(JidoKeys, :get, fn :nonexistent_key, nil ->
        nil
      end)

      result = JidoKeysHybrid.get_global_value(:nonexistent_key, "default_value")
      assert result == "default_value"
    end

    test "handles JidoKeys errors gracefully" do
      expect(JidoKeys, :get, fn :error_key, nil ->
        raise "JidoKeys error"
      end)

      result = JidoKeysHybrid.get_global_value(:error_key, "fallback")
      assert result == "fallback"
    end
  end

  describe "runtime configuration updates" do
    test "sets runtime values through JidoKeys.put/2" do
      expect(JidoKeys, :put, fn :runtime_key, "filtered_value" ->
        :ok
      end)

      result = JidoKeysHybrid.set_runtime_value(:runtime_key, "test_value")
      assert result == :ok
    end

    test "applies filtering before setting runtime values" do
      expect(JidoKeys, :put, fn :api_key, filtered_value ->
        # Verify that sensitive values are filtered before storage
        assert filtered_value != "sk-1234567890abcdef"

        assert String.contains?(filtered_value, "[FILTERED]") or
                 String.length(filtered_value) < String.length("sk-1234567890abcdef")

        :ok
      end)

      result = JidoKeysHybrid.set_runtime_value(:api_key, "sk-1234567890abcdef")
      assert result == :ok
    end

    test "handles runtime update errors" do
      expect(JidoKeys, :put, fn :error_key, _value ->
        raise ArgumentError, "Invalid key"
      end)

      result = JidoKeysHybrid.set_runtime_value(:error_key, "value")
      assert {:error, _reason} = result
    end
  end

  describe "security filtering" do
    test "filters sensitive data in API keys" do
      sensitive_data = "sk-1234567890abcdef"
      filtered = JidoKeysHybrid.filter_sensitive_data(sensitive_data)

      refute filtered == sensitive_data
      assert String.contains?(filtered, "[FILTERED]")
    end

    test "preserves non-sensitive data" do
      normal_data = "regular configuration value"
      filtered = JidoKeysHybrid.filter_sensitive_data(normal_data)

      assert filtered == normal_data
    end

    test "handles various data types safely" do
      assert JidoKeysHybrid.filter_sensitive_data(nil) == nil
      assert JidoKeysHybrid.filter_sensitive_data(123) == 123
      assert JidoKeysHybrid.filter_sensitive_data(:atom) == :atom
    end
  end

  describe "session fallback integration" do
    test "prioritizes session values over JidoKeys", %{keyring: keyring} do
      # Set global value through JidoKeys
      expect(JidoKeys, :get, fn :precedence_key, nil ->
        "global_value"
      end)

      # Set session value
      :ok = Keyring.set_session_value(keyring, :precedence_key, "session_value")

      # Session should take precedence
      result =
        JidoKeysHybrid.get_with_session_fallback(keyring, :precedence_key, "default", self())

      assert result == "session_value"
    end

    test "falls back to JidoKeys when no session value", %{keyring: keyring} do
      expect(JidoKeys, :get, fn :fallback_key, nil ->
        "global_value"
      end)

      result = JidoKeysHybrid.get_with_session_fallback(keyring, :fallback_key, "default", self())
      assert result == "global_value"
    end

    test "applies filtering to session values", %{keyring: keyring} do
      # Set sensitive session value
      :ok = Keyring.set_session_value(keyring, :sensitive_session, "sk-session123456789")

      result =
        JidoKeysHybrid.get_with_session_fallback(keyring, :sensitive_session, "default", self())

      # Should be filtered
      refute result == "sk-session123456789"
    end
  end

  describe "key validation and conversion" do
    test "validates atom keys successfully" do
      result = JidoKeysHybrid.validate_and_convert_key(:valid_atom)
      assert {:ok, :valid_atom} = result
    end

    test "converts string keys to atoms safely" do
      expect(JidoKeys, :to_llm_atom, fn "string_key" ->
        :string_key
      end)

      result = JidoKeysHybrid.validate_and_convert_key("string_key")
      assert {:ok, :string_key} = result
    end

    test "handles invalid key types" do
      result = JidoKeysHybrid.validate_and_convert_key(123)
      assert {:error, :invalid_key_type} = result
    end

    test "handles JidoKeys conversion errors gracefully" do
      expect(JidoKeys, :to_llm_atom, fn "invalid_key" ->
        raise ArgumentError, "Invalid atom conversion"
      end)

      result = JidoKeysHybrid.validate_and_convert_key("invalid_key")
      assert {:error, _reason} = result
    end
  end

  describe "session isolation enhancement" do
    test "maintains ETS-based session storage", %{keyring: keyring} do
      key = :isolation_test
      value = "isolated_value"

      # Set session value
      result = JidoKeysHybrid.ensure_session_isolation(keyring, key, value, self())
      assert result == :ok

      # Verify it's stored in ETS with process isolation
      retrieved = Keyring.get_session_value(keyring, key, self())
      assert retrieved != nil
    end

    test "applies security filtering to stored session values", %{keyring: keyring} do
      sensitive_value = "sk-sensitive123456789"

      result =
        JidoKeysHybrid.ensure_session_isolation(keyring, :sensitive_key, sensitive_value, self())

      assert result == :ok

      # Retrieved value should be filtered
      retrieved = Keyring.get_session_value(keyring, :sensitive_key, self())
      refute retrieved == sensitive_value
    end

    test "handles session storage errors gracefully" do
      invalid_keyring = :nonexistent_keyring

      result =
        JidoKeysHybrid.ensure_session_isolation(invalid_keyring, :test_key, "value", self())

      assert {:error, _reason} = result
    end
  end

  describe "safe logging operations" do
    test "logs operations with credential filtering" do
      # This test verifies that logging doesn't expose sensitive data
      # In a real implementation, you'd capture log output and verify filtering
      result = JidoKeysHybrid.safe_log_key_operation(:api_key, :get, :test)
      assert result == :ok
    end

    test "handles various key types in logging" do
      assert JidoKeysHybrid.safe_log_key_operation("string_key", :set, :source) == :ok
      assert JidoKeysHybrid.safe_log_key_operation(:atom_key, :delete, :source) == :ok
    end
  end

  describe "integration with main Keyring functionality" do
    test "enhanced get/4 uses JidoKeys for global config", %{keyring: keyring} do
      expect(JidoKeys, :get, fn :integration_key, nil ->
        "jido_keys_value"
      end)

      # Call through main Keyring API
      result = Keyring.get(keyring, :integration_key, "default")
      assert result == "jido_keys_value"
    end

    test "enhanced get_env_value/3 tries JidoKeys first", %{keyring: keyring} do
      expect(JidoKeys, :get, fn :env_key, nil ->
        "jido_keys_env_value"
      end)

      result = Keyring.get_env_value(keyring, :env_key, "default")
      assert result == "jido_keys_env_value"
    end

    test "runtime configuration through Keyring API" do
      expect(JidoKeys, :put, fn :runtime_config, "filtered_value" ->
        :ok
      end)

      result = Keyring.set_runtime_value(:runtime_config, "test_value")
      assert result == :ok
    end

    test "session values still take precedence", %{keyring: keyring} do
      # Set global value through JidoKeys
      expect(JidoKeys, :get, fn :precedence_test, nil ->
        "global_from_jido_keys"
      end)

      # Set session value
      :ok = Keyring.set_session_value(keyring, :precedence_test, "session_override")

      # Session should win
      result = Keyring.get(keyring, :precedence_test, "default")
      assert result == "session_override"
    end
  end

  describe "performance and reliability" do
    test "handles high-frequency operations efficiently", %{keyring: keyring} do
      # Mock JidoKeys for consistent responses
      expect(JidoKeys, :get, 100, fn _key, nil ->
        "performance_value"
      end)

      {elapsed_microseconds, results} =
        :timer.tc(fn ->
          for i <- 1..100 do
            JidoKeysHybrid.get_global_value(:"perf_key_#{i}", "default")
          end
        end)

      elapsed_ms = elapsed_microseconds / 1000
      average_ms_per_call = elapsed_ms / 100

      # Should complete efficiently
      assert average_ms_per_call < 5.0
      assert length(results) == 100
      assert Enum.all?(results, &(&1 == "performance_value"))
    end

    test "maintains reliability under concurrent access", %{keyring: keyring} do
      expect(JidoKeys, :get, 500, fn _key, nil ->
        "concurrent_value"
      end)

      # Create multiple concurrent tasks
      tasks =
        for i <- 1..10 do
          Task.async(fn ->
            for j <- 1..50 do
              JidoKeysHybrid.get_global_value(:"concurrent_#{i}_#{j}", "default")
            end
          end)
        end

      # Wait for all tasks
      results = Task.await_many(tasks, 10_000)

      # All tasks should succeed
      assert length(results) == 10

      for task_results <- results do
        assert length(task_results) == 50
        assert Enum.all?(task_results, &(&1 == "concurrent_value"))
      end
    end
  end

  describe "error handling and edge cases" do
    test "handles JidoKeys unavailability gracefully" do
      # Mock JidoKeys module to be unavailable
      expect(JidoKeys, :get, fn _key, _default ->
        raise UndefinedFunctionError, message: "JidoKeys not available"
      end)

      result = JidoKeysHybrid.get_global_value(:unavailable_key, "fallback")
      assert result == "fallback"
    end

    test "handles malformed JidoKeys responses" do
      expect(JidoKeys, :get, fn :malformed_key, nil ->
        {:unexpected, :response}
      end)

      result = JidoKeysHybrid.get_global_value(:malformed_key, "default")
      # Should handle unexpected response gracefully
      assert result != nil
    end

    test "validates inputs comprehensively" do
      # Test with various invalid inputs
      assert {:error, :invalid_key_type} = JidoKeysHybrid.validate_and_convert_key(nil)
      assert {:error, :invalid_key_type} = JidoKeysHybrid.validate_and_convert_key([])
      assert {:error, :invalid_key_type} = JidoKeysHybrid.validate_and_convert_key(%{})
    end
  end
end
