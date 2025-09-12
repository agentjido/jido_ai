defmodule ReqLLM.ErrorTest do
  use ExUnit.Case, async: true

  alias ReqLLM.Error

  describe "error class hierarchy" do
    test "error classes identify as their correct class" do
      assert Error.Invalid.error_class?()
      assert Error.API.error_class?()
      assert Error.Validation.error_class?()
      assert Error.Unknown.error_class?()
    end
  end

  describe "Invalid.Parameter" do
    test "creates error with parameter field and formats message" do
      error = Error.Invalid.Parameter.exception(parameter: "model")
      assert error.parameter == "model"
      assert error.__exception__ == true
      assert Error.Invalid.Parameter.message(error) == "Invalid parameter: model"
    end
  end

  describe "API.Request" do
    test "creates error with all fields and formats message with status" do
      error =
        Error.API.Request.exception(
          reason: "timeout",
          status: 408,
          response_body: "{}",
          request_body: "{}",
          cause: :timeout
        )

      assert error.reason == "timeout"
      assert error.status == 408
      assert error.response_body == "{}"
      assert error.request_body == "{}"
      assert error.cause == :timeout
      assert Error.API.Request.message(error) == "API request failed (408): timeout"
    end

    test "formats message without status when nil" do
      error = Error.API.Request.exception(reason: "network error", status: nil)
      assert Error.API.Request.message(error) == "API request failed: network error"
    end
  end

  describe "API.Response" do
    test "creates error with fields and formats message with status" do
      error =
        Error.API.Response.exception(
          reason: "invalid json",
          response_body: "invalid",
          status: 200
        )

      assert error.reason == "invalid json"
      assert error.response_body == "invalid"
      assert error.status == 200
      assert Error.API.Response.message(error) == "Provider response error (200): invalid json"
    end

    test "formats message without status when nil" do
      error = Error.API.Response.exception(reason: "parse error", status: nil)
      assert Error.API.Response.message(error) == "Provider response error: parse error"
    end
  end

  describe "Validation.Error" do
    test "creates error with all fields and correct type" do
      error =
        Error.Validation.Error.exception(
          tag: :invalid_model,
          reason: "Model not found",
          context: [model: "test"]
        )

      assert %Error.Validation.Error{} = error
      assert error.tag == :invalid_model
      assert error.reason == "Model not found"
      assert error.context == [model: "test"]
      assert Error.Validation.Error.message(error) == "Model not found"
    end
  end

  describe "Unknown.Unknown" do
    test "creates error with error field and formats message" do
      original_error = %RuntimeError{message: "something went wrong"}
      error = Error.Unknown.Unknown.exception(error: original_error)

      assert error.error == original_error
      assert Error.Unknown.Unknown.message(error) == "Unknown error: #{inspect(original_error)}"
    end
  end

  describe "Invalid.Provider" do
    test "creates error with provider field and formats message" do
      error = Error.Invalid.Provider.exception(provider: "nonexistent")
      assert error.provider == "nonexistent"
      assert Error.Invalid.Provider.message(error) == "Unknown provider: nonexistent"
    end
  end

  describe "Invalid.NotImplemented" do
    test "creates error with feature field and formats message" do
      error = Error.Invalid.NotImplemented.exception(feature: "streaming")
      assert error.feature == "streaming"
      assert Error.Invalid.NotImplemented.message(error) == "streaming not implemented"
    end
  end

  describe "Invalid.Schema" do
    test "creates error with reason field and formats message" do
      error = Error.Invalid.Schema.exception(reason: "missing required property")
      assert error.reason == "missing required property"
      assert Error.Invalid.Schema.message(error) == "Invalid schema: missing required property"
    end
  end

  describe "Invalid.Message" do
    test "creates error with reason and index, formats message with index" do
      error = Error.Invalid.Message.exception(reason: "empty content", index: 2)
      assert error.reason == "empty content"
      assert error.index == 2
      assert Error.Invalid.Message.message(error) == "Message at index 2: empty content"
    end

    test "formats message without index when nil" do
      error = Error.Invalid.Message.exception(reason: "invalid format", index: nil)
      assert Error.Invalid.Message.message(error) == "invalid format"
    end
  end

  describe "Invalid.MessageList" do
    test "creates error and formats message with received value" do
      received = "not a list"
      error = Error.Invalid.MessageList.exception(reason: "not a list", received: received)

      assert error.reason == "not a list"
      assert error.received == received

      assert Error.Invalid.MessageList.message(error) ==
               "Expected a list of messages, got: #{inspect(received)}"
    end

    test "formats message with received field even when nil" do
      error = Error.Invalid.MessageList.exception(reason: "empty list")
      assert Error.Invalid.MessageList.message(error) == "Expected a list of messages, got: nil"
    end
  end

  describe "Invalid.Content" do
    test "creates error and formats message with received value" do
      received = %{invalid: "content"}
      error = Error.Invalid.Content.exception(reason: "wrong type", received: received)

      assert error.reason == "wrong type"
      assert error.received == received

      assert Error.Invalid.Content.message(error) ==
               "Content must be a string or list of ContentPart structs, got: #{inspect(received)}"
    end

    test "formats message with received field even when nil" do
      error = Error.Invalid.Content.exception(reason: "empty content")

      assert Error.Invalid.Content.message(error) ==
               "Content must be a string or list of ContentPart structs, got: nil"
    end
  end

  describe "Invalid.Role" do
    test "creates error with role field and formats message" do
      error = Error.Invalid.Role.exception(role: :invalid_role)
      assert error.role == :invalid_role

      assert Error.Invalid.Role.message(error) ==
               "Invalid role: :invalid_role. Must be :user, :assistant, :system, or :tool"
    end
  end

  describe "validation_error/3 helper" do
    test "creates validation error with tag, reason, and context" do
      error = Error.validation_error(:invalid_model_spec, "Bad model", model: "test")

      assert %Error.Validation.Error{} = error
      assert error.tag == :invalid_model_spec
      assert error.reason == "Bad model"
      assert error.context == [model: "test"]
    end

    test "creates validation error with default empty context" do
      error = Error.validation_error(:test_error, "Test reason")

      assert error.tag == :test_error
      assert error.reason == "Test reason"
      assert error.context == []
    end
  end

  describe "error serialization" do
    test "errors are exceptions and can be raised" do
      error = Error.Invalid.Parameter.exception(parameter: "test")

      assert_raise Error.Invalid.Parameter, "Invalid parameter: test", fn ->
        raise error
      end
    end

    test "errors maintain Splode structure" do
      error = Error.API.Request.exception(reason: "test", status: 400)

      assert error.__struct__ == Error.API.Request
      assert error.__exception__ == true
      assert is_binary(Exception.message(error))
    end
  end
end
