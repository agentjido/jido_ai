defmodule ReqLLM.Plugins.Stream do
  @moduledoc """
  Req plugin for handling Server-Sent Events (SSE).

  This plugin processes "text/event-stream" responses and converts them into
  enumerable chunks for streaming AI responses. Non-streaming responses are
  passed through unchanged.

  ## Usage

      iex> req = Req.new() |> ReqLLM.Plugins.Stream.attach()

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
  @spec process_sse_response({Req.Request.t(), Req.Response.t()}) ::
          {Req.Request.t(), Req.Response.t()}
  def process_sse_response({req, resp} = pair) do
    content_type =
      case Req.Response.get_header(resp, "content-type") do
        [ct | _] -> ct
        ct when is_binary(ct) -> ct
        _ -> nil
      end

    if content_type && String.contains?(content_type, "text/event-stream") do
      stream = parse_sse_stream(resp.body)
      {req, %{resp | body: stream}}
    else
      pair
    end
  end

  @spec parse_sse_stream(binary() | Enumerable.t()) :: Enumerable.t()
  defp parse_sse_stream(body) when is_binary(body) do
    {events, _remaining} = ServerSentEvents.parse(body)

    events
    |> Stream.map(&process_sse_event/1)
    |> Stream.reject(&is_nil/1)
  end

  defp parse_sse_stream(stream) when is_struct(stream, Stream) do
    stream
    |> Stream.transform("", &accumulate_and_parse/2)
    |> Stream.flat_map(& &1)
    |> Stream.map(&process_sse_event/1)
    |> Stream.reject(&is_nil/1)
  end

  @spec accumulate_and_parse(binary(), binary()) :: {[map()], binary()}
  defp accumulate_and_parse(chunk, buffer) do
    combined = buffer <> chunk
    {events, remaining} = ServerSentEvents.parse(combined)
    {events, remaining}
  end

  @spec process_sse_event(map()) :: map() | nil
  defp process_sse_event(%{data: data} = event) when is_binary(data) do
    case try_parse_json(data) do
      parsed when is_map(parsed) ->
        %{event | data: parsed}

      _ ->
        event
    end
  end

  defp process_sse_event(event), do: event

  @spec try_parse_json(binary()) :: map() | binary()
  defp try_parse_json(value) do
    case Jason.decode(value) do
      {:ok, decoded} -> decoded
      {:error, _} -> value
    end
  end
end
