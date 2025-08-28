defmodule Jido.AI.Middleware.Transport do
  @moduledoc """
  HTTP transport middleware for AI provider requests.

  This middleware handles the actual HTTP communication with AI provider APIs,
  including request execution, response processing, token counting, cost calculation,
  and error handling.

  ## Behavior

  During the request phase:
  - Validates required options (API key, URL)
  - Counts request tokens for cost calculation
  - Configures HTTP client options

  During the response phase:
  - Executes the HTTP request to the AI provider
  - Processes successful responses with usage and cost data
  - Handles errors and converts them to structured error types
  - Attaches metadata including usage, cost, and model information

  ## Context Updates

  The middleware updates the context with:
  - Response data in the body field
  - Usage metadata from the API response
  - Cost calculations based on actual or estimated token usage
  - Enhanced error information on failures

  ## Configuration

  Uses the following configuration keys:
  - `[:http_client]` - HTTP client module (default: `Req`)
  - `[:http_options]` - Additional HTTP options (default: `[]`)
  - `[:receive_timeout]` - Request receive timeout (default: `60_000`)
  - `[:pool_timeout]` - Connection pool timeout (default: `30_000`)

  ## Examples

      context = Context.new(:request, model, request_body, [
        api_key: "sk-...",
        url: "https://api.openai.com/v1/chat/completions"
      ])
      
      # This middleware processes both phases
      result_context = Transport.call(context, &identity_next/1)
  """

  @behaviour Jido.AI.Middleware

  alias Jido.AI.Error.API
  alias Jido.AI.Middleware
  alias Jido.AI.Middleware.Context
  alias Jido.AI.Provider.Util.Validation
  alias Jido.AI.{CostCalculator, TokenCounter}

  require Logger

  @doc """
  Processes HTTP transport for AI provider requests.

  During the request phase, validates options and prepares for HTTP execution.
  During the response phase, executes the HTTP request and processes the response.

  ## Parameters

    * `context` - The middleware context containing request data and options
    * `next` - Function to call the next middleware in the pipeline

  ## Returns

  The context with response data, metadata, or error information attached.
  """
  @impl Middleware
  @spec call(Context.t(), (Context.t() -> Context.t())) :: Context.t()
  def call(%Context{phase: :request} = context, next) do
    # Validate required options and count tokens during request phase
    with {:ok, _api_key} <- Validation.get_required_opt(context.opts, :api_key),
         {:ok, _url} <- Validation.get_required_opt(context.opts, :url) do
      # Count request tokens and add to metadata
      request_tokens = TokenCounter.count_request_tokens(context.body)
      Logger.debug("🔢 Request tokens: #{request_tokens}")

      # Add token count to context and continue to next middleware
      context = Context.put_meta(context, :request_tokens, request_tokens)

      # Call next middleware (which will eventually switch to response phase)
      context = next.(context)

      # Now we're in the response phase - handle the HTTP request if no errors
      case {context.phase, Context.get_meta(context, :error)} do
        {:response, nil} ->
          # Execute HTTP request in response phase
          execute_http_request(context)

        _ ->
          # Pass through - either still in request phase or has error
          context
      end
    else
      {:error, reason} ->
        # Validation failed - create error and switch to response phase
        error =
          API.Request.exception(
            reason: "Missing required option: #{inspect(reason)}",
            request_body: sanitize_request_body(context.body)
          )

        context
        |> Context.put_phase(:response)
        |> Context.put_meta(:error, error)
    end
  end

  def call(%Context{phase: :response} = context, next) do
    # Check if there's already an error from validation
    case Context.get_meta(context, :error) do
      nil ->
        # Proceed with HTTP request
        context = execute_http_request(context)
        next.(context)

      _error ->
        # Pass through existing error
        next.(context)
    end
  end

  @doc """
  Executes the HTTP request and processes the response.

  This function handles the core HTTP communication, including:
  - HTTP client configuration
  - Request execution with proper authentication and timeouts
  - Response processing with token counting and cost calculation
  - Error handling and conversion to structured error types

  ## Parameters

    * `context` - The middleware context in response phase

  ## Returns

  The updated context with response data, metadata, or error information.
  """
  @spec execute_http_request(Context.t()) :: Context.t()
  def execute_http_request(%Context{} = context) do
    {:ok, api_key} = Validation.get_required_opt(context.opts, :api_key)
    {:ok, url} = Validation.get_required_opt(context.opts, :url)

    http_client = Jido.AI.config([:http_client], Req)
    http_options = Jido.AI.config([:http_options], [])

    recv_to = Keyword.get(context.opts, :receive_timeout, Jido.AI.config([:receive_timeout], 60_000))
    pool_to = Keyword.get(context.opts, :pool_timeout, Jido.AI.config([:pool_timeout], 30_000))

    request_options =
      [
        json: context.body,
        auth: {:bearer, api_key},
        receive_timeout: recv_to,
        pool_timeout: pool_to
      ] ++ http_options

    case http_client.post(url, request_options) do
      {:ok, response} ->
        # Check if the response has an HTTP error status
        if response.status >= 400 do
          error = build_enhanced_api_error(response, context.body)
          Context.put_meta(context, :error, error)
        else
          process_successful_response(context, response)
        end

      {:error, reason} ->
        error = build_enhanced_api_error(reason, context.body)
        Context.put_meta(context, :error, error)
    end
  end

  @doc """
  Processes a successful HTTP response.

  Extracts usage data, calculates costs, and attaches enhanced metadata to the response.

  ## Parameters

    * `context` - The middleware context
    * `response` - The successful HTTP response

  ## Returns

  The updated context with processed response data and metadata.
  """
  @spec process_successful_response(Context.t(), map()) :: Context.t()
  def process_successful_response(%Context{} = context, response) do
    # Extract usage data from response if available (only for map bodies)
    usage =
      case response.body do
        body when is_map(body) -> Map.get(body, "usage")
        _ -> nil
      end

    request_tokens = Context.get_meta(context, :request_tokens, 0)

    # Calculate cost using actual usage data when available, fallback to estimation
    cost =
      case usage do
        nil ->
          # Fallback to estimation for providers that don't return usage
          response_tokens = TokenCounter.count_response_tokens(response.body)
          Logger.debug("🔢 Response tokens (estimated): #{response_tokens}")
          Logger.debug("🔢 Total tokens (estimated): #{request_tokens + response_tokens}")
          CostCalculator.calculate_request_cost(context.model, context.body, response.body)

        usage_data ->
          # Use actual usage data from API response
          input_tokens = Map.get(usage_data, "prompt_tokens", request_tokens)
          output_tokens = Map.get(usage_data, "completion_tokens", 0)
          Logger.debug("🔢 Request tokens (actual): #{input_tokens}")
          Logger.debug("🔢 Response tokens (actual): #{output_tokens}")
          Logger.debug("🔢 Total tokens (actual): #{input_tokens + output_tokens}")
          CostCalculator.calculate_cost_from_usage(context.model, usage_data)
      end

    # Log cost information
    case cost do
      nil ->
        Logger.debug("💰 Cost: unavailable (no pricing data)")

      cost_breakdown ->
        Logger.debug("💰 Cost: #{CostCalculator.format_cost(cost_breakdown)}")
    end

    # Attach metadata to response for downstream consumers
    enhanced_response =
      Map.put(response, :jido_meta, %{
        usage: usage,
        cost: cost,
        model: context.model
      })

    context
    |> Context.put_body(enhanced_response)
    |> Context.put_meta(:usage, usage)
    |> Context.put_meta(:cost, cost)
    |> Context.put_meta(:enhanced_response, enhanced_response)
  end

  @doc """
  Builds enhanced API error structures with detailed context.

  Converts various error types into structured `Jido.AI.Error.API.Request` exceptions
  with appropriate error messages, status codes, and sanitized request context.

  ## Parameters

    * `reason` - The error reason from the HTTP client
    * `request_body` - The original request body for context (will be sanitized)

  ## Returns

  A structured `Jido.AI.Error.API.Request` exception with enhanced error information.
  """
  @spec build_enhanced_api_error(any(), map()) :: Exception.t()
  def build_enhanced_api_error(reason, request_body) do
    case reason do
      %Req.Response{status: status, body: body} when status >= 400 ->
        API.Request.exception(
          reason: format_http_error(status, body),
          status: status,
          response_body: body,
          request_body: sanitize_request_body(request_body)
        )

      %{response: %{status: status, body: body}} when status >= 400 ->
        API.Request.exception(
          reason: format_http_error(status, body),
          status: status,
          response_body: body,
          request_body: sanitize_request_body(request_body)
        )

      %{__exception__: true} = exception ->
        API.Request.exception(
          reason: "Network error: #{Exception.message(exception)}",
          cause: exception,
          request_body: sanitize_request_body(request_body)
        )

      other ->
        API.Request.exception(
          reason: "Request failed: #{inspect(other)}",
          cause: other,
          request_body: sanitize_request_body(request_body)
        )
    end
  end

  # Private helper to format HTTP error messages from response bodies
  @spec format_http_error(integer(), any()) :: String.t()
  defp format_http_error(status, body) when is_map(body) do
    case get_in(body, ["error", "message"]) do
      nil ->
        case get_in(body, ["error"]) do
          error_msg when is_binary(error_msg) -> error_msg
          _ -> "HTTP #{status}"
        end

      error_msg when is_binary(error_msg) ->
        error_type = get_in(body, ["error", "type"]) || "unknown"
        "#{error_msg} (#{error_type})"
    end
  end

  defp format_http_error(status, body) when is_binary(body) do
    "HTTP #{status}: #{String.slice(body, 0, 200)}"
  end

  defp format_http_error(status, _), do: "HTTP #{status}"

  # Private helper to sanitize request bodies for error reporting
  @spec sanitize_request_body(map()) :: map()
  defp sanitize_request_body(body) when is_map(body) do
    # Remove sensitive data but keep structure for debugging
    body
    |> Map.delete("api_key")
    |> Map.put("messages", "[REDACTED]")
  end

  defp sanitize_request_body(body), do: body
end
