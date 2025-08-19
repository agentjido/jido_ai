defmodule Jido.AI.Provider.BaseErrorHandlingTest do
  use Jido.AI.TestSupport.HTTPCase

  alias Jido.AI.Error.API.Request
  alias Jido.AI.Provider.{Base, OpenAI}
  alias Jido.AI.Test.Fixtures.ModelFixtures

  describe "enhanced error handling" do
    test "captures detailed HTTP error information", %{test_name: test_name} do
      model = ModelFixtures.gpt4()

      error_body = %{
        "error" => %{
          "message" => "Insufficient quota",
          "type" => "insufficient_quota",
          "code" => "billing_hard_limit_reached"
        }
      }

      with_error(429, error_body) do
        result = Base.default_generate_text(OpenAI, model, "Hello")

        assert {:error, %Request{} = error} = result
        assert error.status == 429
        assert error.reason == "Insufficient quota (insufficient_quota)"
        assert error.response_body == error_body
        # request_body is only set for low-level HTTP errors, not response errors
        assert is_nil(error.request_body)
      end
    end

    test "handles generic request failures", %{test_name: test_name} do
      model = ModelFixtures.gpt4()

      # Test with 503 Service Unavailable
      with_error(503, %{"error" => %{"message" => "Service temporarily unavailable"}}) do
        result = Base.default_generate_text(OpenAI, model, "Hello")

        assert {:error, %Request{} = error} = result
        assert error.status == 503
        assert error.reason =~ "Service temporarily unavailable"
        assert is_nil(error.request_body)
      end
    end

    test "formats basic HTTP errors without detailed body", %{test_name: test_name} do
      model = ModelFixtures.gpt4()

      with_error(500, "Internal Server Error") do
        result = Base.default_generate_text(OpenAI, model, "Hello")

        assert {:error, %Request{} = error} = result
        assert error.status == 500
        assert error.reason == "HTTP 500: Internal Server Error"
        assert error.response_body == "Internal Server Error"
      end
    end
  end
end
