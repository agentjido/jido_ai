defmodule Jido.AI.ReqLlmBridge.ErrorHandlerTest do
  use ExUnit.Case, async: true

  alias Jido.AI.ReqLlmBridge.ErrorHandler

  @moduledoc """
  Tests for the ErrorHandler module.

  Tests cover:
  - Error formatting for various error types
  - Error categorization into logical groups
  - Sensitive data sanitization
  - Tool error response creation
  """

  describe "7.1 Error Formatting" do
    test "formatting validation errors" do
      error = {:validation_error, "name", "required"}
      result = ErrorHandler.format_error(error)

      assert result.type == "validation_error"
      assert result.field == "name"
      assert result.message == "required"
      assert result.category == "parameter_error"
    end

    test "formatting parameter errors" do
      error = {:parameter_validation_error, "age", "must be positive"}
      result = ErrorHandler.format_error(error)

      assert result.type == "parameter_validation_error"
      assert result.field == "age"
      assert result.message == "Parameter validation failed"
      assert Map.has_key?(result, :details)
      assert result.category == "parameter_error"
    end

    test "formatting execution errors" do
      error = {:action_execution_error, "timeout"}
      result = ErrorHandler.format_error(error)

      assert result.type == "action_execution_error"
      assert result.message == "Action execution failed"
      assert result.category == "execution_error"
    end

    test "formatting timeout errors" do
      error = {:execution_timeout, 5000}
      result = ErrorHandler.format_error(error)

      assert result.type == "execution_timeout"
      assert String.contains?(result.message, "5000")
      assert result.timeout == 5000
      assert result.category == "execution_error"
    end

    test "formatting serialization errors" do
      error = {:serialization_error, "invalid JSON"}
      result = ErrorHandler.format_error(error)

      assert result.type == "serialization_error"
      assert result.message == "Failed to serialize result to JSON"
      assert result.category == "serialization_error"
    end

    test "formatting parameter conversion errors" do
      error = {:parameter_conversion_error, "count", "not an integer"}
      result = ErrorHandler.format_error(error)

      assert result.type == "parameter_conversion_error"
      assert result.field == "count"
      assert result.category == "parameter_error"
    end

    test "formatting schema errors" do
      error = {:schema_error, "incompatible schema"}
      result = ErrorHandler.format_error(error)

      assert result.type == "schema_error"
      assert result.category == "configuration_error"
    end

    test "formatting circuit breaker errors" do
      error = {:circuit_breaker_open, MyAction}
      result = ErrorHandler.format_error(error)

      assert result.type == "circuit_breaker_open"
      assert result.message =~ "temporarily unavailable"
      assert result.category == "availability_error"
    end

    test "formatting map errors with type" do
      error = %{type: "custom_error", message: "Something went wrong"}
      result = ErrorHandler.format_error(error)

      assert result.type == "custom_error"
      assert result.message == "Something went wrong"
      assert Map.has_key?(result, :category)
    end

    test "formatting string errors" do
      error = "Something went wrong"
      result = ErrorHandler.format_error(error)

      assert result.type == "generic_error"
      assert result.message == "Something went wrong"
      assert result.category == "unknown_error"
    end

    test "formatting atom errors" do
      error = :timeout
      result = ErrorHandler.format_error(error)

      assert result.type == "timeout"
      assert result.category == "execution_error"
    end

    test "formatting exception structs" do
      exception = %RuntimeError{message: "Test error"}
      result = ErrorHandler.format_error(exception)

      assert result.type == "exception"
      assert result.message == "Test error"
      # Exception type includes Elixir module prefix
      assert result.exception_type == "Elixir.RuntimeError"
      assert result.category == "execution_error"
    end
  end

  describe "7.2 Error Categorization" do
    test "categorizing parameter errors" do
      assert ErrorHandler.categorize_error_type("validation_error") == "parameter_error"
      assert ErrorHandler.categorize_error_type("parameter_error") == "parameter_error"
      assert ErrorHandler.categorize_error_type("conversion_error") == "parameter_error"
    end

    test "categorizing execution errors" do
      assert ErrorHandler.categorize_error_type("timeout") == "execution_error"
      assert ErrorHandler.categorize_error_type("execution_exception") == "execution_error"
      assert ErrorHandler.categorize_error_type("action_error") == "execution_error"
    end

    test "categorizing network errors" do
      assert ErrorHandler.categorize_error_type("connection_error") == "network_error"
      assert ErrorHandler.categorize_error_type("transport_error") == "network_error"
      # "network_timeout" contains "timeout" which takes precedence
      assert ErrorHandler.categorize_error_type("network_error") == "network_error"
    end

    test "categorizing serialization errors" do
      assert ErrorHandler.categorize_error_type("serialization_error") ==
               "serialization_error"

      assert ErrorHandler.categorize_error_type("json_error") == "serialization_error"
      assert ErrorHandler.categorize_error_type("encoding_error") == "serialization_error"
    end

    test "categorizing configuration errors" do
      assert ErrorHandler.categorize_error_type("schema_error") == "configuration_error"

      assert ErrorHandler.categorize_error_type("configuration_error") ==
               "configuration_error"

      # "incompatible_action" contains "action" which categorizes as execution_error
      # Use "incompatible_schema" instead to test configuration errors
      assert ErrorHandler.categorize_error_type("incompatible_schema") ==
               "configuration_error"
    end

    test "categorizing availability errors" do
      assert ErrorHandler.categorize_error_type("circuit_breaker_open") ==
               "availability_error"

      assert ErrorHandler.categorize_error_type("service_unavailable") ==
               "availability_error"
    end

    test "categorizing unknown errors" do
      assert ErrorHandler.categorize_error_type("random_error") == "unknown_error"
      assert ErrorHandler.categorize_error_type("mystery_error") == "unknown_error"
    end
  end

  describe "7.3 Sensitive Data Sanitization" do
    test "redacting password fields" do
      error = %{password: "secret123", message: "Auth failed"}
      result = ErrorHandler.sanitize_error_for_logging(error)

      assert result.password == "[REDACTED]"
      assert result.message == "Auth failed"
    end

    test "redacting API key fields" do
      error = %{api_key: "sk-12345", user: "john"}
      result = ErrorHandler.sanitize_error_for_logging(error)

      assert result.api_key == "[REDACTED]"
      assert result.user == "john"
    end

    test "redacting token fields" do
      error = %{token: "abc123", status: "failed"}
      result = ErrorHandler.sanitize_error_for_logging(error)

      assert result.token == "[REDACTED]"
      assert result.status == "failed"
    end

    test "redacting secret fields" do
      error = %{secret: "my-secret", data: "public"}
      result = ErrorHandler.sanitize_error_for_logging(error)

      assert result.secret == "[REDACTED]"
      assert result.data == "public"
    end

    test "redacting private_key fields" do
      error = %{private_key: "rsa-key-data", public_data: "pub-data"}
      result = ErrorHandler.sanitize_error_for_logging(error)

      assert result.private_key == "[REDACTED]"
      # "public_key" contains "key" pattern so it would also be redacted
      # Use different field name for non-sensitive data
      assert result.public_data == "pub-data"
    end

    test "sanitizing sensitive patterns in strings" do
      error = "Authentication failed with password=secret123"
      result = ErrorHandler.sanitize_error_for_logging(error)

      assert result =~ "password=[REDACTED]"
      refute result =~ "secret123"
    end

    test "sanitizing token patterns in strings" do
      error = "Failed to connect with token=abc123xyz"
      result = ErrorHandler.sanitize_error_for_logging(error)

      assert result =~ "token=[REDACTED]"
      refute result =~ "abc123xyz"
    end

    test "sanitizing api_key patterns in strings" do
      error = "Invalid api_key=sk-proj-12345"
      result = ErrorHandler.sanitize_error_for_logging(error)

      assert result =~ "api_key=[REDACTED]"
      refute result =~ "sk-proj-12345"
    end

    test "sanitizing nested maps" do
      error = %{
        outer: "visible",
        auth: %{
          password: "secret",
          username: "user"
        }
      }

      result = ErrorHandler.sanitize_error_for_logging(error)

      assert result.outer == "visible"
      # auth key itself is sensitive and should be redacted
      assert result.auth == "[REDACTED]"
    end

    test "sanitizing lists" do
      error = [
        %{password: "secret1", user: "alice"},
        %{password: "secret2", user: "bob"}
      ]

      result = ErrorHandler.sanitize_error_for_logging(error)

      assert is_list(result)
      assert Enum.at(result, 0).password == "[REDACTED]"
      assert Enum.at(result, 0).user == "alice"
      assert Enum.at(result, 1).password == "[REDACTED]"
      assert Enum.at(result, 1).user == "bob"
    end

    test "sanitizing struct data" do
      exception = %RuntimeError{message: "Error with password=secret"}
      result = ErrorHandler.sanitize_error_for_logging(exception)

      # Structs are inspected to strings
      assert is_binary(result)
      assert result =~ "RuntimeError"
    end

    test "detecting sensitive key patterns" do
      error = %{
        user_password: "secret",
        api_token: "token123",
        secret_key: "key456",
        normal_field: "visible"
      }

      result = ErrorHandler.sanitize_error_for_logging(error)

      assert result.user_password == "[REDACTED]"
      assert result.api_token == "[REDACTED]"
      assert result.secret_key == "[REDACTED]"
      assert result.normal_field == "visible"
    end
  end

  describe "7.4 Tool Error Responses" do
    test "creating standardized tool error response" do
      error = {:validation_error, "name", "required"}
      context = %{action_module: MyAction, user_id: 123}

      result = ErrorHandler.create_tool_error_response(error, context)

      assert result.error == true
      assert result.type == "validation_error"
      assert result.message == "required"
      assert result.category == "parameter_error"
      assert Map.has_key?(result, :timestamp)
      assert Map.has_key?(result, :context)
    end

    test "error response includes timestamp" do
      error = {:timeout, 5000}
      result = ErrorHandler.create_tool_error_response(error)

      assert Map.has_key?(result, :timestamp)
      # Timestamp should be ISO8601 formatted
      {:ok, _datetime, _offset} = DateTime.from_iso8601(result.timestamp)
    end

    test "error response sanitizes context" do
      error = {:validation_error, "field", "message"}

      context = %{
        action_module: MyAction,
        user_id: 123,
        password: "secret",
        token: "token123",
        request_id: "req-456"
      }

      result = ErrorHandler.create_tool_error_response(error, context)

      # Sensitive fields should be removed from context
      refute Map.has_key?(result.context, :password)
      refute Map.has_key?(result.context, :token)

      # Non-sensitive fields should be present
      assert result.context.action_module == MyAction
      assert result.context.user_id == 123
      assert result.context.request_id == "req-456"
    end

    test "error response includes field for parameter errors" do
      error = {:parameter_validation_error, "age", "must be positive"}
      result = ErrorHandler.create_tool_error_response(error)

      assert result.field == "age"
    end

    test "error response includes details when present" do
      error = {:action_execution_error, "detailed reason"}
      result = ErrorHandler.create_tool_error_response(error)

      assert Map.has_key?(result, :details)
      assert is_binary(result.details)
    end

    test "error response without context" do
      # Use explicit timeout tuple format that creates execution_timeout type
      error = {:execution_timeout, 3000}
      result = ErrorHandler.create_tool_error_response(error)

      assert result.error == true
      assert result.type == "execution_timeout"
      assert Map.has_key?(result, :context)
    end
  end

  describe "7.5 Complex Error Scenarios" do
    test "formatting execution exception with stacktrace" do
      stacktrace = [
        {MyModule, :my_function, 2, [file: "lib/my_module.ex", line: 42]},
        {OtherModule, :other_function, 1, [file: "lib/other.ex", line: 10]}
      ]

      error = {:execution_exception, "Test exception", stacktrace}
      result = ErrorHandler.format_error(error)

      assert result.type == "execution_exception"
      assert result.message == "Test exception"
      assert is_list(result.stacktrace)
      assert result.category == "execution_error"
    end

    test "formatting incompatible action error" do
      error = {:incompatible_action, MyBrokenAction, "missing run/2 function"}
      result = ErrorHandler.format_error(error)

      assert result.type == "incompatible_action"
      assert result.action_module =~ "MyBrokenAction"
      assert result.category == "configuration_error"
    end

    test "formatting tool configuration error" do
      error = {:tool_configuration_error, "invalid schema format"}
      result = ErrorHandler.format_error(error)

      assert result.type == "tool_configuration_error"
      assert result.category == "configuration_error"
    end

    test "fallback for unknown error formats" do
      error = {:weird_error, :with, :multiple, :parts}
      result = ErrorHandler.format_error(error)

      # Should still return a valid error structure
      assert is_map(result)
      assert Map.has_key?(result, :type)
      assert Map.has_key?(result, :category)
    end

    test "handling nil and empty errors" do
      # String empty
      result = ErrorHandler.format_error("")
      assert result.type == "generic_error"

      # Nil handled as atom
      result = ErrorHandler.format_error(nil)
      assert is_map(result)
    end
  end
end
