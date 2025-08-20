defmodule Jido.AI.Middleware.UsageExtractionTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Middleware
  alias Jido.AI.Test.Fixtures.{ModelFixtures, ProviderFixtures}
  alias Jido.AI.{Middleware.Context, Middleware.UsageExtraction}

  describe "call/2" do
    test "passes through request phase unchanged" do
      model = ModelFixtures.gpt4()
      context = Context.new(:request, model, %{"messages" => []}, [])

      result = UsageExtraction.call(context, fn ctx -> ctx end)

      assert result == context
      assert Context.get_meta(result, :usage) == nil
    end

    test "extracts usage during response phase" do
      model = ModelFixtures.gpt4()
      response_body = ProviderFixtures.openai_response("Hello", prompt_tokens: 10, completion_tokens: 20)
      context = Context.new(:response, model, response_body, [])

      result = UsageExtraction.call(context, fn ctx -> ctx end)

      expected_usage = %{
        input_tokens: 10,
        output_tokens: 20,
        total_tokens: 30
      }

      assert Context.get_meta(result, :usage) == expected_usage
    end

    test "passes through response phase when no usage data" do
      model = ModelFixtures.gpt4()
      response_body = %{"choices" => [%{"message" => %{"content" => "Hello"}}]}
      context = Context.new(:response, model, response_body, [])

      result = UsageExtraction.call(context, fn ctx -> ctx end)

      assert result == context
      assert Context.get_meta(result, :usage) == nil
    end
  end

  describe "extract_usage_from_response/1" do
    test "extracts OpenAI format usage with total_tokens" do
      response =
        ProviderFixtures.openai_response("test",
          prompt_tokens: 15,
          completion_tokens: 25,
          total_tokens: 40
        )

      result = UsageExtraction.extract_usage_from_response(response)

      assert result == %{
               input_tokens: 15,
               output_tokens: 25,
               total_tokens: 40
             }
    end

    test "extracts OpenAI format usage without total_tokens" do
      response = %{
        "usage" => %{
          "prompt_tokens" => 12,
          "completion_tokens" => 18
        }
      }

      result = UsageExtraction.extract_usage_from_response(response)

      assert result == %{
               input_tokens: 12,
               output_tokens: 18,
               total_tokens: 30
             }
    end

    test "extracts Mistral format usage (same as OpenAI)" do
      response =
        ProviderFixtures.mistral_response("test",
          prompt_tokens: 20,
          completion_tokens: 30,
          total_tokens: 50
        )

      result = UsageExtraction.extract_usage_from_response(response)

      assert result == %{
               input_tokens: 20,
               output_tokens: 30,
               total_tokens: 50
             }
    end

    test "extracts Google format usage with totalTokenCount" do
      response =
        ProviderFixtures.gemini_response("test",
          prompt_tokens: 25,
          completion_tokens: 35,
          total_tokens: 60
        )

      result = UsageExtraction.extract_usage_from_response(response)

      assert result == %{
               input_tokens: 25,
               output_tokens: 35,
               total_tokens: 60
             }
    end

    test "extracts Google format usage without totalTokenCount" do
      response = %{
        "usageMetadata" => %{
          "promptTokenCount" => 15,
          "candidatesTokenCount" => 25
        }
      }

      result = UsageExtraction.extract_usage_from_response(response)

      assert result == %{
               input_tokens: 15,
               output_tokens: 25,
               total_tokens: 40
             }
    end

    test "extracts Anthropic format usage" do
      response =
        ProviderFixtures.anthropic_response("test",
          input_tokens: 22,
          output_tokens: 33
        )

      result = UsageExtraction.extract_usage_from_response(response)

      assert result == %{
               input_tokens: 22,
               output_tokens: 33,
               total_tokens: 55
             }
    end

    test "returns nil for response without usage data" do
      response = %{"choices" => [%{"message" => %{"content" => "Hello"}}]}

      result = UsageExtraction.extract_usage_from_response(response)

      assert result == nil
    end

    test "returns nil for invalid response format" do
      assert UsageExtraction.extract_usage_from_response(nil) == nil
      assert UsageExtraction.extract_usage_from_response("invalid") == nil
      assert UsageExtraction.extract_usage_from_response(123) == nil
    end

    test "returns nil for usage with missing token fields" do
      response = %{
        "usage" => %{
          "prompt_tokens" => 10
          # missing completion_tokens
        }
      }

      result = UsageExtraction.extract_usage_from_response(response)

      assert result == nil
    end

    test "returns nil for usage with non-integer token values" do
      response = %{
        "usage" => %{
          "prompt_tokens" => "10",
          "completion_tokens" => "20"
        }
      }

      result = UsageExtraction.extract_usage_from_response(response)

      assert result == nil
    end
  end

  describe "extract_and_store_usage/1" do
    test "stores normalized usage in context metadata" do
      model = ModelFixtures.gpt4()

      response_body =
        ProviderFixtures.openai_response("test",
          prompt_tokens: 100,
          completion_tokens: 200,
          total_tokens: 300
        )

      context = Context.new(:response, model, response_body, [])

      result = UsageExtraction.extract_and_store_usage(context)

      expected_usage = %{
        input_tokens: 100,
        output_tokens: 200,
        total_tokens: 300
      }

      assert Context.get_meta(result, :usage) == expected_usage
    end

    test "returns unchanged context when no usage data" do
      model = ModelFixtures.gpt4()
      response_body = %{"choices" => [%{"message" => %{"content" => "Hello"}}]}
      context = Context.new(:response, model, response_body, [])

      result = UsageExtraction.extract_and_store_usage(context)

      assert result == context
      assert Context.get_meta(result, :usage) == nil
    end
  end

  describe "middleware integration" do
    test "works correctly in middleware pipeline" do
      model = ModelFixtures.gpt4()
      request_body = %{"messages" => [%{"role" => "user", "content" => "Hello"}]}
      context = Context.new(:request, model, request_body, [])

      # Simulate API call that returns usage data
      api_call = fn ctx ->
        response_body =
          ProviderFixtures.openai_response("Hi there!",
            prompt_tokens: 50,
            completion_tokens: 75,
            total_tokens: 125
          )

        ctx
        |> Context.put_phase(:response)
        |> Context.put_body(response_body)
      end

      result = Middleware.run([UsageExtraction], context, api_call)

      expected_usage = %{
        input_tokens: 50,
        output_tokens: 75,
        total_tokens: 125
      }

      assert Context.get_meta(result, :usage) == expected_usage
    end
  end
end
