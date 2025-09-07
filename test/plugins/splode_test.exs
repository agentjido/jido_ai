defmodule ReqLLM.Plugins.SplodeTest do
  use ExUnit.Case, async: true

  alias ReqLLM.Plugins.Splode
  alias ReqLLM.Error

  describe "attach/1" do
    test "attaches splode_errors step to error handling" do
      req = Req.new() |> Splode.attach()

      assert Enum.any?(req.error_steps, fn
               {:splode_errors, _fun} -> true
               _ -> false
             end)
    end
  end

  describe "handle_error_response/1" do
    test "converts 400 response to API.Request error" do
      request = %Req.Request{body: ~s({"model": "invalid"})}

      response = %Req.Response{
        status: 400,
        body: ~s({"error": {"message": "Invalid model specified"}})
      }

      {_req, error} = Splode.handle_error_response({request, response})

      assert %Error.API.Request{} = error
      assert error.status == 400
      assert error.reason == "Invalid model specified"
      assert error.response_body == ~s({"error": {"message": "Invalid model specified"}})
      assert error.request_body == ~s({"model": "invalid"})
    end

    test "converts 401 response to API.Request error with default message" do
      request = %Req.Request{body: nil}
      response = %Req.Response{status: 401, body: ""}

      {_req, error} = Splode.handle_error_response({request, response})

      assert %Error.API.Request{} = error
      assert error.status == 401
      assert error.reason == "Unauthorized - Invalid or missing API key"
    end

    test "converts 429 response to API.Request error" do
      request = %Req.Request{body: nil}

      response = %Req.Response{
        status: 429,
        body: ~s({"error": "Rate limit exceeded"})
      }

      {_req, error} = Splode.handle_error_response({request, response})

      assert %Error.API.Request{} = error
      assert error.status == 429
      assert error.reason == "Rate limit exceeded"
    end

    test "converts 500 response to API.Request error" do
      request = %Req.Request{body: nil}

      response = %Req.Response{
        status: 500,
        body: ~s({"message": "Internal server error"})
      }

      {_req, error} = Splode.handle_error_response({request, response})

      assert %Error.API.Request{} = error
      assert error.status == 500
      assert error.reason == "Internal server error"
    end

    @error_format_cases [
      %{
        name: "nested error message",
        body: ~s({"error": {"message": "Test error"}}),
        expected_reason: "Test error"
      },
      %{
        name: "simple error string",
        body: ~s({"error": "Simple error"}),
        expected_reason: "Simple error"
      },
      %{
        name: "direct message field",
        body: ~s({"message": "Direct message"}),
        expected_reason: "Direct message"
      },
      %{
        name: "detail field",
        body: ~s({"detail": "Detail message"}),
        expected_reason: "Detail message"
      },
      %{
        name: "error description",
        body: ~s({"error_description": "Description"}),
        expected_reason: "Description"
      }
    ]

    for test_case <- @error_format_cases do
      test "extracts error from JSON response formats - #{test_case.name}" do
        data = unquote(Macro.escape(test_case))

        request = %Req.Request{body: nil}
        response = %Req.Response{status: 400, body: data.body}

        {_req, error} = Splode.handle_error_response({request, response})

        assert error.reason == data.expected_reason
      end
    end

    test "converts exception to API.Request error" do
      request = %Req.Request{body: "test"}
      exception = %RuntimeError{message: "Connection failed"}

      {_req, error} = Splode.handle_error_response({request, exception})

      assert %Error.API.Request{} = error
      assert error.reason == "Connection failed"
      assert error.status == nil
      assert error.cause == exception
      assert error.request_body == "test"
    end
  end
end
