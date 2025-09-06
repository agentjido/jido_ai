defmodule Kagi.ErrorTest do
  @moduledoc """
  Tests for Kagi error handling.
  """

  use ExUnit.Case, async: true

  alias Kagi.Error.{ConfigurationError, InvalidError, NotFoundError, ServerError}

  describe "NotFoundError" do
    test "generates proper message" do
      error = %NotFoundError{key: :api_key}
      message = NotFoundError.message(error)
      assert message == "Configuration key :api_key not found"
    end

    test "can be raised" do
      assert_raise NotFoundError, ~r/Configuration key :missing not found/, fn ->
        raise NotFoundError, key: :missing
      end
    end
  end

  describe "ConfigurationError" do
    test "generates proper message" do
      error = %ConfigurationError{reason: "Invalid config file"}
      message = ConfigurationError.message(error)
      assert message == "Configuration error: Invalid config file"
    end
  end

  describe "InvalidError" do
    test "generates proper message" do
      error = %InvalidError{field: :api_key, value: "invalid"}
      message = InvalidError.message(error)
      assert message == "Invalid value \"invalid\" for field api_key"
    end
  end

  describe "ServerError" do
    test "generates proper message" do
      error = %ServerError{reason: "Server crashed"}
      message = ServerError.message(error)
      assert message == "Server error: Server crashed"
    end
  end
end
