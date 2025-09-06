defmodule ReqAI.Providers.Anthropic do
  @moduledoc """
  Anthropic provider adapter implementation using the Messages API.

  ## Usage

      ReqAI.Providers.Anthropic.generate_text("claude-3-haiku-20240307", "What is the capital of France?")
      ReqAI.Providers.Anthropic.stream_text("claude-3-opus-20240229", "Tell me a story", stream: true)

  ## Configuration

  Set your Anthropic API key:

      config :req_ai, ReqAI.Providers.Anthropic,
        api_key: "your-api-key"

  Or use environment variable:

      export ANTHROPIC_API_KEY="your-api-key"
  """

  use ReqAI.Provider.DSL,
    id: :anthropic,
    base_url: "https://api.anthropic.com",
    auth: {:header, "x-api-key", :plain},
    metadata: "anthropic.json",
    default_temperature: 1,
    default_max_tokens: 4096

  @impl true
  def build_request(input, provider_opts, request_opts) do
    spec = spec()
    prompt = input
    opts = Keyword.merge(provider_opts, request_opts)

    # Default to first available model from JSON, fallback to haiku
    default_model =
      case spec.models |> Map.keys() |> List.first() do
        nil -> "claude-3-haiku-20240307"
        first_model -> first_model
      end

    model = Keyword.get(opts, :model, spec.default_model || default_model)
    max_tokens = Keyword.get(opts, :max_tokens, spec.default_max_tokens)
    temperature = Keyword.get(opts, :temperature, spec.default_temperature)
    stream = Keyword.get(opts, :stream?, false)

    url = URI.merge(spec.base_url, "/v1/messages") |> URI.to_string()

    headers = [
      {"content-type", "application/json"},
      {"anthropic-version", "2023-06-01"}
    ]

    body = %{
      model: model,
      max_tokens: max_tokens,
      messages: normalize_messages(prompt),
      stream: stream
    }

    body = if temperature != nil, do: Map.put(body, :temperature, temperature), else: body

    request =
      Req.new(
        method: :post,
        url: url,
        headers: headers,
        json: body
      )

    {:ok, request}
  end

  @impl true
  def parse_response(response, provider_opts, request_opts) do
    opts = Keyword.merge(provider_opts, request_opts)
    stream = Keyword.get(opts, :stream?, false)

    case stream do
      true -> parse_streaming_response(response)
      false -> parse_non_streaming_response(response)
    end
  end

  # Private helper functions

  defp normalize_messages(prompt) when is_binary(prompt) do
    [%{role: "user", content: prompt}]
  end

  defp normalize_messages(messages) when is_list(messages) do
    messages
  end

  defp normalize_messages(prompt) do
    [%{role: "user", content: to_string(prompt)}]
  end

  defp parse_non_streaming_response(%{status: 200, body: body}) do
    case body do
      %{"content" => [%{"text" => text} | _]} when is_binary(text) ->
        {:ok, text}

      %{"error" => %{"message" => message}} ->
        {:error, ReqAI.Error.API.Response.exception(reason: message)}

      _ ->
        {:error, ReqAI.Error.API.Response.exception(reason: "Unexpected response format")}
    end
  end

  defp parse_non_streaming_response(%{status: status, body: body}) do
    error_message =
      case body do
        %{"error" => %{"message" => message}} -> message
        _ -> "HTTP #{status}"
      end

    {:error, ReqAI.Error.API.Response.exception(reason: error_message, status: status)}
  end

  defp parse_streaming_response(response) do
    case response do
      %{status: 200, body: body} when is_binary(body) ->
        parse_sse_chunks(body)

      %{status: status, body: body} ->
        error_message =
          case body do
            %{"error" => %{"message" => message}} -> message
            _ -> "HTTP #{status}"
          end

        {:error, ReqAI.Error.API.Response.exception(reason: error_message, status: status)}
    end
  end

  defp parse_sse_chunks(body) do
    case ServerSentEvent.parse_all(body) do
      {[], _rest} ->
        {:error,
         ReqAI.Error.API.Response.exception(reason: "No events found in streaming response")}

      {events, _rest} ->
        content_parts =
          events
          |> Enum.filter(&(&1.event == nil or &1.event == "message"))
          |> Enum.map(& &1.data)
          |> Enum.reject(&(&1 in [nil, "", "[DONE]"]))
          |> Enum.map(&Jason.decode/1)
          |> Enum.filter(&match?({:ok, _}, &1))
          |> Enum.map(fn {:ok, data} -> data end)
          |> Enum.filter(&(&1["type"] == "content_block_delta"))
          |> Enum.map(& &1["delta"]["text"])
          |> Enum.filter(&is_binary/1)

        case content_parts do
          [] ->
            {:error,
             ReqAI.Error.API.Response.exception(reason: "No content found in streaming response")}

          parts ->
            {:ok, Enum.join(parts, "")}
        end
    end
  end
end
