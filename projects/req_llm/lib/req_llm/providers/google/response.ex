defmodule ReqLLM.Providers.Google.Response do
  @moduledoc false
  defstruct [:payload]
  @type t :: %__MODULE__{payload: term()}
end

# Protocol implementation for Google-specific response decoding
defimpl ReqLLM.Response.Codec, for: ReqLLM.Providers.Google.Response do
  alias ReqLLM.{Response, Context, Message, StreamChunk, Model}

  @doc """
  Decode wrapped Google response struct.

  This handles tagged wrapper structs created by wrap_response.
  """
  def decode_response(%{payload: _data} = _wrapped_response) do
    # Wrapped responses without model should use decode_response/2 instead
    {:error, :not_implemented}
  end

  @doc """
  Decode wrapped Google response struct with model information.
  """
  def decode_response(
        %{payload: stream} = _wrapped_response,
        %Model{provider: :google} = model
      )
      when is_struct(stream, Stream) do
    # Convert SSE events to StreamChunks
    chunk_stream =
      stream
      |> Stream.flat_map(&decode_sse_event/1)
      |> Stream.reject(&is_nil/1)

    response = %Response{
      id: "stream-#{System.unique_integer([:positive])}",
      model: model.model || "unknown",
      context: %Context{messages: []},
      message: nil,
      stream?: true,
      stream: chunk_stream,
      usage: %{input_tokens: 0, output_tokens: 0, total_tokens: 0},
      finish_reason: nil,
      provider_meta: %{}
    }

    {:ok, response}
  end

  def decode_response(%{payload: data} = _wrapped_response, %Model{provider: :google} = model)
      when is_map(data) do
    try do
      result =
        ReqLLM.Providers.Google.ResponseDecoder.decode_google_json(
          data,
          model.model || "unknown"
        )

      result
    rescue
      error ->
        {:error, error}
    catch
      {:decode_error, reason} ->
        {:error, %ReqLLM.Error.API.Response{reason: reason}}
    end
  end

  def decode_response(_wrapped_response, _model) do
    {:error, :unsupported_provider}
  end

  def encode_request(_), do: {:error, :not_implemented}

  # SSE Event decoding for streaming responses
  defp decode_sse_event(%{data: %{"candidates" => [%{"content" => %{"parts" => parts}} | _]}}) do
    parts
    |> Enum.flat_map(&decode_google_part/1)
    |> Enum.reject(&is_nil/1)
  end

  defp decode_sse_event(_event), do: []

  defp decode_google_part(%{"text" => text}) when is_binary(text) and text != "" do
    [StreamChunk.text(text)]
  end

  defp decode_google_part(%{"functionCall" => %{"name" => name, "args" => args}}) do
    [StreamChunk.tool_call(name, args)]
  end

  defp decode_google_part(_), do: []
end

# Note: Map protocol implementation is handled in anthropic/response.ex to avoid conflicts

