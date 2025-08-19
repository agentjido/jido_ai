defmodule Jido.AI.CostCalculator do
  @moduledoc """
  Cost calculation functionality for LLM API requests and responses.

  Calculates costs based on token usage and model pricing from the models.dev schema.
  All costs are calculated in USD based on the model's cost structure.
  """

  alias Jido.AI.TokenCounter

  @type cost_breakdown :: %{
          input_tokens: non_neg_integer(),
          output_tokens: non_neg_integer(),
          input_cost: float(),
          output_cost: float(),
          total_cost: float(),
          currency: String.t()
        }

  @doc """
  Calculates the cost for a request/response pair.

  ## Parameters

  - `model` - The Model struct containing cost information
  - `request_tokens` - Number of input tokens
  - `response_tokens` - Number of output tokens

  ## Returns

  Cost breakdown struct with detailed pricing information.

  ## Examples

      iex> model = %{cost: %{input: 1.5, output: 6.0}}
      iex> CostCalculator.calculate_cost(model, 1000, 500)
      %{
        input_tokens: 1000,
        output_tokens: 500, 
        input_cost: 0.0015,
        output_cost: 0.003,
        total_cost: 0.0045,
        currency: "USD"
      }
  """
  @spec calculate_cost(map(), non_neg_integer(), non_neg_integer()) :: cost_breakdown() | nil
  def calculate_cost(%{cost: nil}, _input_tokens, _output_tokens), do: nil

  def calculate_cost(%{cost: cost}, input_tokens, output_tokens)
      when is_map(cost) and is_integer(input_tokens) and is_integer(output_tokens) do
    input_rate = Map.get(cost, :input, 0.0)
    output_rate = Map.get(cost, :output, 0.0)

    # Costs are typically per million tokens, convert to per token
    input_cost = input_tokens * input_rate / 1_000_000
    output_cost = output_tokens * output_rate / 1_000_000

    %{
      input_tokens: input_tokens,
      output_tokens: output_tokens,
      input_cost: input_cost,
      output_cost: output_cost,
      total_cost: input_cost + output_cost,
      currency: "USD"
    }
  end

  def calculate_cost(_model, _input_tokens, _output_tokens), do: nil

  @doc """
  Calculates cost from actual usage data returned by the API.

  This is preferred over estimate-based calculation as it uses exact token counts
  from the provider's response.

  ## Examples

      iex> model = %{cost: %{input: 1.5, output: 6.0}}
      iex> usage = %{"prompt_tokens" => 1000, "completion_tokens" => 500}
      iex> CostCalculator.calculate_cost_from_usage(model, usage)
      %{
        input_tokens: 1000,
        output_tokens: 500,
        input_cost: 0.0015,
        output_cost: 0.003,
        total_cost: 0.0045,
        currency: "USD"
      }
  """
  @spec calculate_cost_from_usage(map(), map()) :: cost_breakdown() | nil
  def calculate_cost_from_usage(%{cost: nil}, _usage), do: nil

  def calculate_cost_from_usage(model, %{"prompt_tokens" => input_tokens, "completion_tokens" => output_tokens}) do
    calculate_cost(model, input_tokens, output_tokens)
  end

  # Google format uses different field names
  def calculate_cost_from_usage(model, %{"promptTokenCount" => input_tokens, "candidatesTokenCount" => output_tokens}) do
    calculate_cost(model, input_tokens, output_tokens)
  end

  def calculate_cost_from_usage(_model, _usage), do: nil

  @doc """
  Calculates cost for a chat completion request body and response.

  Uses TokenCounter to determine token counts, then calculates cost.
  This is a fallback when exact usage data is not available.
  """
  @spec calculate_request_cost(map(), map(), map()) :: cost_breakdown() | nil
  def calculate_request_cost(model, request_body, response_body) do
    input_tokens = TokenCounter.count_request_tokens(request_body)
    output_tokens = TokenCounter.count_response_tokens(response_body)

    calculate_cost(model, input_tokens, output_tokens)
  end

  @doc """
  Calculates cost for streaming requests.

  ## Parameters

  - `model` - The Model struct containing cost information
  - `request_body` - The request body to count input tokens
  - `total_response_tokens` - Total response tokens from streaming
  """
  @spec calculate_stream_cost(map(), map(), non_neg_integer()) :: cost_breakdown() | nil
  def calculate_stream_cost(model, request_body, total_response_tokens) do
    input_tokens = TokenCounter.count_request_tokens(request_body)

    calculate_cost(model, input_tokens, total_response_tokens)
  end

  @doc """
  Formats a cost breakdown into a human-readable string.

  ## Examples

      iex> cost = %{input_tokens: 1000, output_tokens: 500, total_cost: 0.0045, currency: "USD"}
      iex> CostCalculator.format_cost(cost)
      "$0.0045 (1000 in + 500 out tokens)"
  """
  @spec format_cost(cost_breakdown() | nil) :: String.t()
  def format_cost(nil), do: "Cost unavailable"

  def format_cost(%{total_cost: total_cost, input_tokens: input, output_tokens: output, currency: _currency}) do
    formatted_cost = :erlang.float_to_binary(total_cost, [{:decimals, 6}, :compact])
    "$#{formatted_cost} (#{input} in + #{output} out tokens)"
  end

  @doc """
  Formats cost breakdown with detailed input/output costs.
  """
  @spec format_detailed_cost(cost_breakdown() | nil) :: String.t()
  def format_detailed_cost(nil), do: "Cost breakdown unavailable"

  def format_detailed_cost(%{
        input_tokens: input_tokens,
        output_tokens: output_tokens,
        input_cost: input_cost,
        output_cost: output_cost,
        total_cost: total_cost,
        currency: currency
      }) do
    """
    Cost Breakdown:
    • Input: #{input_tokens} tokens × $#{:erlang.float_to_binary(input_cost / input_tokens * 1_000_000, [{:decimals, 2}])}/1M = $#{:erlang.float_to_binary(input_cost, [{:decimals, 6}, :compact])}
    • Output: #{output_tokens} tokens × $#{:erlang.float_to_binary(output_cost / output_tokens * 1_000_000, [{:decimals, 2}])}/1M = $#{:erlang.float_to_binary(output_cost, [{:decimals, 6}, :compact])}
    • Total: $#{:erlang.float_to_binary(total_cost, [{:decimals, 6}, :compact])} #{currency}
    """
  end

  @doc """
  Gets the cost rates for a model.

  Returns the input and output costs per million tokens.
  """
  @spec get_model_rates(map()) :: {float(), float()} | nil
  def get_model_rates(%{cost: nil}), do: nil

  def get_model_rates(%{cost: cost}) when is_map(cost) do
    input_rate = Map.get(cost, :input, 0.0)
    output_rate = Map.get(cost, :output, 0.0)
    {input_rate, output_rate}
  end

  def get_model_rates(_), do: nil
end
