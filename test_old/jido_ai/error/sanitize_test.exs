defmodule Jido.AI.Error.SanitizeTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Error.Sanitize

  describe "sanitize_error_message/2" do
    test "returns generic message for detailed exceptions" do
      assert "An error occurred" == Sanitize.sanitize_error_message(%RuntimeError{message: "internal details"})
    end

    test "returns mapped message for known atom reasons" do
      assert "Request timed out" == Sanitize.sanitize_error_message(:timeout)
      assert "Connection failed" == Sanitize.sanitize_error_message(:econnrefused)
    end

    test "supports verbose mode with code" do
      message = Sanitize.sanitize_error_message(:timeout, verbose: true, include_code: true)
      assert message =~ "timeout"
    end

    test "maps tuple reasons by first atom element and hides payload details" do
      assert "Validation failed" ==
               Sanitize.sanitize_error_message({:validation_error, %{field: "api_key", details: "sensitive"}})
    end

    test "returns processing-safe message for exception maps with file/line metadata" do
      error = %{__struct__: RuntimeError, __exception__: true, file: "/srv/secret.ex", line: 9}

      assert "An error occurred while processing your request" ==
               Sanitize.sanitize_error_message(error)
    end

    test "does not append code when include_code is false even in verbose mode" do
      message = Sanitize.sanitize_error_message(:timeout, verbose: true, include_code: false)
      refute message =~ "timeout)"
      assert message == "Request timed out"
    end

    test "falls back to generic message for unknown reasons and binaries" do
      assert "An error occurred" == Sanitize.sanitize_error_message(:unknown_reason)
      assert "An error occurred" == Sanitize.sanitize_error_message("raw internal message")
      assert "An error occurred" == Sanitize.sanitize_error_message({123, "bad tuple"})
    end
  end

  describe "sanitize_error_for_display/1" do
    test "returns user-safe and log-safe messages" do
      result = Sanitize.sanitize_error_for_display(%RuntimeError{message: "File: /secret/path/config.exs"})
      assert is_binary(result.user_message)
      assert is_binary(result.log_message)
      refute result.user_message =~ "/secret/"
    end

    test "preserves full details for logs while keeping user-safe message" do
      result =
        Sanitize.sanitize_error_for_display({:validation_error, %{field: "api_key", details: "secret=abc123"}})

      assert result.user_message == "Validation failed"
      assert result.log_message =~ "api_key"
      assert result.log_message =~ "secret=abc123"
    end
  end
end
