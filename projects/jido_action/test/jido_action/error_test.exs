defmodule Jido.Action.ErrorTest do
  use ExUnit.Case, async: true

  alias Jido.Action.Error

  describe "error creation functions" do
    test "validation_error/2 creates InvalidInputError with details" do
      error = Error.validation_error("must be positive", field: :count, value: -1)

      assert %Error.InvalidInputError{} = error
      assert error.message == "must be positive"
      assert error.field == :count
      assert error.value == -1
      assert error.details[:field] == :count
      assert error.details[:value] == -1
    end

    test "validation_error/1 creates InvalidInputError with defaults" do
      error = Error.validation_error("invalid input")

      assert %Error.InvalidInputError{} = error
      assert error.message == "invalid input"
      assert error.field == nil
      assert error.value == nil
      assert error.details == %{}
    end

    test "execution_error/2 creates ExecutionFailureError" do
      error = Error.execution_error("failed to execute", step: :process)

      assert %Error.ExecutionFailureError{} = error
      assert error.message == "failed to execute"
      assert error.details[:step] == :process
    end

    test "execution_error/1 creates ExecutionFailureError with defaults" do
      error = Error.execution_error("execution failed")

      assert %Error.ExecutionFailureError{} = error
      assert error.message == "execution failed"
      assert error.details == %{}
    end

    test "config_error/2 creates ConfigurationError" do
      error = Error.config_error("missing required config", key: :database_url)

      assert %Error.ConfigurationError{} = error
      assert error.message == "missing required config"
      assert error.details[:key] == :database_url
    end

    test "config_error/1 creates ConfigurationError with defaults" do
      error = Error.config_error("configuration error")

      assert %Error.ConfigurationError{} = error
      assert error.message == "configuration error"
      assert error.details == %{}
    end

    test "timeout_error/2 creates TimeoutError with timeout value" do
      error = Error.timeout_error("operation timed out", timeout: 5000)

      assert %Error.TimeoutError{} = error
      assert error.message == "operation timed out"
      assert error.timeout == 5000
      assert error.details[:timeout] == 5000
    end

    test "timeout_error/1 creates TimeoutError with defaults" do
      error = Error.timeout_error("timeout occurred")

      assert %Error.TimeoutError{} = error
      assert error.message == "timeout occurred"
      assert error.timeout == nil
      assert error.details == %{}
    end

    test "internal_error/2 creates InternalError" do
      error = Error.internal_error("unexpected failure", component: :database)

      assert %Error.InternalError{} = error
      assert error.message == "unexpected failure"
      assert error.details[:component] == :database
    end

    test "internal_error/1 creates InternalError with defaults" do
      error = Error.internal_error("internal error")

      assert %Error.InternalError{} = error
      assert error.message == "internal error"
      assert error.details == %{}
    end
  end

  describe "exception creation" do
    test "InvalidInputError.exception/1 with all options" do
      error =
        Error.InvalidInputError.exception(
          message: "custom message",
          field: :email,
          value: "invalid@",
          details: %{extra: "info"}
        )

      assert %Error.InvalidInputError{} = error
      assert error.message == "custom message"
      assert error.field == :email
      assert error.value == "invalid@"
      assert error.details == %{extra: "info"}
    end

    test "InvalidInputError.exception/1 with defaults" do
      error = Error.InvalidInputError.exception([])

      assert %Error.InvalidInputError{} = error
      assert error.message == "Invalid input"
      assert error.field == nil
      assert error.value == nil
      assert error.details == %{}
    end

    test "ExecutionFailureError.exception/1 with all options" do
      error =
        Error.ExecutionFailureError.exception(
          message: "execution failed",
          details: %{step: "validation"}
        )

      assert %Error.ExecutionFailureError{} = error
      assert error.message == "execution failed"
      assert error.details == %{step: "validation"}
    end

    test "ExecutionFailureError.exception/1 with defaults" do
      error = Error.ExecutionFailureError.exception([])

      assert %Error.ExecutionFailureError{} = error
      assert error.message == "Execution failed"
      assert error.details == %{}
    end

    test "TimeoutError.exception/1 with all options" do
      error =
        Error.TimeoutError.exception(
          message: "timed out",
          timeout: 1000,
          details: %{operation: "network"}
        )

      assert %Error.TimeoutError{} = error
      assert error.message == "timed out"
      assert error.timeout == 1000
      assert error.details == %{operation: "network"}
    end

    test "TimeoutError.exception/1 with defaults" do
      error = Error.TimeoutError.exception([])

      assert %Error.TimeoutError{} = error
      assert error.message == "Action timed out"
      assert error.timeout == nil
      assert error.details == %{}
    end

    test "ConfigurationError.exception/1 with all options" do
      error =
        Error.ConfigurationError.exception(
          message: "config missing",
          details: %{key: :api_url}
        )

      assert %Error.ConfigurationError{} = error
      assert error.message == "config missing"
      assert error.details == %{key: :api_url}
    end

    test "ConfigurationError.exception/1 with defaults" do
      error = Error.ConfigurationError.exception([])

      assert %Error.ConfigurationError{} = error
      assert error.message == "Configuration error"
      assert error.details == %{}
    end

    test "InternalError.exception/1 with all options" do
      error =
        Error.InternalError.exception(
          message: "system failure",
          details: %{subsystem: "cache"}
        )

      assert %Error.InternalError{} = error
      assert error.message == "system failure"
      assert error.details == %{subsystem: "cache"}
    end

    test "InternalError.exception/1 with defaults" do
      error = Error.InternalError.exception([])

      assert %Error.InternalError{} = error
      assert error.message == "Internal error"
      assert error.details == %{}
    end

    test "Internal.UnknownError.exception/1 with all options" do
      error =
        Error.Internal.UnknownError.exception(
          message: "unknown error",
          details: %{context: "test"}
        )

      assert %Error.Internal.UnknownError{} = error
      assert error.message == "unknown error"
      assert error.details == %{context: "test"}
    end

    test "Internal.UnknownError.exception/1 with defaults" do
      error = Error.Internal.UnknownError.exception([])

      assert %Error.Internal.UnknownError{} = error
      assert error.message == "Unknown error"
      assert error.details == %{}
    end
  end

  describe "NimbleOptions formatting" do
    test "format_nimble_config_error/3 with empty keys_path" do
      error = %NimbleOptions.ValidationError{
        keys_path: [],
        message: "required :name option not found"
      }

      result = Error.format_nimble_config_error(error, "Action", MyModule)

      expected =
        "Invalid configuration given to use Jido.Action (Elixir.MyModule): required :name option not found"

      assert result == expected
    end

    test "format_nimble_config_error/3 with keys_path" do
      error = %NimbleOptions.ValidationError{
        keys_path: [:schema, :name],
        message: "must be a string"
      }

      result = Error.format_nimble_config_error(error, "Action", MyModule)

      expected =
        "Invalid configuration given to use Jido.Action (Elixir.MyModule) for key [:schema, :name]: must be a string"

      assert result == expected
    end

    test "format_nimble_config_error/3 with binary error" do
      result = Error.format_nimble_config_error("simple error", "Action", MyModule)
      assert result == "simple error"
    end

    test "format_nimble_config_error/3 with other error type" do
      result = Error.format_nimble_config_error({:error, :reason}, "Action", MyModule)
      assert result == "{:error, :reason}"
    end

    test "format_nimble_validation_error/3 with empty keys_path" do
      error = %NimbleOptions.ValidationError{
        keys_path: [],
        message: "required :count option not found"
      }

      result = Error.format_nimble_validation_error(error, "Action", MyAction)

      expected =
        "Invalid parameters for Action (Elixir.MyAction): required :count option not found"

      assert result == expected
    end

    test "format_nimble_validation_error/3 with keys_path" do
      error = %NimbleOptions.ValidationError{
        keys_path: [:user, :email],
        message: "must be a valid email"
      }

      result = Error.format_nimble_validation_error(error, "Action", MyAction)

      expected =
        "Invalid parameters for Action (Elixir.MyAction) at [:user, :email]: must be a valid email"

      assert result == expected
    end

    test "format_nimble_validation_error/3 with binary error" do
      result = Error.format_nimble_validation_error("validation failed", "Action", MyAction)
      assert result == "validation failed"
    end

    test "format_nimble_validation_error/3 with other error type" do
      result = Error.format_nimble_validation_error(%{error: "bad"}, "Action", MyAction)
      assert result == "%{error: \"bad\"}"
    end
  end
end
