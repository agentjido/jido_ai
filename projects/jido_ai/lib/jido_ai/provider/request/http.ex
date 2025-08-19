defmodule Jido.AI.Provider.Request.HTTP do
  @moduledoc """
  HTTP request utilities for AI providers.
  """

  alias Jido.AI.Error.API
  alias Jido.AI.Provider.Util.Validation
  alias Jido.AI.{CostCalculator, Model, TokenCounter}

  require Logger

  @doc """
  Performs HTTP request for text generation.
  """
  @spec do_http_request(module(), Model.t(), map(), keyword()) :: {:ok, struct()} | {:error, struct()}
  def do_http_request(_provider_module, %Model{} = model, request_body, opts) do
    with {:ok, api_key} <- Validation.get_required_opt(opts, :api_key),
         {:ok, url} <- Validation.get_required_opt(opts, :url) do
      # Count request tokens for cost calculation
      request_tokens = TokenCounter.count_request_tokens(request_body)
      Logger.debug("🔢 Request tokens: #{request_tokens}")

      http_client = Jido.AI.config([:http_client], Req)
      http_options = Jido.AI.config([:http_options], [])

      recv_to =
        Keyword.get(opts, :receive_timeout, Jido.AI.config([:receive_timeout], 60_000))

      pool_to = Keyword.get(opts, :pool_timeout, Jido.AI.config([:pool_timeout], 30_000))

      request_options =
        [
          json: request_body,
          auth: {:bearer, api_key},
          receive_timeout: recv_to,
          pool_timeout: pool_to
        ] ++ http_options

      case http_client.post(url, request_options) do
        {:ok, response} ->
          # Extract usage data from response if available (only for map bodies)
          usage =
            case response.body do
              body when is_map(body) -> Map.get(body, "usage")
              _ -> nil
            end

          # Calculate cost using actual usage data when available, fallback to estimation
          cost =
            case usage do
              nil ->
                # Fallback to estimation for providers that don't return usage
                response_tokens = TokenCounter.count_response_tokens(response.body)
                Logger.debug("🔢 Response tokens (estimated): #{response_tokens}")
                Logger.debug("🔢 Total tokens (estimated): #{request_tokens + response_tokens}")
                CostCalculator.calculate_request_cost(model, request_body, response.body)

              usage_data ->
                # Use actual usage data from API response
                input_tokens = Map.get(usage_data, "prompt_tokens", request_tokens)
                output_tokens = Map.get(usage_data, "completion_tokens", 0)
                Logger.debug("🔢 Request tokens (actual): #{input_tokens}")
                Logger.debug("🔢 Response tokens (actual): #{output_tokens}")
                Logger.debug("🔢 Total tokens (actual): #{input_tokens + output_tokens}")
                CostCalculator.calculate_cost_from_usage(model, usage_data)
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
              model: model
            })

          {:ok, enhanced_response}

        {:error, reason} ->
          {:error, build_enhanced_api_error(reason, request_body)}
      end
    end
  end

  @doc """
  Performs streaming HTTP request for text generation.
  """
  @spec do_stream_request(module(), Model.t(), map(), keyword()) ::
          {:ok, Enumerable.t()} | {:error, struct()}
  def do_stream_request(_provider_module, %Model{} = model, request_body, opts) do
    with {:ok, api_key} <- Validation.get_required_opt(opts, :api_key),
         {:ok, url} <- Validation.get_required_opt(opts, :url) do
      # Count request tokens for streaming
      request_tokens = TokenCounter.count_request_tokens(request_body)
      Logger.debug("🔢 Stream request tokens: #{request_tokens}")

      # Create a stream wrapper that tracks total response tokens and calculates cost
      base_stream =
        Stream.resource(
          fn ->
            pid = self()

            Task.async(fn ->
              http_client = Jido.AI.config([:http_client], Req)

              recv_to =
                Keyword.get(opts, :receive_timeout, Jido.AI.config([:receive_timeout], 60_000))

              pool_to = Keyword.get(opts, :pool_timeout, Jido.AI.config([:pool_timeout], 30_000))

              try do
                http_options = Jido.AI.config([:http_options], [])

                stream_options =
                  [
                    json: request_body,
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
                opts,
                :stream_inactivity_timeout,
                Jido.AI.config([:stream_inactivity_timeout], 15_000)
              )

            receive do
              :done ->
                {:halt, task}

              {:error, error} ->
                throw({:error, API.Request.exception(reason: inspect(error))})

              {:events, events} ->
                {Jido.AI.Provider.Response.Stream.parse_events(events, model), task}
            after
              inactivity_to -> {:halt, task}
            end
          end,
          fn task ->
            Task.await(task, 15_000)
          end
        )

      # For now, return the base stream directly
      # Cost calculation will be handled in the playground LiveView
      {:ok, base_stream}
    end
  end

  # Enhanced error handling with API response details
  defp build_enhanced_api_error(reason, request_body) do
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

  defp sanitize_request_body(body) when is_map(body) do
    # Remove sensitive data but keep structure for debugging
    body
    |> Map.delete("api_key")
    |> Map.put("messages", "[REDACTED]")
  end
end
