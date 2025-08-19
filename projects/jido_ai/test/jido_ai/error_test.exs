defmodule Jido.AI.ErrorTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Error.API.Request
  alias Jido.AI.Error.Invalid.Parameter
  alias Jido.AI.Error.Unknown.Unknown
  alias Jido.AI.Model

  describe "error types" do
    test "Parameter error with custom message" do
      error = Parameter.exception(parameter: "custom_param")
      assert Exception.message(error) == "Invalid parameter: custom_param"
    end

    test "API Request error with reason" do
      error = Request.exception(reason: "API request failed")
      assert Exception.message(error) == "API request failed: API request failed"
    end

    test "Unknown error with details" do
      error = Unknown.exception(error: "Unexpected error")
      assert Exception.message(error) == "Unknown error: \"Unexpected error\""
    end

    test "all errors are proper exceptions" do
      errors = [Parameter.exception([]), Request.exception([]), Unknown.exception([])]

      for error <- errors do
        assert is_exception(error)
        assert is_binary(Exception.message(error))
      end
    end
  end

  describe "integration with other modules" do
    test "parameter errors are used for validation failures" do
      # Test that our error types are used correctly by other modules
      case Model.from("invalid-format") do
        {:error, "Invalid model specification. Expected format: 'provider:model'"} -> :ok
        other -> flunk("Expected Invalid.Parameter error, got: #{inspect(other)}")
      end
    end

    test "errors contain helpful messages" do
      {:error, error} = Model.from("unknown:model")

      assert is_binary(error)
      assert String.length(error) > 0
      # Should contain some context about what went wrong
      assert error =~ "unknown" or error =~ "provider" or error =~ "model"
    end
  end
end
