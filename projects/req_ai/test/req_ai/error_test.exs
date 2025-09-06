defmodule ReqAI.ErrorTest do
  use ExUnit.Case, async: true
  doctest ReqAI.Error

  alias ReqAI.Error

  # Core error test cases with {module, exception_args, expected_message_fragment, expected_class}
  @error_test_cases [
    {Error.Invalid.Parameter, [parameter: "model"], "Invalid parameter: model", :invalid},
    {Error.API.Request, [reason: "timeout", status: 500], "API request failed (500): timeout", :api},
    {Error.API.Request, [reason: "network error"], "API request failed: network error", :api},
    {Error.Validation.Error, [reason: "Invalid temperature"], "Invalid temperature", :validation},
    {Error.Unknown.Unknown, [error: :test_error], "Unknown error: :test_error", :unknown},
    {Error.ObjectGeneration, [text: "bad json", cause: :json_decode_error], "Object generation failed: :json_decode_error", :invalid},
    {Error.ObjectGeneration, [text: "some text"], "Object generation failed: unable to parse generated content", :invalid},
    {Error.SchemaValidation, [validation_errors: [%{field: "name", message: "is required"}], schema: %{}], "Schema validation failed: name: is required", :invalid}
  ]

  describe "all error modules" do
    test "construction, message generation, and class verification" do
      for {module, args, expected_message_fragment, expected_class} <- @error_test_cases do
        # Test construction
        error = apply(module, :exception, [args])
        assert error.__struct__ == module

        # Test message generation
        message = apply(module, :message, [error])
        assert message =~ expected_message_fragment

        # Test class verification
        assert error.class == expected_class
      end
    end
  end

  describe "SchemaValidation advanced message handling" do
    test "handles complex validation error scenarios" do
      # Path-based errors
      error = Error.SchemaValidation.exception(
        validation_errors: [%{path: ["user", "address", "street"], message: "is required"}],
        schema: %{}
      )
      message = Error.SchemaValidation.message(error)
      assert message == "Schema validation failed: user.address.street: is required"

      # String errors
      error = Error.SchemaValidation.exception(validation_errors: ["Missing required field"], schema: %{})
      message = Error.SchemaValidation.message(error)
      assert message == "Schema validation failed: Missing required field"

      # Truncated multiple errors
      many_errors = for i <- 1..5, do: %{field: "field#{i}", message: "error"}
      error = Error.SchemaValidation.exception(validation_errors: many_errors, schema: %{})
      message = Error.SchemaValidation.message(error)
      assert message =~ "(and 2 more)"

      # Empty validation errors
      error = Error.SchemaValidation.exception(validation_errors: [], schema: %{})
      message = Error.SchemaValidation.message(error)
      assert message == "Schema validation failed: unknown validation errors"

      # Invalid validation errors format
      error = Error.SchemaValidation.exception(validation_errors: "not a list")
      message = Error.SchemaValidation.message(error)
      assert message == "Schema validation failed: generated data does not conform to expected schema"
    end
  end

  describe "ObjectGeneration text handling" do
    test "handles edge cases in text preview" do
      # Long text truncation
      long_text = String.duplicate("a", 150)
      error = Error.ObjectGeneration.exception(text: long_text)
      message = Error.ObjectGeneration.message(error)
      assert message =~ "..."
      refute String.length(message) > 200

      # Nil, empty, and non-string text
      for invalid_text <- [nil, "", %{invalid: "data"}] do
        error = Error.ObjectGeneration.exception(text: invalid_text)
        message = Error.ObjectGeneration.message(error)
        refute message =~ "preview:"
      end
    end
  end

  describe "validation_error helper" do
    test "creates validation error with tag, reason, and context" do
      error = Error.validation_error(:invalid_model_spec, "Bad model", model: "test")
      assert %Error.Validation.Error{
        tag: :invalid_model_spec,
        reason: "Bad model",
        context: [model: "test"]
      } = error

      # Default empty context
      error = Error.validation_error(:missing_param, "Parameter required")
      assert %Error.Validation.Error{
        tag: :missing_param,
        reason: "Parameter required",
        context: []
      } = error
    end
  end

  describe "error class helpers" do
    test "all error classes are properly configured" do
      error_classes = [Error.Invalid, Error.API, Error.Validation, Error.Unknown]
      
      for error_class <- error_classes do
        assert apply(error_class, :error_class?, [])
        assert apply(error_class, :exception, [[]])
      end
    end
  end

  describe "Splode integration" do
    test "error modules integrate with Splode framework" do
      # Test that errors can be created and have expected Splode behavior
      error = Error.Invalid.Parameter.exception(parameter: "test")
      assert is_exception(error)
      assert Exception.message(error) =~ "Invalid parameter: test"

      error = Error.API.Request.exception(reason: "timeout", status: 408)
      assert is_exception(error)
      assert Exception.message(error) =~ "API request failed (408): timeout"
    end
  end
end
