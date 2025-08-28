defmodule Jido.AI.Middleware.CostCalculator do
  @moduledoc """
  Middleware for calculating LLM API request/response costs.

  Calculates costs based on token usage and model pricing during the response phase.
  Stores cost breakdown in context.meta.cost for downstream middleware and user access.

  ## Operation

  - **Request phase**: Passes through unchanged
  - **Response phase**: 
    - Attempts exact cost calculation using API usage data
    - Falls back to estimated cost using TokenCounter data from context
    - Stores cost breakdown in `context.meta.cost`

  ## Cost Data Sources (in priority order)

  1. **Exact usage**: Uses actual token counts from API response usage field
  2. **Token counter**: Uses token counts from TokenCounter middleware in context.meta
  3. **Fallback estimation**: Uses request/response bodies with TokenCounter module

  ## Usage

      middlewares = [
        Jido.AI.Middleware.TokenCounter,
        Jido.AI.Middleware.CostCalculator
      ]
      
      context = Middleware.run(middlewares, context, &api_call/1)
      cost = Context.get_meta(context, :cost)
      # => %{input_tokens: 1000, output_tokens: 500, total_cost: 0.0045, ...}

  ## Cost Breakdown Format

  The cost breakdown stored in context.meta.cost contains:

  - `input_tokens` - Number of input tokens
  - `output_tokens` - Number of output tokens  
  - `input_cost` - Input cost in USD
  - `output_cost` - Output cost in USD
  - `total_cost` - Total cost in USD
  - `currency` - Always "USD"

  Returns `nil` if cost calculation is not possible (e.g., model has no cost data).
  """

  @behaviour Jido.AI.Middleware

  alias Jido.AI.{CostCalculator, Middleware.Context}

  require Logger

  @doc """
  Middleware callback that calculates costs during the response phase.

  During request phase, passes context through unchanged.
  During response phase, attempts to calculate cost using available data sources.
  """
  @spec call(Context.t(), (Context.t() -> Context.t())) :: Context.t()
  def call(context, next) do
    # Store request body in metadata for potential fallback use
    context =
      case context.phase do
        :request -> Context.put_meta(context, :request_body, context.body)
        :response -> context
      end

    # Call next middleware/function
    context = next.(context)

    # Calculate cost during response phase
    case context.phase do
      :response -> calculate_and_store_cost(context)
      _ -> context
    end
  end

  @doc """
  Calculates cost breakdown and stores it in context metadata.

  Attempts cost calculation in priority order:
  1. From API usage data in response body
  2. From TokenCounter middleware token counts in context.meta
  3. Fallback estimation using request/response bodies

  ## Parameters

  - `context` - Middleware context in response phase

  ## Returns

  Context with cost breakdown stored in `context.meta.cost`, or unchanged
  context if cost calculation is not possible.
  """
  @spec calculate_and_store_cost(Context.t()) :: Context.t()
  def calculate_and_store_cost(%Context{phase: :response} = context) do
    cost = calculate_cost_from_context(context)

    case cost do
      nil ->
        Logger.debug("Cost calculation unavailable for model #{context.model.model}")
        context

      cost_breakdown ->
        Logger.debug("Calculated cost: #{CostCalculator.format_cost(cost_breakdown)}")
        Context.put_meta(context, :cost, cost_breakdown)
    end
  end

  # Calculates cost from available context data sources.
  # Tries multiple data sources in priority order until successful.
  @spec calculate_cost_from_context(Context.t()) :: CostCalculator.cost_breakdown() | nil
  defp calculate_cost_from_context(%Context{model: model, body: response_body, meta: meta} = context) do
    # Priority 1: Exact usage data from API response
    case extract_usage_from_response(response_body) do
      usage when is_map(usage) ->
        CostCalculator.calculate_cost_from_usage(model, usage)

      nil ->
        # Priority 2: Token counts from TokenCounter middleware
        case get_token_counts_from_meta(meta) do
          {input_tokens, output_tokens} when is_integer(input_tokens) and is_integer(output_tokens) ->
            CostCalculator.calculate_cost(model, input_tokens, output_tokens)

          nil ->
            # Priority 3: Fallback estimation using request/response bodies
            calculate_fallback_cost(context)
        end
    end
  end

  # Extracts usage data from API response body.
  # Supports different provider response formats.
  @spec extract_usage_from_response(map()) :: map() | nil
  defp extract_usage_from_response(%{"usage" => usage}) when is_map(usage), do: usage
  defp extract_usage_from_response(_), do: nil

  # Gets token counts from TokenCounter middleware metadata.
  # Looks for token count data stored by TokenCounter middleware.
  @spec get_token_counts_from_meta(map()) :: {non_neg_integer(), non_neg_integer()} | nil
  defp get_token_counts_from_meta(meta) do
    input_tokens = Map.get(meta, :input_tokens)
    output_tokens = Map.get(meta, :output_tokens)

    if is_integer(input_tokens) and is_integer(output_tokens) do
      {input_tokens, output_tokens}
    end
  end

  # Calculates cost using fallback estimation from request/response bodies.
  # Uses the original CostCalculator.calculate_request_cost/3 function as fallback
  # when exact usage data and TokenCounter metadata are not available.
  @spec calculate_fallback_cost(Context.t()) :: CostCalculator.cost_breakdown() | nil
  defp calculate_fallback_cost(%Context{model: model, meta: meta, body: response_body}) do
    # Get original request body from metadata (should be stored by request phase)
    case Map.get(meta, :request_body) do
      request_body when is_map(request_body) ->
        CostCalculator.calculate_request_cost(model, request_body, response_body)

      nil ->
        Logger.debug("No request body available for fallback cost calculation")
        nil
    end
  end
end
