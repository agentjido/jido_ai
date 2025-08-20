defmodule Jido.AI.Middleware.CostCalculatorTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Middleware
  alias Jido.AI.{Model, Middleware, Middleware.Context, Middleware.CostCalculator}

  # Test fixtures
  def model_with_cost do
    %Model{
      provider: :openai,
      model: "gpt-4",
      cost: %{input: 1.5, output: 6.0}
    }
  end

  def model_without_cost do
    %Model{
      provider: :openai,
      model: "gpt-4",
      cost: nil
    }
  end

  def sample_request_body do
    %{
      "model" => "gpt-4",
      "messages" => [
        %{"role" => "user", "content" => "Hello world"}
      ]
    }
  end

  def sample_response_body do
    %{
      "choices" => [
        %{"message" => %{"content" => "Hi there!"}}
      ]
    }
  end

  def sample_response_with_usage do
    %{
      "choices" => [
        %{"message" => %{"content" => "Hi there!"}}
      ],
      "usage" => %{
        "prompt_tokens" => 1000,
        "completion_tokens" => 500
      }
    }
  end

  def sample_google_response_with_usage do
    %{
      "candidates" => [
        %{"content" => %{"parts" => [%{"text" => "Hi there!"}]}}
      ],
      "usage" => %{
        "promptTokenCount" => 800,
        "candidatesTokenCount" => 200
      }
    }
  end

  describe "call/2 - request phase" do
    test "passes through request phase unchanged" do
      context = Context.new(:request, model_with_cost(), sample_request_body(), [])

      result =
        CostCalculator.call(context, fn ctx ->
          # Simulate next middleware
          Context.put_phase(ctx, :response)
          |> Context.put_body(sample_response_body())
        end)

      # Should be in response phase after next middleware
      assert result.phase == :response
      assert result.body == sample_response_body()
    end
  end

  describe "call/2 - response phase with API usage data" do
    test "calculates cost from OpenAI-style usage data" do
      request_context = Context.new(:request, model_with_cost(), sample_request_body(), [])

      response_context =
        Context.put_phase(request_context, :response)
        |> Context.put_body(sample_response_with_usage())

      result = CostCalculator.call(response_context, fn ctx -> ctx end)

      cost = Context.get_meta(result, :cost)
      assert cost != nil
      assert cost.input_tokens == 1000
      assert cost.output_tokens == 500
      assert cost.input_cost == 0.0015
      assert cost.output_cost == 0.003
      assert_in_delta cost.total_cost, 0.0045, 0.00001
      assert cost.currency == "USD"
    end

    test "calculates cost from Google-style usage data" do
      model = %{model_with_cost() | provider: :google, model: "gemini-pro"}
      request_context = Context.new(:request, model, sample_request_body(), [])

      response_context =
        Context.put_phase(request_context, :response)
        |> Context.put_body(sample_google_response_with_usage())

      result = CostCalculator.call(response_context, fn ctx -> ctx end)

      cost = Context.get_meta(result, :cost)
      assert cost != nil
      assert cost.input_tokens == 800
      assert cost.output_tokens == 200
      assert cost.input_cost == 0.0012
      assert cost.output_cost == 0.0012
      assert_in_delta cost.total_cost, 0.0024, 0.00001
      assert cost.currency == "USD"
    end
  end

  describe "call/2 - response phase with TokenCounter metadata" do
    test "uses token counts from middleware metadata" do
      request_context = Context.new(:request, model_with_cost(), sample_request_body(), [])

      response_context =
        Context.put_phase(request_context, :response)
        |> Context.put_body(sample_response_body())
        |> Context.put_meta(:input_tokens, 750)
        |> Context.put_meta(:output_tokens, 250)

      result = CostCalculator.call(response_context, fn ctx -> ctx end)

      cost = Context.get_meta(result, :cost)
      assert cost != nil
      assert cost.input_tokens == 750
      assert cost.output_tokens == 250
      assert cost.input_cost == 0.001125
      assert cost.output_cost == 0.0015
      assert_in_delta cost.total_cost, 0.002625, 0.00001
      assert cost.currency == "USD"
    end

    test "ignores partial token metadata" do
      request_context = Context.new(:request, model_with_cost(), sample_request_body(), [])

      response_context =
        Context.put_phase(request_context, :response)
        |> Context.put_body(sample_response_body())
        |> Context.put_meta(:input_tokens, 750)
        # Add request body for fallback
        |> Context.put_meta(:request_body, sample_request_body())

      # Missing output_tokens

      result = CostCalculator.call(response_context, fn ctx -> ctx end)

      # Should fall back to request cost calculation
      cost = Context.get_meta(result, :cost)
      assert cost != nil
      assert cost.input_tokens > 0
      assert cost.output_tokens > 0
      assert cost.total_cost > 0.0
    end
  end

  describe "call/2 - response phase with fallback estimation" do
    test "uses fallback cost calculation when no usage or token metadata" do
      request_context = Context.new(:request, model_with_cost(), sample_request_body(), [])

      response_context =
        Context.put_phase(request_context, :response)
        |> Context.put_body(sample_response_body())
        |> Context.put_meta(:request_body, sample_request_body())

      result = CostCalculator.call(response_context, fn ctx -> ctx end)

      cost = Context.get_meta(result, :cost)
      assert cost != nil
      assert cost.input_tokens > 0
      assert cost.output_tokens > 0
      assert cost.total_cost > 0.0
      assert cost.currency == "USD"
    end

    test "returns nil when no request body available for fallback" do
      request_context = Context.new(:request, model_with_cost(), sample_request_body(), [])

      response_context =
        Context.put_phase(request_context, :response)
        |> Context.put_body(sample_response_body())

      # No request_body in metadata

      result = CostCalculator.call(response_context, fn ctx -> ctx end)

      cost = Context.get_meta(result, :cost)
      assert cost == nil
    end
  end

  describe "call/2 - model without cost data" do
    test "returns context unchanged when model has no cost data" do
      request_context = Context.new(:request, model_without_cost(), sample_request_body(), [])

      response_context =
        Context.put_phase(request_context, :response)
        |> Context.put_body(sample_response_with_usage())

      result = CostCalculator.call(response_context, fn ctx -> ctx end)

      cost = Context.get_meta(result, :cost)
      assert cost == nil
    end
  end

  describe "calculate_and_store_cost/1" do
    test "stores cost in metadata when calculation succeeds" do
      context = Context.new(:response, model_with_cost(), sample_response_with_usage(), [])

      result = CostCalculator.calculate_and_store_cost(context)

      cost = Context.get_meta(result, :cost)
      assert cost != nil
      assert cost.total_cost > 0.0
    end

    test "leaves context unchanged when cost calculation fails" do
      context = Context.new(:response, model_without_cost(), sample_response_body(), [])

      result = CostCalculator.calculate_and_store_cost(context)

      cost = Context.get_meta(result, :cost)
      assert cost == nil
    end
  end

  describe "middleware behavior compliance" do
    test "implements Middleware behavior" do
      # Verify the module implements the required callback
      assert function_exported?(CostCalculator, :call, 2)

      # Check that it's listed as implementing the behavior
      behaviors =
        CostCalculator.module_info(:attributes)
        |> Keyword.get_values(:behaviour)
        |> List.flatten()

      assert Middleware in behaviors
    end
  end

  describe "integration with Middleware.run/3" do
    test "works correctly in middleware pipeline" do
      middlewares = [CostCalculator]
      context = Context.new(:request, model_with_cost(), sample_request_body(), [])

      result =
        Middleware.run(middlewares, context, fn ctx ->
          # Simulate API call
          ctx
          |> Context.put_phase(:response)
          |> Context.put_body(sample_response_with_usage())
        end)

      assert result.phase == :response
      cost = Context.get_meta(result, :cost)
      assert cost != nil
      assert cost.total_cost > 0.0
    end

    test "works with multiple middleware in pipeline" do
      # Mock TokenCounter middleware for testing
      defmodule MockTokenCounter do
        @behaviour Jido.AI.Middleware

        def call(context, next) do
          # Call next first to get the response
          context = next.(context)

          # Add token counts in response phase
          case context.phase do
            :response ->
              context
              |> Context.put_meta(:input_tokens, 600)
              |> Context.put_meta(:output_tokens, 300)

            _ ->
              context
          end
        end
      end

      middlewares = [CostCalculator, MockTokenCounter]
      context = Context.new(:request, model_with_cost(), sample_request_body(), [])

      result =
        Middleware.run(middlewares, context, fn ctx ->
          # Simulate API call without usage data
          ctx
          |> Context.put_phase(:response)
          |> Context.put_body(sample_response_body())
          # Ensure fallback works if needed
          |> Context.put_meta(:request_body, sample_request_body())
        end)

      assert result.phase == :response
      cost = Context.get_meta(result, :cost)
      assert cost != nil
      assert cost.input_tokens == 600
      assert cost.output_tokens == 300
      assert cost.total_cost > 0.0
    end
  end

  describe "cost calculation priority order" do
    test "prefers API usage over TokenCounter metadata" do
      context =
        Context.new(:response, model_with_cost(), sample_response_with_usage(), [])
        # Different from usage data
        |> Context.put_meta(:input_tokens, 999)
        # Different from usage data
        |> Context.put_meta(:output_tokens, 999)

      result = CostCalculator.call(context, fn ctx -> ctx end)

      cost = Context.get_meta(result, :cost)
      assert cost != nil
      # Should use API usage (1000, 500) not metadata (999, 999)
      assert cost.input_tokens == 1000
      assert cost.output_tokens == 500
    end

    test "falls back to TokenCounter metadata when no API usage" do
      context =
        Context.new(:response, model_with_cost(), sample_response_body(), [])
        |> Context.put_meta(:input_tokens, 800)
        |> Context.put_meta(:output_tokens, 400)
        |> Context.put_meta(:request_body, sample_request_body())

      result = CostCalculator.call(context, fn ctx -> ctx end)

      cost = Context.get_meta(result, :cost)
      assert cost != nil
      # Should use metadata values, not fallback estimation
      assert cost.input_tokens == 800
      assert cost.output_tokens == 400
    end

    test "falls back to request estimation when no usage or metadata" do
      context =
        Context.new(:response, model_with_cost(), sample_response_body(), [])
        |> Context.put_meta(:request_body, sample_request_body())

      result = CostCalculator.call(context, fn ctx -> ctx end)

      cost = Context.get_meta(result, :cost)
      assert cost != nil
      # Should use estimated values from TokenCounter module functions
      assert cost.input_tokens > 0
      assert cost.output_tokens > 0
      assert cost.total_cost > 0.0
    end
  end
end
