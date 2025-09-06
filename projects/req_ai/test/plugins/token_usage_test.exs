defmodule ReqAI.Plugins.TokenUsageTest do
  use ExUnit.Case, async: true

  alias ReqAI.Plugins.TokenUsage
  alias ReqAI.Model

  describe "attach/2" do
    test "attaches plugin to request" do
      req = Req.new()
      model = Model.new(:openai, "gpt-4")

      attached_req = TokenUsage.attach(req, model)

      # Check that the plugin is attached
      assert Keyword.has_key?(attached_req.response_steps, :token_usage)
      assert attached_req.private[:req_ai_model] == model
    end

    test "works without model" do
      req = Req.new()

      attached_req = TokenUsage.attach(req)

      assert Keyword.has_key?(attached_req.response_steps, :token_usage)
      refute Map.has_key?(attached_req.private, :req_ai_model)
    end
  end

  describe "handle/1" do
    test "extracts usage from OpenAI format response" do
      model = Model.new(:openai, "gpt-4", cost: %{input: 0.03, output: 0.06})

      request = %Req.Request{
        private: %{req_ai_model: model}
      }

      response = %Req.Response{
        status: 200,
        body: %{
          "usage" => %{
            "prompt_tokens" => 100,
            "completion_tokens" => 50
          }
        },
        private: %{}
      }

      {_req, result} = TokenUsage.handle({request, response})

      expected_usage = %{
        tokens: %{input: 100, output: 50},
        # (100/1000 * 0.03) + (50/1000 * 0.06)
        cost: 0.006
      }

      assert get_in(result.private, [:req_ai, :usage]) == expected_usage
    end

    test "extracts usage from Anthropic format response" do
      model = Model.new(:anthropic, "claude-3", cost: %{input: 0.003, output: 0.015})

      request = %Req.Request{
        private: %{req_ai_model: model}
      }

      response = %Req.Response{
        status: 200,
        body: %{
          "usage" => %{
            "input_tokens" => 200,
            "output_tokens" => 100
          }
        },
        private: %{}
      }

      {_req, result} = TokenUsage.handle({request, response})

      expected_usage = %{
        tokens: %{input: 200, output: 100},
        # (200/1000 * 0.003) + (100/1000 * 0.015)
        cost: 0.0021
      }

      assert get_in(result.private, [:req_ai, :usage]) == expected_usage
    end

    test "handles missing usage data gracefully" do
      model = Model.new(:openai, "gpt-4")

      request = %Req.Request{
        private: %{req_ai_model: model}
      }

      response = %Req.Response{
        status: 200,
        body: %{"text" => "Hello world"},
        private: %{}
      }

      {req_result, resp_result} = TokenUsage.handle({request, response})

      # Should return request and response unchanged when no usage data
      assert req_result == request
      assert resp_result == response
    end

    test "handles model without cost data" do
      model = Model.new(:openai, "gpt-4", cost: nil)

      request = %Req.Request{
        private: %{req_ai_model: model}
      }

      response = %Req.Response{
        status: 200,
        body: %{
          "usage" => %{
            "prompt_tokens" => 100,
            "completion_tokens" => 50
          }
        },
        private: %{}
      }

      {_req, result} = TokenUsage.handle({request, response})

      expected_usage = %{
        tokens: %{input: 100, output: 50},
        cost: nil
      }

      assert get_in(result.private, [:req_ai, :usage]) == expected_usage
    end

    test "handles missing model gracefully" do
      request = %Req.Request{private: %{}}

      response = %Req.Response{
        status: 200,
        body: %{
          "usage" => %{
            "prompt_tokens" => 100,
            "completion_tokens" => 50
          }
        },
        private: %{}
      }

      {req_result, resp_result} = TokenUsage.handle({request, response})

      # Should return request and response unchanged when no model
      assert req_result == request
      assert resp_result == response
    end

    test "emits telemetry events" do
      model = Model.new(:openai, "gpt-4", cost: %{input: 0.03, output: 0.06})

      # Attach telemetry handler
      test_pid = self()

      :telemetry.attach(
        "test-token-usage",
        [:req_ai, :token_usage],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      request = %Req.Request{
        private: %{req_ai_model: model}
      }

      response = %Req.Response{
        status: 200,
        body: %{
          "usage" => %{
            "prompt_tokens" => 100,
            "completion_tokens" => 50
          }
        },
        private: %{}
      }

      TokenUsage.handle({request, response})

      # Should receive telemetry event
      assert_received {:telemetry, [:req_ai, :token_usage], measurements, metadata}
      assert measurements.tokens == %{input: 100, output: 50}
      assert measurements.cost == 0.006
      assert metadata.model == model

      :telemetry.detach("test-token-usage")
    end
  end
end
