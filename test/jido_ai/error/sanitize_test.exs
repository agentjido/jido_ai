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
  end

  describe "sanitize_error_for_display/1" do
    test "returns user-safe and log-safe messages" do
      result = Sanitize.sanitize_error_for_display(%RuntimeError{message: "File: /secret/path/config.exs"})
      assert is_binary(result.user_message)
      assert is_binary(result.log_message)
      refute result.user_message =~ "/secret/"
    end
  end
end
