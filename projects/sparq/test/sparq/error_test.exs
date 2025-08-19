defmodule Sparq.ErrorTest do
  use ExUnit.Case, async: true

  alias Sparq.Error

  describe "new/3" do
    test "creates error with basic fields" do
      error = Error.new(:runtime_error, "test message")
      assert error.type == :runtime_error
      assert error.message == "test message"
      assert error.frame_ref == nil
      assert error.context_ref == nil
      assert error.line == nil
      assert error.file == nil
    end

    test "creates error with optional fields" do
      frame_ref = make_ref()
      context_ref = make_ref()
      opts = [frame_ref: frame_ref, context_ref: context_ref, line: 42, file: "test.ex"]
      error = Error.new(:type_error, "test message", opts)

      assert error.type == :type_error
      assert error.message == "test message"
      assert error.frame_ref == frame_ref
      assert error.context_ref == context_ref
      assert error.line == 42
      assert error.file == "test.ex"
    end
  end

  describe "format_error/1" do
    test "formats error with location" do
      error = Error.new(:syntax_error, "bad syntax", file: "test.ex", line: 42)
      formatted = Error.format_error(error)
      assert formatted == "syntax_error at test.ex:42: bad syntax"
    end

    test "formats error without location" do
      error = Error.new(:runtime_error, "test error")
      formatted = Error.format_error(error)
      assert formatted == "runtime_error at unknown location: test error"
    end
  end

  describe "from_catch/2" do
    test "handles Sparq.Error directly" do
      error = Error.new(:runtime_error, "test error")
      assert Error.from_catch(:error, error) == error
    end

    test "handles badmatch with Sparq.Error" do
      error = Error.new(:runtime_error, "test error")
      caught = {:badmatch, {:error, error, nil}}
      assert Error.from_catch(:error, caught) == error
    end

    test "handles map with message" do
      caught = %{message: "test message"}
      error = Error.from_catch(:error, caught)
      assert error.type == :runtime_error
      assert error.message == "test message"
    end

    test "handles throw" do
      error = Error.from_catch(:throw, "test value")
      assert error.type == :runtime_error
      assert error.message =~ ~s(Uncaught throw: "test value")
    end

    test "handles exit" do
      error = Error.from_catch(:exit, :normal)
      assert error.type == :runtime_error
      assert error.message =~ "Process exit: :normal"
    end

    test "handles function clause error" do
      error = Error.from_catch(:error, :function_clause)
      assert error.type == :function_clause_error
      assert error.message == "No matching function clause"
    end

    test "handles atom error" do
      error = Error.from_catch(:error, :test_error)
      assert error.type == :runtime_error
      assert error.message == "test_error"
    end

    test "handles unknown error" do
      error = Error.from_catch(:unknown, %{custom: "error"})
      assert error.type == :runtime_error
      assert error.message =~ "Unhandled error: :unknown"
    end
  end

  describe "from_exception/1" do
    test "handles Sparq.Error directly" do
      error = Error.new(:runtime_error, "test error")
      assert Error.from_exception(error) == error
    end

    test "handles exception with message" do
      exception = %RuntimeError{message: "test message"}
      error = Error.from_exception(exception)
      assert error.type == :runtime_error
      assert error.message == "test message"
    end

    test "handles atom exception" do
      error = Error.from_exception(:test_error)
      assert error.type == :runtime_error
      assert error.message == "test_error"
    end

    test "handles unknown exception" do
      error = Error.from_exception(%{custom: "error"})
      assert error.type == :runtime_error
      assert error.message =~ "Unknown error:"
    end
  end
end
