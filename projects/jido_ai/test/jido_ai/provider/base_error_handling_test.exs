defmodule Jido.AI.Provider.BaseErrorHandlingTest do
  use Jido.AI.TestSupport.HTTPCase
  use Jido.AI.TestSupport.KeyringCase

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

      session(openai_api_key: "sk-test-key") do
        with_error(429, error_body) do
          result = Base.default_generate_text(OpenAI, model, "Hello")

          assert {:error, %Request{} = error} = result
          assert error.status == 429
          assert error.reason == "Insufficient quota (insufficient_quota)"
          assert error.response_body == error_body
          # request_body should be sanitized for debugging purposes
          assert is_map(error.request_body)
          assert error.request_body["messages"] == "[REDACTED]"
        end
      end
    end

    test "handles generic request failures", %{test_name: test_name} do
      model = ModelFixtures.gpt4()

      session(openai_api_key: "sk-test-key") do
        # Test with 503 Service Unavailable
        with_error(503, %{"error" => %{"message" => "Service temporarily unavailable"}}) do
          result = Base.default_generate_text(OpenAI, model, "Hello")

          assert {:error, %Request{} = error} = result
          assert error.status == 503
          assert error.reason =~ "Service temporarily unavailable"
          # request_body should be sanitized for debugging purposes
          assert is_map(error.request_body)
          assert error.request_body["messages"] == "[REDACTED]"
        end
      end
    end

    test "formats basic HTTP errors without detailed body", %{test_name: test_name} do
      model = ModelFixtures.gpt4()

      session(openai_api_key: "sk-test-key") do
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
end
