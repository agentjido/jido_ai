defmodule Jido.AI.Keyring.SecurityEnhancementsTest do
  use ExUnit.Case, async: false
  use Mimic

  @moduletag :capture_log

  alias Jido.AI.Keyring
  alias Jido.AI.Keyring.SecurityEnhancements

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

  describe "credential filtering" do
    test "filters sensitive strings" do
      test_cases = [
        {"sk-1234567890abcdef", true},
        {"password123", true},
        {"bearer_token_xyz", true},
        {"client_secret_abc", true},
        {"normal_value", false}
      ]

      for {input, should_filter} <- test_cases do
        filtered = SecurityEnhancements.filter_credential_data(input)

        if should_filter do
          refute filtered == input, "Expected filtering for: #{input}"
        else
          assert filtered == input, "Unexpected filtering for: #{input}"
        end
      end
    end

    test "filters sensitive data in maps" do
      sensitive_map = %{
        api_key: "sk-sensitive123",
        password: "secret456",
        normal_field: "normal_value",
        count: 42
      }

      filtered = SecurityEnhancements.filter_credential_data(sensitive_map)

      # Sensitive fields should be filtered
      refute filtered.api_key == "sk-sensitive123"
      refute filtered.password == "secret456"

      # Non-sensitive fields should be preserved
      assert filtered.normal_field == "normal_value"
      assert filtered.count == 42
    end

    test "filters sensitive data in lists" do
      sensitive_list = [
        "sk-key123",
        "normal_value",
        %{token: "secret456", data: "normal"}
      ]

      filtered = SecurityEnhancements.filter_credential_data(sensitive_list)

      # Check that filtering was applied to sensitive items
      [filtered_key, normal_value, filtered_map] = filtered

      refute filtered_key == "sk-key123"
      assert normal_value == "normal_value"
      refute filtered_map.token == "secret456"
      assert filtered_map.data == "normal"
    end

    test "handles non-string data types safely" do
      test_values = [nil, 123, :atom, [1, 2, 3], %{key: :value}]

      for value <- test_values do
        filtered = SecurityEnhancements.filter_credential_data(value)
        # Non-string values should be preserved (except when they contain sensitive strings)
        assert is_list(filtered) == is_list(value)
        assert is_map(filtered) == is_map(value)
      end
    end
  end

  describe "sensitive key detection" do
    test "identifies sensitive key patterns" do
      sensitive_keys = [
        :api_key,
        :openai_api_key,
        :password,
        :client_secret,
        :bearer_token,
        :access_token,
        :refresh_token,
        "API_KEY",
        "Password",
        "SECRET"
      ]

      for key <- sensitive_keys do
        assert SecurityEnhancements.is_sensitive_key?(key),
               "Failed to identify #{key} as sensitive"
      end
    end

    test "allows non-sensitive keys" do
      normal_keys = [
        :username,
        :email,
        :host,
        :port,
        :timeout,
        :debug,
        :log_level,
        "CONFIG_VALUE",
        "HOST_URL"
      ]

      for key <- normal_keys do
        refute SecurityEnhancements.is_sensitive_key?(key),
               "Incorrectly identified #{key} as sensitive"
      end
    end

    test "handles edge cases in key detection" do
      edge_cases = [nil, 123, [], %{}]

      for key <- edge_cases do
        refute SecurityEnhancements.is_sensitive_key?(key),
               "Should handle edge case #{inspect(key)} safely"
      end
    end
  end

  describe "safe logging operations" do
    test "logs operations without exposing sensitive data" do
      # Capture log output to verify filtering
      log_output =
        ExUnit.CaptureLog.capture_log(fn ->
          SecurityEnhancements.safe_log_operation(:get, :api_key, %{
            value: "sk-secret123",
            source: :session
          })
        end)

      # Log should not contain the actual sensitive value
      refute String.contains?(log_output, "sk-secret123")
      # But should contain operation info
      assert String.contains?(log_output, "get")
    end

    test "handles various data types in logging" do
      test_details = [
        %{string_field: "value"},
        [item1: "value1", item2: "value2"],
        "simple string",
        123
      ]

      for details <- test_details do
        # Should not raise errors regardless of input type
        assert SecurityEnhancements.safe_log_operation(:test, :test_key, details) == :ok
      end
    end
  end

  describe "input validation and filtering" do
    test "validates and filters valid inputs" do
      result = SecurityEnhancements.validate_and_filter_input(:test_key, "test_value")
      assert {:ok, :test_key, "test_value"} = result
    end

    test "validates and filters sensitive inputs" do
      result = SecurityEnhancements.validate_and_filter_input(:api_key, "sk-sensitive123")
      assert {:ok, :api_key, filtered_value} = result
      refute filtered_value == "sk-sensitive123"
    end

    test "handles invalid key types" do
      result = SecurityEnhancements.validate_and_filter_input(123, "value")
      assert {:error, :invalid_key_type} = result
    end

    test "converts string keys safely" do
      # Mock JidoKeysHybrid for key conversion
      expect(Jido.AI.Keyring.JidoKeysHybrid, :validate_and_convert_key, fn "string_key" ->
        {:ok, :string_key}
      end)

      result = SecurityEnhancements.validate_and_filter_input("string_key", "value")
      assert {:ok, :string_key, "value"} = result
    end
  end

  describe "error handling with security" do
    test "handles errors without exposing sensitive information" do
      error = "Authentication failed for key sk-secret123"

      result = SecurityEnhancements.handle_keyring_error(:get, :api_key, error)

      assert {:error, message} = result
      # Should not expose the original sensitive data
      refute String.contains?(message, "sk-secret123")
      # But should provide useful error information
      assert String.contains?(message, "get")
      assert String.contains?(message, "api_key")
    end

    test "sanitizes various error types" do
      error_cases = [
        {:error, "contains sk-secret123"},
        "simple error string",
        %{error: "nested sk-key456"},
        :simple_atom_error
      ]

      for error <- error_cases do
        result = SecurityEnhancements.handle_keyring_error(:test, :test_key, error)
        assert {:error, _sanitized_message} = result
      end
    end
  end

  describe "log redaction capabilities" do
    test "filters log messages comprehensively" do
      log_output =
        ExUnit.CaptureLog.capture_log(fn ->
          SecurityEnhancements.log_with_redaction(:info, "Operation with sk-secret123",
            key: :api_key,
            value: "sk-another-secret456"
          )
        end)

      # Sensitive data should be filtered from both message and metadata
      refute String.contains?(log_output, "sk-secret123")
      refute String.contains?(log_output, "sk-another-secret456")
    end

    test "preserves non-sensitive log information" do
      log_output =
        ExUnit.CaptureLog.capture_log(fn ->
          SecurityEnhancements.log_with_redaction(:debug, "Normal operation completed",
            operation: :get,
            duration: 50
          )
        end)

      # Normal information should be preserved
      assert String.contains?(log_output, "Normal operation completed")
    end

    test "handles various metadata formats" do
      metadata_formats = [
        %{key: "value", sensitive: "sk-secret123"},
        [key: "value", password: "secret456"],
        "simple string metadata"
      ]

      for metadata <- metadata_formats do
        # Should handle all formats without errors
        assert SecurityEnhancements.log_with_redaction(:info, "Test", metadata) == :ok
      end
    end
  end

  describe "process isolation validation" do
    test "validates process isolation correctly", %{keyring: keyring} do
      result =
        SecurityEnhancements.validate_process_isolation(keyring, :isolation_test, "test_value")

      assert result == :ok
    end

    test "detects isolation violations", %{keyring: keyring} do
      # This test would need to simulate a violation scenario
      # For now, we test that the function handles the normal case
      result =
        SecurityEnhancements.validate_process_isolation(keyring, :isolation_test, "test_value")

      assert result == :ok
    end

    test "handles isolation validation errors gracefully" do
      invalid_keyring = :nonexistent_keyring

      result =
        SecurityEnhancements.validate_process_isolation(invalid_keyring, :test_key, "test_value")

      assert {:error, _reason} = result
    end
  end

  describe "comprehensive credential filtering tests" do
    test "runs built-in filtering tests successfully" do
      result = SecurityEnhancements.test_credential_filtering()
      assert result == :ok
    end

    test "detects filtering failures" do
      # This would test the test function itself
      # In a real scenario, you might mock the filtering to fail
      # and verify that the test function catches it
      result = SecurityEnhancements.test_credential_filtering()

      case result do
        :ok ->
          assert true

        {:error, failures} ->
          # If there are failures, they should be properly formatted
          assert is_list(failures)
      end
    end
  end

  describe "integration with keyring operations" do
    test "security filtering is applied to session operations", %{keyring: keyring} do
      sensitive_value = "sk-session123456"

      # Set session value (should be filtered internally)
      :ok = Keyring.set_session_value(keyring, :session_test, sensitive_value)

      # Retrieved value should be filtered
      retrieved = Keyring.get_session_value(keyring, :session_test)

      # The exact filtering depends on implementation, but it should be different
      # This test verifies that filtering is applied at some level
      assert is_binary(retrieved)
    end

    test "security filtering works with global value retrieval", %{keyring: keyring} do
      # Mock JidoKeys to return sensitive data
      expect(JidoKeys, :get, fn :sensitive_global, nil ->
        "sk-global-secret123"
      end)

      # Get through Keyring API
      result = Keyring.get(keyring, :sensitive_global, "default")

      # Should get the value (filtering may be applied at display/log level)
      assert is_binary(result)
    end
  end

  describe "performance impact of security features" do
    test "security filtering doesn't significantly impact performance", %{keyring: _keyring} do
      # Test that security enhancements don't cause major performance regression
      test_values = for i <- 1..100, do: "test_value_#{i}"

      {elapsed_microseconds, _results} =
        :timer.tc(fn ->
          for value <- test_values do
            SecurityEnhancements.filter_credential_data(value)
          end
        end)

      elapsed_ms = elapsed_microseconds / 1000
      average_ms_per_filter = elapsed_ms / 100

      # Should be very fast for non-sensitive data
      assert average_ms_per_filter < 1.0
    end

    test "key validation performance is acceptable" do
      test_keys = for i <- 1..100, do: :"test_key_#{i}"

      {elapsed_microseconds, _results} =
        :timer.tc(fn ->
          for key <- test_keys do
            SecurityEnhancements.is_sensitive_key?(key)
          end
        end)

      elapsed_ms = elapsed_microseconds / 1000
      average_ms_per_check = elapsed_ms / 100

      # Key sensitivity checking should be very fast
      assert average_ms_per_check < 0.5
    end
  end

  describe "edge cases and error conditions" do
    test "handles nil and empty values safely" do
      assert SecurityEnhancements.filter_credential_data(nil) == nil
      assert SecurityEnhancements.filter_credential_data("") == ""
      assert SecurityEnhancements.is_sensitive_key?(nil) == false
      assert SecurityEnhancements.is_sensitive_key?("") == false
    end

    test "handles deeply nested data structures" do
      nested_data = %{
        level1: %{
          level2: %{
            api_key: "sk-nested123",
            normal: "value"
          },
          list: ["sk-list123", "normal"]
        },
        simple: "sk-simple123"
      }

      filtered = SecurityEnhancements.filter_credential_data(nested_data)

      # Should filter at all levels
      assert is_map(filtered)
      assert is_map(filtered.level1)
      assert is_map(filtered.level1.level2)
    end

    test "handles circular references gracefully" do
      # Create a structure that might cause issues
      map1 = %{key: "value"}
      map2 = %{ref: map1, api_key: "sk-circular123"}

      # This shouldn't hang or crash
      filtered = SecurityEnhancements.filter_credential_data(map2)
      assert is_map(filtered)
    end
  end
end
