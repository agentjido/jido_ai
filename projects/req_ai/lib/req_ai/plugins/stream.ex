defmodule ReqAI.Plugins.Stream do
  @moduledoc """
  Req plugin for handling Server-Sent Events (SSE).

  This plugin processes "text/event-stream" responses and converts them into
  enumerable chunks for streaming AI responses. Non-streaming responses are
  passed through unchanged.

  ## Usage

      iex> req = Req.new() |> ReqAI.Plugins.Stream.attach()

  The plugin automatically detects SSE responses by content type and processes
  them into structured chunks. Each chunk contains:

  - `event` - The event type (e.g., "delta", "done")
  - `data` - The event data (JSON parsed if valid)
  - `id` - Event ID (if present)
  - `retry` - Retry interval (if present)

  ## Examples

      # Streaming response
      response = Req.get!(req, url: "https://api.example.com/stream")
      response.body
      #=> %Stream{} containing parsed SSE chunks

      # Non-streaming response
      response = Req.get!(req, url: "https://api.example.com/chat")
      response.body
      #=> "Regular JSON response"

  """

  @doc """
  Attaches the SSE streaming plugin to a Req request struct.

  ## Parameters
    - `req` - The Req request struct

  ## Returns
    - Updated Req request struct with the plugin attached

  """
  @spec attach(Req.Request.t()) :: Req.Request.t()
  def attach(req) do
    Req.Request.append_response_steps(req, stream_sse: &process_sse_response/1)
  end

  @doc false
  @spec process_sse_response(Req.Response.t()) :: Req.Response.t()
  def process_sse_response(response) do
    content_type = Req.Response.get_header(response, "content-type") |> List.first()

    if content_type && String.contains?(content_type, "text/event-stream") do
      stream = parse_sse_stream(response.body)
      %{response | body: stream}
    else
      response
    end
  end

  @spec parse_sse_stream(binary() | Stream.t()) :: Stream.t()
  defp parse_sse_stream(body) when is_binary(body) do
    body
    |> String.split("\n\n")
    |> Stream.map(&parse_sse_chunk/1)
    |> Stream.reject(&is_nil/1)
  end

  defp parse_sse_stream(stream) when is_struct(stream, Stream) do
    stream
    |> Stream.transform("", &accumulate_chunks/2)
    |> Stream.map(&parse_sse_chunk/1)
    |> Stream.reject(&is_nil/1)
  end

  @spec accumulate_chunks(binary(), binary()) :: {[binary()], binary()}
  defp accumulate_chunks(chunk, buffer) do
    combined = buffer <> chunk
    parts = String.split(combined, "\n\n")

    case parts do
      [single] ->
        {[], single}

      [_ | _] ->
        {complete_chunks, incomplete} = Enum.split(parts, -1)
        {complete_chunks, List.last(incomplete) || ""}
    end
  end

  @spec parse_sse_chunk(binary()) :: map() | nil
  defp parse_sse_chunk(""), do: nil

  defp parse_sse_chunk(chunk) when is_binary(chunk) do
    chunk
    |> String.trim()
    |> String.split("\n")
    |> Enum.reduce(%{}, &parse_sse_line/2)
    |> case do
      %{data: _} = parsed -> parsed
      _ -> nil
    end
  end

  @spec parse_sse_line(binary(), map()) :: map()
  defp parse_sse_line(line, acc) do
    case String.split(line, ":", parts: 2) do
      [field, value] ->
        field = String.trim(field)
        value = String.trim(value)

        case field do
          "data" ->
            parsed_data = try_parse_json(value)
            Map.put(acc, :data, parsed_data)

          "event" ->
            Map.put(acc, :event, value)

          "id" ->
            Map.put(acc, :id, value)

          "retry" ->
            case Integer.parse(value) do
              {int_value, _} -> Map.put(acc, :retry, int_value)
              _ -> acc
            end

          _ ->
            acc
        end

      [field] ->
        field = String.trim(field)

        if field == "data" do
          Map.put(acc, :data, "")
        else
          acc
        end

      _ ->
        acc
    end
  end

  @spec try_parse_json(binary()) :: map() | binary()
  defp try_parse_json(value) do
    case Jason.decode(value) do
      {:ok, decoded} -> decoded
      {:error, _} -> value
    end
  end
end
