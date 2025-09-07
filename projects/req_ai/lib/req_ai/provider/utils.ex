defmodule ReqAI.Provider.Utils do
  @moduledoc """
  Shared utilities for provider implementations.

  Contains common functions used across multiple providers to eliminate
  duplication and ensure consistency.

  ## Examples

      iex> ReqAI.Provider.Utils.normalize_messages("Hello world")
      [%{role: "user", content: "Hello world"}]

      iex> messages = [%{role: "user", content: "Hi"}]
      iex> ReqAI.Provider.Utils.normalize_messages(messages)
      [%{role: "user", content: "Hi"}]

      iex> spec = %{default_model: "gpt-4", models: %{"gpt-3.5" => %{}, "gpt-4" => %{}}}
      iex> ReqAI.Provider.Utils.default_model(spec)
      "gpt-4"

      iex> spec = %{default_model: nil, models: %{"claude-3-haiku" => %{}, "claude-3-opus" => %{}}}
      iex> ReqAI.Provider.Utils.default_model(spec)
      "claude-3-haiku"
  """

  @doc """
  Normalizes various prompt formats into a standardized messages list.

  ## Parameters

  - `prompt` - Can be a string, list of messages, or any other type that can be converted to string

  ## Returns

  A list of message maps with `:role` and `:content` keys.

  ## Examples

      iex> ReqAI.Provider.Utils.normalize_messages("What is the weather?")
      [%{role: "user", content: "What is the weather?"}]

      iex> messages = [%{role: "user", content: "Hello"}, %{role: "assistant", content: "Hi there!"}]
      iex> ReqAI.Provider.Utils.normalize_messages(messages)
      [%{role: "user", content: "Hello"}, %{role: "assistant", content: "Hi there!"}]

      iex> ReqAI.Provider.Utils.normalize_messages(123)
      [%{role: "user", content: "123"}]
  """
  @spec normalize_messages(binary() | list() | term()) :: [map()]
  def normalize_messages(prompt) when is_binary(prompt) do
    [%{role: "user", content: prompt}]
  end

  def normalize_messages(messages) when is_list(messages) do
    messages
  end

  def normalize_messages(prompt) do
    [%{role: "user", content: to_string(prompt)}]
  end

  @doc """
  Gets the default model for a provider spec.

  Falls back to the first available model if no default is specified.

  ## Parameters

  - `spec` - Provider spec struct with `:default_model` and `:models` fields

  ## Returns

  The default model string, or `nil` if no models are available.

  ## Examples

      iex> spec = %{default_model: "gpt-4", models: %{"gpt-3.5" => %{}, "gpt-4" => %{}}}
      iex> ReqAI.Provider.Utils.default_model(spec)
      "gpt-4"

      iex> spec = %{default_model: nil, models: %{"model-a" => %{}, "model-b" => %{}}}
      iex> ReqAI.Provider.Utils.default_model(spec)
      "model-a"

      iex> spec = %{default_model: nil, models: %{}}
      iex> ReqAI.Provider.Utils.default_model(spec)
      nil
  """
  @spec default_model(map()) :: binary() | nil
  def default_model(spec) do
    spec.default_model ||
      case Map.keys(spec.models) do
        [first_model | _] -> first_model
        [] -> nil
      end
  end

  @doc """
  Creates standard HTTP headers for JSON API requests.

  ## Parameters

  - `extra_headers` - Optional list of additional header tuples to include

  ## Returns

  A list of header tuples with content-type set to application/json.

  ## Examples

      iex> ReqAI.Provider.Utils.json_headers()
      [{"content-type", "application/json"}]

      iex> ReqAI.Provider.Utils.json_headers([{"authorization", "Bearer token"}])
      [{"content-type", "application/json"}, {"authorization", "Bearer token"}]
  """
  @spec json_headers(list()) :: list()
  def json_headers(extra_headers \\ []) do
    [{"content-type", "application/json"}] ++ extra_headers
  end

  @doc """
  Parses error responses into ReqAI.Error.API.Response exceptions.

  Handles both structured error responses with message fields and fallback
  to HTTP status codes.

  ## Parameters

  - `status` - HTTP status code
  - `body` - Response body (map or other)

  ## Returns

  A `ReqAI.Error.API.Response` exception struct.

  ## Examples

      iex> body = %{"error" => %{"message" => "Invalid API key"}}
      iex> error = ReqAI.Provider.Utils.parse_error_response(401, body)
      iex> error.reason
      "Invalid API key"

      iex> error = ReqAI.Provider.Utils.parse_error_response(500, %{})
      iex> error.reason
      "HTTP 500"
  """
  @spec parse_error_response(integer(), any()) :: ReqAI.Error.API.Response.t()
  def parse_error_response(status, body) do
    error_message =
      case body do
        %{"error" => %{"message" => message}} -> message
        _ -> "HTTP #{status}"
      end

    ReqAI.Error.API.Response.exception(reason: error_message, status: status)
  end

  @doc """
  Parses Server-Sent Event chunks for streaming responses.

  Common logic for parsing SSE format used by both OpenAI and Anthropic.

  ## Parameters

  - `body` - Raw SSE response body
  - `filter_event` - Event type to filter for (e.g., "data", "message")
  - `extract_fn` - Function to extract content from parsed data

  ## Returns

  `{:ok, combined_content}` or `{:error, reason}`.

  ## Examples

      iex> body = "event: data\\ndata: {\\"choices\\": [{\\"delta\\": {\\"content\\": \\"Hello\\"}}]}\\n\\n"
      iex> extract_fn = fn data -> get_in(data, ["choices", Access.at(0), "delta", "content"]) end
      iex> ReqAI.Provider.Utils.parse_sse_stream(body, "data", extract_fn)
      {:ok, "Hello"}
  """
  @spec parse_sse_stream(binary(), binary() | nil, function()) ::
          {:ok, binary()} | {:error, ReqAI.Error.API.Response.t()}
  def parse_sse_stream(body, filter_event, extract_fn) do
    case ServerSentEvent.parse_all(body) do
      {:ok, {events, _rest}} ->
        if Enum.empty?(events) do
          {:error,
           ReqAI.Error.API.Response.exception(reason: "No events found in streaming response")}
        else
          content_parts =
            events
            |> Enum.filter(&(&1.type == nil or &1.type == filter_event))
            |> Enum.flat_map(& &1.lines)
            |> Enum.reject(&(&1 in [nil, "", "[DONE]"]))
            |> Enum.map(&Jason.decode/1)
            |> Enum.filter(&match?({:ok, _}, &1))
            |> Enum.map(fn {:ok, data} -> data end)
            |> Enum.map(extract_fn)
            |> Enum.filter(&is_binary/1)

          case content_parts do
            [] ->
              {:error,
               ReqAI.Error.API.Response.exception(
                 reason: "No content found in streaming response"
               )}

            parts ->
              {:ok, Enum.join(parts, "")}
          end
        end

      {:error, reason} ->
        {:error,
         ReqAI.Error.API.Response.exception(reason: "SSE parse error: #{inspect(reason)}")}
    end
  end

  @doc """
  Safely parses JSON chunks from streaming data.

  Handles malformed JSON and filters out empty or control chunks.

  ## Parameters

  - `raw_chunk` - Raw streaming chunk data

  ## Returns

  `{:ok, [parsed_data]}` or `{:error, reason}`.

  ## Examples

      iex> chunk = "data: {\\"test\\": \\"value\\"}\\n\\n"
      iex> ReqAI.Provider.Utils.parse_json_chunks(chunk)
      {:ok, [%{"test" => "value"}]}
  """
  @spec parse_json_chunks(iodata()) :: {:ok, [map()]} | {:error, ReqAI.Error.API.Response.t()}
  def parse_json_chunks(raw_chunk) do
    lines =
      raw_chunk
      |> IO.iodata_to_binary()
      |> String.split("\n")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    parsed_chunks =
      lines
      |> Enum.filter(&String.starts_with?(&1, "data:"))
      |> Enum.map(&String.slice(&1, 5..-1//1))
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 in ["", "[DONE]"]))
      |> Enum.map(&Jason.decode/1)

    case Enum.find(parsed_chunks, &match?({:error, _}, &1)) do
      {:error, reason} ->
        {:error,
         ReqAI.Error.API.Response.exception(reason: "JSON decode error: #{inspect(reason)}")}

      nil ->
        valid_chunks = Enum.map(parsed_chunks, fn {:ok, data} -> data end)
        {:ok, valid_chunks}
    end
  end
end
