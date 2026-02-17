defmodule Jido.AI.Error.SanitizeTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Error.Sanitize

  describe "message/2" do
    test "returns generic message for structured errors" do
      error = %RuntimeError{message: "Detailed internal error"}
      assert "An error occurred" = Sanitize.message(error)
    end

    test "returns specific message for known error atoms" do
      assert "Request timed out" = Sanitize.message(:timeout)
      assert "Connection failed" = Sanitize.message(:econnrefused)
      assert "Authentication required" = Sanitize.message(:unauthorized)
      assert "Invalid input provided" = Sanitize.message(:invalid_input)
    end

    test "handles tuple and string errors" do
      assert "An error occurred" = Sanitize.message({:error, :reason})
      assert "An error occurred" = Sanitize.message("Sensitive internal error details")
    end

    test "includes code in verbose mode" do
      assert Sanitize.message(:timeout, verbose: true, include_code: true) =~ "timeout"
    end
  end

  describe "for_display/1" do
    test "returns user-safe and log messages" do
      error = %RuntimeError{message: "Internal error details"}
      result = Sanitize.for_display(error)

      assert is_binary(result.user_message)
      assert is_binary(result.log_message)
      assert result.user_message != result.log_message
      assert result.log_message =~ "RuntimeError"
    end
  end
end
