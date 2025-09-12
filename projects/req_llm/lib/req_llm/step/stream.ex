defmodule ReqLLM.Step.Stream do
  @moduledoc """
  Req step for handling Server-Sent Events (SSE).

  This step processes "text/event-stream" responses and converts them into
  enumerable chunks for streaming AI responses. Non-streaming responses are
  passed through unchanged.

  ## Usage

      request
      |> ReqLLM.Step.Stream.attach()

  The step automatically detects SSE responses by content type and processes
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
  Attaches the SSE streaming step to a Req request struct.

  ## Parameters
    - `req` - The Req request struct

  ## Returns
    - Updated Req request struct with the step attached

  """
  @spec attach(Req.Request.t()) :: Req.Request.t()
  def attach(req) do
    Req.Request.append_response_steps(req, stream_sse: &__MODULE__.handle/1)
  end

  @doc """
  Conditionally attaches the SSE streaming step to a Req request struct.

  ## Parameters
    - `req` - The Req request struct
    - `stream_enabled` - Whether streaming is enabled

  ## Returns
    - Updated Req request struct with the step attached if streaming is enabled

  ## Examples

      # Streaming enabled - step attached
      request |> ReqLLM.Step.Stream.maybe_attach(true)

      # Streaming disabled - request unchanged
      request |> ReqLLM.Step.Stream.maybe_attach(false)

  """
  @spec maybe_attach(Req.Request.t(), boolean()) :: Req.Request.t()
  def maybe_attach(req, true), do: attach(req)
  def maybe_attach(req, _), do: req

  @doc false
  @spec handle({Req.Request.t(), Req.Response.t()}) ::
          {Req.Request.t(), Req.Response.t()}
  def handle({req, resp} = pair) do
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
