defmodule Jido.AI.Middleware.UsageExtraction do
  @moduledoc """
  Middleware for extracting usage data from AI provider API responses.

  Extracts token usage information from API responses during the response phase
  and stores it in context.meta.usage in a normalized format. Supports different
  provider usage formats (OpenAI, Google, Anthropic, etc.).

  ## Operation

  - **Request phase**: Passes through unchanged
  - **Response phase**: 
    - Extracts usage data from API response body
    - Normalizes usage data to a common format
    - Stores normalized usage in `context.meta.usage`

  ## Normalized Usage Format

  The middleware normalizes different provider formats to:

      %{
        input_tokens: non_neg_integer(),
        output_tokens: non_neg_integer(),
        total_tokens: non_neg_integer()
      }

  ## Provider Support

  - **OpenAI**: `usage.prompt_tokens` → `input_tokens`, `usage.completion_tokens` → `output_tokens`
  - **Google**: `usageMetadata.promptTokenCount` → `input_tokens`, `usageMetadata.candidatesTokenCount` → `output_tokens`
  - **Anthropic**: `usage.input_tokens` → `input_tokens`, `usage.output_tokens` → `output_tokens`
  - **Mistral**: `usage.prompt_tokens` → `input_tokens`, `usage.completion_tokens` → `output_tokens`

  ## Usage

      middlewares = [
        Jido.AI.Middleware.UsageExtraction,
        Jido.AI.Middleware.CostCalculator
      ]
      
      context = Middleware.run(middlewares, context, &api_call/1)
      usage = Context.get_meta(context, :usage)
      # => %{input_tokens: 150, output_tokens: 75, total_tokens: 225}

  If usage data cannot be extracted, no usage metadata is stored.
  """

  @behaviour Jido.AI.Middleware

  alias Jido.AI.Middleware.Context

  require Logger

  @type normalized_usage :: %{
          input_tokens: non_neg_integer(),
          output_tokens: non_neg_integer(),
          total_tokens: non_neg_integer()
        }

  @doc """
  Middleware callback that extracts usage data during the response phase.

  During request phase, passes context through unchanged.
  During response phase, attempts to extract and normalize usage data from the API response.
  """
  @spec call(Context.t(), (Context.t() -> Context.t())) :: Context.t()
  def call(context, next) do
    # Call next middleware/function first
    context = next.(context)

    # Extract usage during response phase
    case context.phase do
      :response -> extract_and_store_usage(context)
      _ -> context
    end
  end

  @doc """
  Extracts usage data from response and stores it in context metadata.

  Attempts to extract usage data from the API response body and normalizes it
  to a common format regardless of provider.

  ## Parameters

  - `context` - Middleware context in response phase

  ## Returns

  Context with normalized usage data stored in `context.meta.usage`, or unchanged
  context if usage data cannot be extracted.
  """
  @spec extract_and_store_usage(Context.t()) :: Context.t()
  def extract_and_store_usage(%Context{phase: :response, body: response_body} = context) do
    case extract_usage_from_response(response_body) do
      nil ->
        Logger.debug("No usage data found in API response")
        context

      usage ->
        Logger.debug("Extracted usage: #{inspect(usage)}")
        Context.put_meta(context, :usage, usage)
    end
  end

  @doc """
  Extracts and normalizes usage data from an API response body.

  Supports multiple provider formats and returns a normalized usage structure.

  ## Parameters

  - `response_body` - The API response body map

  ## Returns

  Normalized usage map with `:input_tokens`, `:output_tokens`, and `:total_tokens`,
  or `nil` if no usage data can be extracted.

  ## Examples

      # OpenAI format
      iex> response = %{"usage" => %{"prompt_tokens" => 10, "completion_tokens" => 20, "total_tokens" => 30}}
      iex> UsageExtraction.extract_usage_from_response(response)
      %{input_tokens: 10, output_tokens: 20, total_tokens: 30}

      # Google format
      iex> response = %{"usageMetadata" => %{"promptTokenCount" => 15, "candidatesTokenCount" => 25, "totalTokenCount" => 40}}
      iex> UsageExtraction.extract_usage_from_response(response)
      %{input_tokens: 15, output_tokens: 25, total_tokens: 40}

      # Anthropic format
      iex> response = %{"usage" => %{"input_tokens" => 12, "output_tokens" => 18}}
      iex> UsageExtraction.extract_usage_from_response(response)
      %{input_tokens: 12, output_tokens: 18, total_tokens: 30}
  """
  @spec extract_usage_from_response(map()) :: normalized_usage() | nil
  def extract_usage_from_response(response_body) when is_map(response_body) do
    cond do
      # Google format: usageMetadata.promptTokenCount, usageMetadata.candidatesTokenCount
      google_usage = get_in(response_body, ["usageMetadata"]) ->
        normalize_google_usage(google_usage)

      # OpenAI/Mistral/Anthropic format: usage.*
      usage = get_in(response_body, ["usage"]) ->
        # Try Anthropic format first (input_tokens/output_tokens)
        case normalize_anthropic_usage(usage) do
          nil -> normalize_openai_usage(usage)
          result -> result
        end

      true ->
        nil
    end
  end

  def extract_usage_from_response(_), do: nil

  # Normalizes OpenAI/Mistral usage format
  @spec normalize_openai_usage(map()) :: normalized_usage() | nil
  defp normalize_openai_usage(%{"prompt_tokens" => input_tokens, "completion_tokens" => output_tokens} = usage)
       when is_integer(input_tokens) and is_integer(output_tokens) do
    total_tokens = Map.get(usage, "total_tokens", input_tokens + output_tokens)

    %{
      input_tokens: input_tokens,
      output_tokens: output_tokens,
      total_tokens: if(is_integer(total_tokens), do: total_tokens, else: input_tokens + output_tokens)
    }
  end

  defp normalize_openai_usage(_), do: nil

  # Normalizes Google usage format
  @spec normalize_google_usage(map()) :: normalized_usage() | nil
  defp normalize_google_usage(%{"promptTokenCount" => input_tokens, "candidatesTokenCount" => output_tokens} = usage)
       when is_integer(input_tokens) and is_integer(output_tokens) do
    total_tokens = Map.get(usage, "totalTokenCount", input_tokens + output_tokens)

    %{
      input_tokens: input_tokens,
      output_tokens: output_tokens,
      total_tokens: if(is_integer(total_tokens), do: total_tokens, else: input_tokens + output_tokens)
    }
  end

  defp normalize_google_usage(_), do: nil

  # Normalizes Anthropic usage format
  @spec normalize_anthropic_usage(map()) :: normalized_usage() | nil
  defp normalize_anthropic_usage(%{"input_tokens" => input_tokens, "output_tokens" => output_tokens})
       when is_integer(input_tokens) and is_integer(output_tokens) do
    %{
      input_tokens: input_tokens,
      output_tokens: output_tokens,
      total_tokens: input_tokens + output_tokens
    }
  end

  defp normalize_anthropic_usage(_), do: nil
end
