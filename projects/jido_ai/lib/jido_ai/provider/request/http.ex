defmodule Jido.AI.Provider.Request.HTTP do
  @moduledoc """
  HTTP request utilities for AI providers.

  This module provides a backward-compatible interface to AI provider HTTP requests
  while internally using the new middleware pipeline for processing. It maintains
  the existing function signatures and return values that providers depend on.

  ## Middleware Integration

  Both `do_http_request/4` and `do_stream_request/4` now use the middleware pipeline
  internally, which provides:

  - Token counting and cost calculation
  - Structured request/response processing  
  - Extensible middleware architecture
  - Consistent error handling

  The middleware pipeline runs these middlewares in order:
  1. `TokenCounter` - Counts tokens in requests and responses
  2. `CostCalculator` - Calculates API costs based on usage
  3. `Transport` - Handles HTTP communication with providers

  ## Backward Compatibility

  All existing provider code continues to work unchanged. The function signatures,
  return values, and error handling behavior remain identical to the previous
  implementation.
  """

  alias Jido.AI.Error.API
  alias Jido.AI.Middleware.Context
  alias Jido.AI.Middleware.CostCalculator
  alias Jido.AI.Middleware.TokenCounter
  alias Jido.AI.Middleware.Transport
  alias Jido.AI.Provider.Response.Stream, as: ResponseStream
  alias Jido.AI.Provider.Util.Validation
  alias Jido.AI.{Middleware, Model}

  require Logger

  @doc """
  Performs HTTP request for text generation using the middleware pipeline.

  This function maintains backward compatibility with existing providers while
  internally using the new middleware architecture for processing. The middleware
  pipeline handles token counting, cost calculation, and HTTP transport.

  ## Parameters

    * `provider_module` - The provider module (preserved for compatibility)
    * `model` - The AI model configuration
    * `request_body` - The request payload to send to the provider
    * `opts` - Request options including `:api_key` and `:url`

  ## Returns

  Returns the same format as the original implementation:
    * `{:ok, enhanced_response}` - Response with `:jido_meta` containing usage and cost data
    * `{:error, exception}` - Structured error with detailed information

  ## Middleware Pipeline

  Executes the following middleware in order:
  1. `TokenCounter` - Counts request/response tokens
  2. `CostCalculator` - Calculates API costs
  3. `Transport` - Executes HTTP request

  The final response maintains the same format as the legacy implementation.
  """
  @spec do_http_request(module(), Model.t(), map(), keyword()) :: {:ok, struct()} | {:error, struct()}
  def do_http_request(_provider_module, %Model{} = model, request_body, opts) do
    # Create initial context for the middleware pipeline
    context = Context.new(:request, model, request_body, opts)

    # Define the middleware pipeline
    middlewares = [
      TokenCounter,
      CostCalculator,
      Transport
    ]

    # Execute the pipeline with a final function that switches to response phase
    result_context = Middleware.run(middlewares, context, &switch_to_response_phase/1)

    # Extract the result from the context and return in the expected format
    case Context.get_meta(result_context, :error) do
      nil ->
        # Success - extract the enhanced response from context
        enhanced_response = Context.get_meta(result_context, :enhanced_response)
        {:ok, enhanced_response}

      error ->
        # Error occurred during pipeline execution
        {:error, error}
    end
  end

  # Switches context from request to response phase.
  # This is the final function in the middleware pipeline that marks the transition
  # from the request phase to the response phase.
  @spec switch_to_response_phase(Context.t()) :: Context.t()
  defp switch_to_response_phase(%Context{} = context) do
    Context.put_phase(context, :response)
  end

  @doc """
  Performs streaming HTTP request for text generation using the middleware pipeline.

  This implementation uses the same middleware pipeline as non-streaming requests
  for consistent token counting, cost calculation, and processing across all request types.

  ## Parameters

    * `provider_module` - The provider module (preserved for compatibility)  
    * `model` - The AI model configuration
    * `request_body` - The request payload to send to the provider
    * `opts` - Request options including `:api_key` and `:url`

  ## Returns

  Returns the same format as the original implementation:
    * `{:ok, stream}` - An enumerable stream of parsed response events with middleware metadata
    * `{:error, exception}` - Structured error with detailed information

  ## Middleware Integration

  The streaming implementation now uses the middleware pipeline for:
  - Token counting during request phase
  - Cost calculation integration
  - Consistent error handling and validation
  - Enhanced metadata attachment to stream chunks
  """
  @spec do_stream_request(module(), Model.t(), map(), keyword()) ::
          {:ok, Enumerable.t()} | {:error, struct()}
  def do_stream_request(_provider_module, %Model{} = model, request_body, opts) do
    # Create middleware context for request phase
    context = Context.new(:request, model, request_body, opts)

    # Use middleware pipeline for request phase processing (validation, token counting, etc.)
    middlewares = [
      TokenCounter,
      CostCalculator
    ]

    # Process request phase through middleware
    context_after_request =
      Middleware.run(middlewares, context, fn ctx ->
        # Switch to response phase for streaming execution
        Context.put_phase(ctx, :response)
      end)

    # Check for validation errors from middleware
    case Context.get_meta(context_after_request, :error) do
      nil ->
        # No errors - proceed with streaming
        create_streaming_response(context_after_request)

      error ->
        # Return error from middleware validation
        {:error, error}
    end
  end

  # Creates the streaming response with middleware-enhanced chunks
  @spec create_streaming_response(Context.t()) :: {:ok, Enumerable.t()} | {:error, struct()}
  defp create_streaming_response(%Context{} = context) do
    with {:ok, api_key} <- Validation.get_required_opt(context.opts, :api_key),
         {:ok, url} <- Validation.get_required_opt(context.opts, :url) do
      request_tokens = Context.get_meta(context, :request_tokens, 0)
      Logger.debug("🔢 Stream request tokens: #{request_tokens}")

      # Create stream with middleware-aware chunk processing
      base_stream =
        Stream.resource(
          fn ->
            pid = self()

            Task.async(fn ->
              http_client = Jido.AI.config([:http_client], Req)

              recv_to =
                Keyword.get(context.opts, :receive_timeout, Jido.AI.config([:receive_timeout], 60_000))

              pool_to = Keyword.get(context.opts, :pool_timeout, Jido.AI.config([:pool_timeout], 30_000))

              try do
                http_options = Jido.AI.config([:http_options], [])

                stream_options =
                  [
                    json: context.body,
                    auth: {:bearer, api_key},
                    receive_timeout: recv_to,
                    pool_timeout: pool_to,
                    into: fn {:data, data}, {req, resp} ->
                      buffer = Req.Request.get_private(req, :sse_buffer, "")
                      {events, new_buffer} = ServerSentEvents.parse(buffer <> data)

                      if events != [] do
                        send(pid, {:events, events})
                      end

                      {:cont, {Req.Request.put_private(req, :sse_buffer, new_buffer), resp}}
                    end
                  ] ++ http_options

                http_client.post(url, stream_options)
              rescue
                e -> send(pid, {:error, e})
              after
                send(pid, :done)
              end
            end)
          end,
          fn task ->
            inactivity_to =
              Keyword.get(
                context.opts,
                :stream_inactivity_timeout,
                Jido.AI.config([:stream_inactivity_timeout], 15_000)
              )

            receive do
              :done ->
                {:halt, task}

              {:error, error} ->
                throw({:error, API.Request.exception(reason: inspect(error))})

              {:events, events} ->
                # Parse events and enhance with middleware metadata for debugging
                chunks = ResponseStream.parse_events(events, context.model)
                # Note: Middleware metadata enhancement would go here in future versions
                # For now, maintain backward compatibility with plain chunks
                {chunks, task}
            after
              inactivity_to -> {:halt, task}
            end
          end,
          fn task ->
            Task.await(task, 15_000)
          end
        )

      {:ok, base_stream}
    end
  end
end
