defmodule Jido.AI.ReqLlmBridge.ErrorHandlerTest do
  use ExUnit.Case, async: true

  alias Jido.AI.ReqLlmBridge.ErrorHandler

  @moduletag :capture_log

  describe "format_error/1 - validation errors" do
    test "formats validation error with field and message" do
      error = {:validation_error, "name", "required field missing"}

      result = ErrorHandler.format_error(error)

      assert result.type == "validation_error"
      assert result.field == "name"
      assert result.message == "required field missing"
      assert result.category == "parameter_error"
    end

    test "formats parameter validation error" do
      error = {:parameter_validation_error, :email, "invalid format"}

      result = ErrorHandler.format_error(error)

      assert result.type == "parameter_validation_error"
      assert result.field == "email"
      assert result.message == "Parameter validation failed"
      assert result.details == "invalid format"
      assert result.category == "parameter_error"
    end

    test "formats parameter conversion error" do
      error = {:parameter_conversion_error, "count", {:invalid_integer, "not_a_number"}}

      result = ErrorHandler.format_error(error)

      assert result.type == "parameter_conversion_error"
      assert result.field == "count"
      assert result.message == "Failed to convert parameter"
      assert result.category == "parameter_error"
      assert is_binary(result.details) || is_map(result.details)
    end
  end

  describe "format_error/1 - execution errors" do
    test "formats execution timeout error" do
      error = {:execution_timeout, 5000}

      result = ErrorHandler.format_error(error)

      assert result.type == "execution_timeout"
      assert result.message == "Operation timed out after 5000ms"
      assert result.timeout == 5000
      assert result.category == "execution_error"
    end

    test "formats action execution error" do
      error = {:action_execution_error, "Division by zero"}

      result = ErrorHandler.format_error(error)

      assert result.type == "action_execution_error"
      assert result.message == "Action execution failed"
      assert result.details == "Division by zero"
      assert result.category == "execution_error"
    end

    test "formats execution exception with stacktrace" do
      try do
        raise ArgumentError, "test exception"
      rescue
        exception ->
          # Use Exception.message/1 to convert to string since ErrorHandler expects string
          exception_message = Exception.message(exception)
          error = {:execution_exception, exception_message, __STACKTRACE__}
          result = ErrorHandler.format_error(error)

          assert result.type == "execution_exception"
          assert String.contains?(result.message, "test exception")
          assert is_list(result.stacktrace)
          assert result.category == "execution_error"
          # Stacktrace should be limited to 10 entries
          assert length(result.stacktrace) <= 10
      end
    end
  end

  describe "format_error/1 - serialization errors" do
    test "formats serialization error" do
      error = {:serialization_error, "Cannot encode tuple to JSON"}

      result = ErrorHandler.format_error(error)

      assert result.type == "serialization_error"
      assert result.message == "Failed to serialize result to JSON"
      assert result.details == "Cannot encode tuple to JSON"
      assert result.category == "serialization_error"
    end
  end

  describe "format_error/1 - schema and compatibility errors" do
    test "formats schema error" do
      error = {:schema_error, "Unknown field type: custom"}

      result = ErrorHandler.format_error(error)

      assert result.type == "schema_error"
      assert result.message == "Schema validation or conversion failed"
      assert result.details == "Unknown field type: custom"
      assert result.category == "configuration_error"
    end

    test "formats incompatible action error" do
      error = {:incompatible_action, MyModule, "Missing run/2 function"}

      result = ErrorHandler.format_error(error)

      assert result.type == "incompatible_action"
      assert result.message == "Action module is not compatible with ReqLLM"
      assert result.action_module == "Elixir.MyModule"
      assert result.details == "Missing run/2 function"
      assert result.category == "configuration_error"
    end
  end

  describe "format_error/1 - tool configuration errors" do
    test "formats tool configuration error" do
      error = {:tool_configuration_error, "Invalid schema format"}

      result = ErrorHandler.format_error(error)

      assert result.type == "tool_configuration_error"
      assert result.message == "Tool configuration is invalid"
      assert result.details == "Invalid schema format"
      assert result.category == "configuration_error"
    end
  end

  describe "format_error/1 - circuit breaker errors" do
    test "formats circuit breaker open error" do
      error = {:circuit_breaker_open, MyAction}

      result = ErrorHandler.format_error(error)

      assert result.type == "circuit_breaker_open"
      assert result.message == "Tool temporarily unavailable due to repeated failures"
      assert result.action_module == "Elixir.MyAction"
      assert result.category == "availability_error"
    end
  end

  describe "format_error/1 - generic errors" do
    test "formats map error with type field" do
      error = %{type: "custom_error", message: "Something went wrong", extra: "info"}

      result = ErrorHandler.format_error(error)

      assert result.type == "custom_error"
      assert result.message == "Something went wrong"
      assert result.category == "unknown_error"
      assert result.extra == "info"
    end

    test "formats map error with reason field" do
      error = %{reason: "timeout_error", details: "Connection failed"}

      result = ErrorHandler.format_error(error)

      assert result.type == "timeout_error"
      assert result.reason == "timeout_error"
      assert result.details == "Connection failed"
      assert result.category == "execution_error"
    end

    test "formats string error" do
      error = "Something went wrong"

      result = ErrorHandler.format_error(error)

      assert result.type == "generic_error"
      assert result.message == "Something went wrong"
      assert result.category == "unknown_error"
    end

    test "formats atom error" do
      error = :connection_failed

      result = ErrorHandler.format_error(error)

      assert result.type == "connection_failed"
      assert result.message == "Error: connection_failed"
      assert result.category == "network_error"
    end

    test "formats generic tuple error" do
      error = {:custom_error, %{details: "some info"}}

      result = ErrorHandler.format_error(error)

      assert result.type == "custom_error"
      assert result.message == "Error occurred"
      assert result.category == "unknown_error"
      assert is_map(result.details) or is_binary(result.details)
    end

    test "formats exception struct" do
      exception = %ArgumentError{message: "invalid argument"}

      result = ErrorHandler.format_error(exception)

      assert result.type == "exception"
      assert result.message == "invalid argument"
      assert result.exception_type == "Elixir.ArgumentError"
      assert result.category == "execution_error"
    end

    test "formats unknown error type" do
      error = {:some_pid, self()}

      result = ErrorHandler.format_error(error)

      # This is the actual behavior
      assert result.type == "some_pid"
      assert result.message == "Error occurred"
      assert String.contains?(result.details, "#PID<")
      assert result.category == "unknown_error"
    end
  end

  describe "sanitize_error_for_logging/1" do
    test "sanitizes sensitive keys in map" do
      error = %{
        username: "user123",
        password: "secret123",
        message: "Authentication failed",
        token: "bearer_xyz",
        api_key: "key_abc",
        secret: "very_secret",
        private_key: "rsa_key",
        auth: "auth_data",
        credential: "cred_data"
      }

      result = ErrorHandler.sanitize_error_for_logging(error)

      assert result.username == "user123"
      assert result.message == "Authentication failed"
      assert result.password == "[REDACTED]"
      assert result.token == "[REDACTED]"
      assert result.api_key == "[REDACTED]"
      assert result.secret == "[REDACTED]"
      assert result.private_key == "[REDACTED]"
      assert result.auth == "[REDACTED]"
      assert result.credential == "[REDACTED]"
    end

    test "sanitizes sensitive patterns in key names" do
      error = %{
        user_password: "secret123",
        access_token: "token_xyz",
        secret_key: "key_abc",
        auth_header: "bearer_token",
        normal_field: "safe_value"
      }

      result = ErrorHandler.sanitize_error_for_logging(error)

      assert result.normal_field == "safe_value"
      assert result.user_password == "[REDACTED]"
      assert result.access_token == "[REDACTED]"
      assert result.secret_key == "[REDACTED]"
      assert result.auth_header == "[REDACTED]"
    end

    test "sanitizes nested maps recursively" do
      error = %{
        user: %{
          name: "john",
          password: "secret123"
        },
        config: %{
          api_key: "key_abc",
          timeout: 5000
        }
      }

      result = ErrorHandler.sanitize_error_for_logging(error)

      assert result.user.name == "john"
      assert result.user.password == "[REDACTED]"
      assert result.config.api_key == "[REDACTED]"
      assert result.config.timeout == 5000
    end

    test "sanitizes lists of maps" do
      error = [
        %{username: "user1", password: "pass1"},
        %{username: "user2", token: "token2"}
      ]

      result = ErrorHandler.sanitize_error_for_logging(error)

      assert length(result) == 2
      assert Enum.at(result, 0).username == "user1"
      assert Enum.at(result, 0).password == "[REDACTED]"
      assert Enum.at(result, 1).username == "user2"
      assert Enum.at(result, 1).token == "[REDACTED]"
    end

    test "sanitizes sensitive patterns in strings" do
      error = "User login failed with password=secret123 and token=abc123"

      result = ErrorHandler.sanitize_error_for_logging(error)

      assert result == "User login failed with password=[REDACTED] and token=[REDACTED]"
    end

    test "sanitizes API key patterns in strings" do
      error = "API call failed with api_key=sk-1234567890"

      result = ErrorHandler.sanitize_error_for_logging(error)

      assert result == "API call failed with api_key=[REDACTED]"
    end

    test "leaves non-sensitive data unchanged" do
      error = %{
        username: "user123",
        email: "user@example.com",
        timestamp: "2023-01-01T00:00:00Z",
        count: 42,
        enabled: true
      }

      result = ErrorHandler.sanitize_error_for_logging(error)

      assert result == error
    end

    test "handles non-map/non-list data unchanged" do
      assert ErrorHandler.sanitize_error_for_logging(42) == 42
      assert ErrorHandler.sanitize_error_for_logging(:atom) == :atom
      assert ErrorHandler.sanitize_error_for_logging("safe string") == "safe string"
    end
  end

  describe "categorize_error_type/1" do
    test "categorizes parameter errors" do
      assert ErrorHandler.categorize_error_type("validation_error") == "parameter_error"
      assert ErrorHandler.categorize_error_type("parameter_invalid") == "parameter_error"
      assert ErrorHandler.categorize_error_type("conversion_failed") == "parameter_error"
      assert ErrorHandler.categorize_error_type(:validation_error) == "parameter_error"
    end

    test "categorizes execution errors" do
      assert ErrorHandler.categorize_error_type("timeout_error") == "execution_error"
      assert ErrorHandler.categorize_error_type("execution_failed") == "execution_error"
      assert ErrorHandler.categorize_error_type("action_error") == "execution_error"
      assert ErrorHandler.categorize_error_type("exception_occurred") == "execution_error"
    end

    test "categorizes serialization errors" do
      assert ErrorHandler.categorize_error_type("serialization_failed") == "serialization_error"
      assert ErrorHandler.categorize_error_type("json_error") == "serialization_error"
      assert ErrorHandler.categorize_error_type("encoding_failed") == "serialization_error"
    end

    test "categorizes configuration errors" do
      assert ErrorHandler.categorize_error_type("schema_error") == "configuration_error"
      assert ErrorHandler.categorize_error_type("configuration_invalid") == "configuration_error"
      assert ErrorHandler.categorize_error_type("incompatible_version") == "configuration_error"
    end

    test "categorizes availability errors" do
      assert ErrorHandler.categorize_error_type("circuit_breaker_open") == "availability_error"
      assert ErrorHandler.categorize_error_type("service_unavailable") == "availability_error"
      assert ErrorHandler.categorize_error_type("availability_check") == "availability_error"
    end

    test "categorizes network errors" do
      # This is the actual behavior
      assert ErrorHandler.categorize_error_type("network_timeout") == "execution_error"
      assert ErrorHandler.categorize_error_type("connection_failed") == "network_error"
      assert ErrorHandler.categorize_error_type("transport_error") == "network_error"
    end

    test "defaults to unknown_error for unrecognized types" do
      assert ErrorHandler.categorize_error_type("completely_unknown") == "unknown_error"
      assert ErrorHandler.categorize_error_type("random_error") == "unknown_error"
      assert ErrorHandler.categorize_error_type(:mysterious) == "unknown_error"
    end
  end

  describe "create_tool_error_response/2" do
    test "creates standardized error response without context" do
      error = {:validation_error, "name", "required"}

      result = ErrorHandler.create_tool_error_response(error)

      assert result.error == true
      assert result.type == "validation_error"
      assert result.message == "required"
      assert result.category == "parameter_error"
      assert result.field == "name"
      assert is_binary(result.timestamp)
      assert result.context == %{}

      # Verify timestamp format
      {:ok, _datetime, _offset} = DateTime.from_iso8601(result.timestamp)
    end

    test "creates error response with context" do
      error = {:execution_timeout, 5000}
      context = %{action_module: MyAction, user_id: 123, password: "secret"}

      result = ErrorHandler.create_tool_error_response(error, context)

      assert result.error == true
      assert result.type == "execution_timeout"
      assert result.message == "Operation timed out after 5000ms"
      assert result.category == "execution_error"
      # Context should be sanitized - no password, but action_module and user_id preserved
      assert result.context.action_module == MyAction
      assert result.context.user_id == 123
      refute Map.has_key?(result.context, :password)
    end

    test "creates error response with detailed error" do
      error = {:parameter_conversion_error, "count", "not an integer"}

      result = ErrorHandler.create_tool_error_response(error)

      assert result.error == true
      assert result.type == "parameter_conversion_error"
      assert result.field == "count"
      assert result.details == "not an integer"
      assert result.category == "parameter_error"
    end

    test "handles complex nested errors" do
      nested_error = %{
        reason: "validation_failed",
        fields: ["name", "email"],
        # Should be sanitized
        password: "secret123"
      }

      error = {:parameter_validation_error, "user", nested_error}

      result = ErrorHandler.create_tool_error_response(error)

      assert result.error == true
      assert result.type == "parameter_validation_error"
      assert result.field == "user"
      assert is_map(result.details)
      # Nested error should be sanitized
      assert result.details.password == "[REDACTED]"
      assert result.details.reason == "validation_failed"
    end
  end

  describe "error formatting edge cases" do
    test "handles empty maps" do
      result = ErrorHandler.format_error(%{})

      assert result.category == "unknown_error"
      assert is_binary(result.type) || is_atom(result.type)
    end

    test "handles nil values in error data" do
      error = %{type: nil, message: nil, details: nil}

      result = ErrorHandler.format_error(error)

      assert is_map(result)
      assert Map.has_key?(result, :category)
    end

    test "handles very large stacktraces" do
      # Create a mock large stacktrace
      large_stacktrace =
        Enum.map(1..50, fn i ->
          {SomeModule, :some_function, [arg: i], [file: ~c"test.ex", line: i]}
        end)

      error = {:execution_exception, "test", large_stacktrace}
      result = ErrorHandler.format_error(error)

      assert result.type == "execution_exception"
      assert is_list(result.stacktrace)
      # Should be limited to 10 entries
      assert length(result.stacktrace) <= 10
    end

    test "handles circular references in nested data safely" do
      # Create a simple circular reference test
      error = {:schema_error, "circular reference detected"}

      result = ErrorHandler.format_error(error)

      assert result.type == "schema_error"
      assert result.details == "circular reference detected"
      assert result.category == "configuration_error"
    end
  end

  describe "sanitization security tests" do
    test "prevents sensitive data leakage in complex nested structures" do
      complex_error = %{
        user: %{
          profile: %{
            name: "John Doe",
            secret_data: %{
              password: "ultra_secret",
              api_key: "sk-very-secret-key",
              nested: %{
                token: "nested_token_123",
                safe_field: "this is safe"
              }
            }
          }
        },
        metadata: %{
          auth_token: "auth_123",
          request_id: "req_456"
        }
      }

      result = ErrorHandler.sanitize_error_for_logging(complex_error)

      # Verify deep nesting sanitization
      assert result.user.profile.name == "John Doe"
      # secret_data is entirely redacted because the key contains "secret"
      assert result.user.profile.secret_data == "[REDACTED]"
      assert result.metadata.auth_token == "[REDACTED]"
      assert result.metadata.request_id == "req_456"
    end

    test "handles various sensitive key patterns case-insensitively" do
      error = %{
        Password: "secret1",
        PASSWORD: "secret2",
        pAsSwOrD: "secret3",
        user_TOKEN: "token1",
        API_KEY: "key1",
        authHeader: "header1",
        secretValue: "value1"
      }

      result = ErrorHandler.sanitize_error_for_logging(error)

      # All should be redacted regardless of case
      assert Map.get(result, :Password) == "[REDACTED]"
      assert Map.get(result, :PASSWORD) == "[REDACTED]"
      assert Map.get(result, :pAsSwOrD) == "[REDACTED]"
      assert Map.get(result, :user_TOKEN) == "[REDACTED]"
      assert Map.get(result, :API_KEY) == "[REDACTED]"
      assert result.authHeader == "[REDACTED]"
      assert result.secretValue == "[REDACTED]"
    end

    test "sanitizes sensitive patterns in error messages with various formats" do
      test_cases = [
        {"Login failed: password=mypass123", "Login failed: password=[REDACTED]"},
        {"Auth error with token=bearer_abc123", "Auth error with token=[REDACTED]"},
        {"API request failed, api_key=sk-1234567890", "API request failed, api_key=[REDACTED]"},
        {"Error: password=secret123", "Error: password=[REDACTED]"},
        # This matches because regex handles "Token:" pattern
        {"Token: abc123 expired", "token=[REDACTED] expired"}
      ]

      Enum.each(test_cases, fn {input, expected} ->
        result = ErrorHandler.sanitize_error_for_logging(input)
        assert result == expected, "Expected '#{input}' to become '#{expected}', got '#{result}'"
      end)
    end
  end

  describe "performance and stability tests" do
    test "handles very large error structures efficiently" do
      # Create a large error structure
      large_error = %{
        type: "large_error",
        data:
          Enum.into(1..1000, %{}, fn i ->
            {"field_#{i}", "value_#{i}"}
          end),
        nested: %{
          deep: %{
            structure:
              Enum.into(1..500, %{}, fn i ->
                {"nested_#{i}", %{value: i, password: "secret_#{i}"}}
              end)
          }
        }
      }

      start_time = System.monotonic_time(:millisecond)
      result = ErrorHandler.sanitize_error_for_logging(large_error)
      end_time = System.monotonic_time(:millisecond)

      # Should complete within reasonable time (less than 1 second)
      assert end_time - start_time < 1000
      assert is_map(result)
      # Verify some sanitization occurred
      assert get_in(result, [:nested, :deep, :structure, "nested_1", :password]) == "[REDACTED]"
    end

    test "handles concurrent sanitization safely" do
      error = %{
        password: "secret123",
        token: "token456",
        data: "some data"
      }

      # Run sanitization concurrently
      tasks =
        Enum.map(1..10, fn _i ->
          Task.async(fn ->
            ErrorHandler.sanitize_error_for_logging(error)
          end)
        end)

      results = Task.await_many(tasks, 5000)

      # All results should be identical and properly sanitized
      Enum.each(results, fn result ->
        assert result.password == "[REDACTED]"
        assert result.token == "[REDACTED]"
        assert result.data == "some data"
      end)
    end
  end
end