defmodule ReqLLM.Providers.Google.ResponseDecoder do
  @moduledoc false
  alias ReqLLM.{Response, Context, Message, StreamChunk, Model}

  # Shared implementation for decoding Google JSON
  def decode_google_json(data, model) when is_map(data) do
    # Extract basic response information
    candidates = Map.get(data, "candidates", [])
    usage = parse_usage(Map.get(data, "usageMetadata"))

    # Google doesn't provide a response ID, so we'll generate one or use a default
    id = Map.get(data, "id", "google-response-#{:erlang.system_time(:microsecond)}")

    # Extract content from the first candidate
    {content_chunks, finish_reason} =
      case candidates do
        [first_candidate | _] ->
          chunks = extract_content_from_candidate(first_candidate)
          finish_reason = parse_finish_reason(Map.get(first_candidate, "finishReason"))
          {chunks, finish_reason}

        [] ->
          {[], nil}
      end

    # Build assistant message from content chunks
    message = build_message_from_chunks(content_chunks)

    # Create a minimal context with just the assistant message
    # In practice, this would be appended to the original context by the caller
    context = %Context{
      messages: if(message, do: [message], else: [])
    }

    response = %Response{
      id: id,
      model: model,
      context: context,
      message: message,
      stream?: false,
      stream: nil,
      usage: usage,
      finish_reason: finish_reason,
      provider_meta: Map.drop(data, ["candidates", "usageMetadata"])
    }

    {:ok, response}
  end

  def build_message_from_chunks(chunks) when is_list(chunks) do
    case chunks do
      [] ->
        nil

      _ ->
        # Convert StreamChunks to Message.ContentPart structs
        content_parts =
          chunks
          |> Enum.map(&chunk_to_content_part/1)
          |> Enum.reject(&is_nil/1)

        if content_parts != [] do
          message = %Message{
            role: :assistant,
            content: content_parts,
            metadata: %{}
          }

          message
        else
          nil
        end
    end
  end

  def chunk_to_content_part(%StreamChunk{type: :content, text: text}) do
    %ReqLLM.Message.ContentPart{type: :text, text: text}
  end

  def chunk_to_content_part(%StreamChunk{
        type: :tool_call,
        name: name,
        arguments: args,
        metadata: meta
      }) do
    %ReqLLM.Message.ContentPart{
      type: :tool_call,
      tool_name: name,
      input: args,
      tool_call_id: Map.get(meta, :id)
    }
  end

  def chunk_to_content_part(_), do: nil

  def parse_usage(
        %{"promptTokenCount" => prompt, "candidatesTokenCount" => candidates} = usage_map
      ) do
    total = prompt + candidates

    %{
      input_tokens: prompt,
      output_tokens: candidates,
      total_tokens: total,
      # Preserve additional usage metadata from Google
      cached_content_token_count: Map.get(usage_map, "cachedContentTokenCount", 0),
      total_token_count: Map.get(usage_map, "totalTokenCount", total)
    }
  end

  def parse_usage(_), do: %{input_tokens: 0, output_tokens: 0, total_tokens: 0}

  def parse_finish_reason("STOP"), do: :stop
  def parse_finish_reason("MAX_TOKENS"), do: :length
  def parse_finish_reason("SAFETY"), do: :content_filter
  def parse_finish_reason("RECITATION"), do: :content_filter
  def parse_finish_reason("OTHER"), do: :other
  def parse_finish_reason(reason) when is_binary(reason), do: reason
  def parse_finish_reason(_), do: nil

  # Helper functions for content extraction
  defp extract_content_from_candidate(%{"content" => %{"parts" => parts}}) when is_list(parts) do
    parts
    |> Enum.map(&decode_content_part/1)
    |> List.flatten()
    |> Enum.reject(&is_nil/1)
  end

  defp extract_content_from_candidate(%{content: %{parts: parts}}) when is_list(parts) do
    parts
    |> Enum.map(&decode_content_part/1)
    |> List.flatten()
    |> Enum.reject(&is_nil/1)
  end

  defp extract_content_from_candidate(_), do: []

  defp decode_content_part(%{"text" => text}) when is_binary(text) do
    [ReqLLM.StreamChunk.text(text)]
  end

  defp decode_content_part(%{text: text}) when is_binary(text) do
    [ReqLLM.StreamChunk.text(text)]
  end

  # defp decode_content_part(%{"function_call" => %{"name" => name, "args" => args}}) do
  #   [ReqLLM.StreamChunk.tool_call(name, args, %{})]
  # end

  # Google returns camel-case keys in JSON responses
  defp decode_content_part(%{"functionCall" => %{"name" => name, "args" => args}}) do
    [ReqLLM.StreamChunk.tool_call(name, args, %{})]
  end

  defp decode_content_part(%{function_call: %{name: name, args: args}}) do
    [ReqLLM.StreamChunk.tool_call(name, args, %{})]
  end

  defp decode_content_part(_unknown), do: []
end
