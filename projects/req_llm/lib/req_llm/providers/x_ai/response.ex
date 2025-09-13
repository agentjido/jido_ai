defmodule ReqLLM.Providers.XAI.Response do
  @moduledoc false
  defstruct [:payload]
  @type t :: %__MODULE__{payload: term()}
end

# Protocol implementation for xAI-specific response decoding
# xAI uses OpenAI-compatible response format with some xAI-specific extensions
defimpl ReqLLM.Response.Codec, for: ReqLLM.Providers.XAI.Response do
  alias ReqLLM.{Response, Context, Message, StreamChunk, Model}

  @doc """
  Decode wrapped xAI response struct.
  """
  def decode_response(%{payload: _data} = _wrapped_response) do
    # Wrapped responses without model should use decode_response/2 instead
    {:error, :not_implemented}
  end

  @doc """
  Decode wrapped xAI response struct with model information.
  """
  def decode_response(
        %{payload: stream} = _wrapped_response,
        %Model{provider: :xai} = model
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

  def decode_response(%{payload: data} = _wrapped_response, %Model{provider: :xai} = model)
      when is_map(data) do
    try do
      result =
        ReqLLM.Providers.XAI.ResponseDecoder.decode_xai_json(
          data,
          model.model || "unknown"
        )

      result
    rescue
      error -> {:error, error}
    end
  end

  def decode_response(_wrapped_response, _model) do
    {:error, :unsupported_provider}
  end

  def encode_request(_), do: {:error, :not_implemented}

  # SSE Event decoding for streaming responses (xAI uses OpenAI-compatible format with reasoning)
  defp decode_sse_event(%{event: "completion", data: %{"choices" => [%{"delta" => delta} | _]}}) do
    decode_xai_delta(delta)
  end

  defp decode_sse_event(%{data: %{"choices" => [%{"delta" => delta} | _]}}) do
    decode_xai_delta(delta)
  end

  defp decode_sse_event(_event), do: []

  defp decode_xai_delta(%{"content" => content}) when is_binary(content) and content != "" do
    [StreamChunk.text(content)]
  end

  # Handle xAI reasoning content in streaming
  defp decode_xai_delta(%{"reasoning_content" => reasoning_content})
       when is_binary(reasoning_content) and reasoning_content != "" do
    [StreamChunk.thinking(reasoning_content)]
  end

  defp decode_xai_delta(%{"tool_calls" => tool_calls}) when is_list(tool_calls) do
    tool_calls
    |> Enum.map(&decode_tool_call_delta/1)
    |> Enum.reject(&is_nil/1)
  end

  defp decode_xai_delta(_), do: []

  defp decode_tool_call_delta(%{
         "id" => id,
         "type" => "function",
         "function" => %{"name" => name, "arguments" => args_json}
       }) do
    case Jason.decode(args_json || "{}") do
      {:ok, args} -> StreamChunk.tool_call(name, args, %{id: id})
      {:error, _} -> nil
    end
  end

  defp decode_tool_call_delta(_), do: nil
end

defmodule ReqLLM.Providers.XAI.ResponseDecoder do
  @moduledoc false
  alias ReqLLM.{Response, Context, Message, StreamChunk, Model}

  def decode_xai_json(data, model) when is_map(data) do
    # Extract basic response information
    id = Map.get(data, "id", "unknown")
    model_name = Map.get(data, "model", model || "unknown")
    usage = parse_usage(Map.get(data, "usage"))

    # Extract choices and get the first one
    choices = Map.get(data, "choices", [])
    first_choice = Enum.at(choices, 0, %{})

    finish_reason = parse_finish_reason(Map.get(first_choice, "finish_reason"))

    # Convert xAI choice to StreamChunks
    content_chunks =
      case first_choice do
        %{"message" => message} -> decode_xai_message(message)
        %{"delta" => delta} -> decode_xai_delta(delta)
        _ -> []
      end

    # Build assistant message from content chunks
    message = build_message_from_chunks(content_chunks)

    # Create a minimal context with just the assistant message
    context = %Context{
      messages: if(message, do: [message], else: [])
    }

    # Extract xAI-specific metadata
    provider_meta =
      data
      |> Map.drop(["id", "model", "choices", "usage"])
      |> Map.put("system_fingerprint", Map.get(data, "system_fingerprint"))
      # xAI may include live search information or other specific metadata
      |> Map.put("x_xai", Map.get(data, "x_xai"))
      |> Map.put("live_search_used", Map.get(data, "live_search_used"))

    response = %Response{
      id: id,
      model: model_name,
      context: context,
      message: message,
      stream?: false,
      stream: nil,
      usage: usage,
      finish_reason: finish_reason,
      provider_meta: provider_meta
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
          %Message{
            role: :assistant,
            content: content_parts,
            metadata: %{}
          }
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

  defp decode_xai_message(%{"content" => content})
       when is_binary(content) and content != "" do
    [ReqLLM.StreamChunk.text(content)]
  end

  # Handle xAI reasoning models that put content in reasoning_content
  defp decode_xai_message(%{"content" => "", "reasoning_content" => reasoning_content})
       when is_binary(reasoning_content) and reasoning_content != "" do
    [ReqLLM.StreamChunk.text(reasoning_content)]
  end

  defp decode_xai_message(%{"reasoning_content" => reasoning_content})
       when is_binary(reasoning_content) and reasoning_content != "" do
    [ReqLLM.StreamChunk.text(reasoning_content)]
  end

  defp decode_xai_message(%{"content" => content}) when is_list(content) do
    content
    |> Enum.map(&decode_content_part/1)
    |> List.flatten()
    |> Enum.reject(&is_nil/1)
  end

  defp decode_xai_message(%{"tool_calls" => tool_calls}) when is_list(tool_calls) do
    tool_calls
    |> Enum.map(&decode_tool_call/1)
    |> Enum.reject(&is_nil/1)
  end

  defp decode_xai_message(_), do: []

  defp decode_xai_delta(%{"content" => content})
       when is_binary(content) and content != "" do
    [ReqLLM.StreamChunk.text(content)]
  end

  # Handle xAI reasoning deltas
  defp decode_xai_delta(%{"reasoning_content" => reasoning_content})
       when is_binary(reasoning_content) and reasoning_content != "" do
    [ReqLLM.StreamChunk.text(reasoning_content)]
  end

  defp decode_xai_delta(%{"tool_calls" => tool_calls}) when is_list(tool_calls) do
    tool_calls
    |> Enum.map(&decode_tool_call/1)
    |> Enum.reject(&is_nil/1)
  end

  defp decode_xai_delta(_), do: []

  defp decode_content_part(%{"type" => "text", "text" => text}) do
    [ReqLLM.StreamChunk.text(text)]
  end

  defp decode_content_part(_), do: []

  defp decode_tool_call(%{
         "id" => id,
         "type" => "function",
         "function" => %{"name" => name, "arguments" => args_json}
       }) do
    case Jason.decode(args_json || "{}") do
      {:ok, args} -> ReqLLM.StreamChunk.tool_call(name, args, %{id: id})
      {:error, _} -> nil
    end
  end

  defp decode_tool_call(_), do: nil

  # xAI uses OpenAI-compatible usage format with possible extensions
  def parse_usage(
        %{
          "prompt_tokens" => input,
          "completion_tokens" => output,
          "total_tokens" => total
        } = usage
      ) do
    base_usage = %{
      input_tokens: input,
      output_tokens: output,
      total_tokens: total
    }

    # Include xAI-specific usage information if present
    case Map.get(usage, "num_sources_used") do
      nil -> base_usage
      sources -> Map.put(base_usage, :live_search_sources, sources)
    end
  end

  # Handle already-converted format (from fixtures)
  def parse_usage(
        %{
          "input_tokens" => input,
          "output_tokens" => output,
          "total_tokens" => total
        } = usage
      ) do
    base_usage = %{
      input_tokens: input,
      output_tokens: output,
      total_tokens: total
    }

    # Include xAI-specific usage information if present
    case Map.get(usage, "live_search_sources") do
      nil -> base_usage
      sources -> Map.put(base_usage, :live_search_sources, sources)
    end
  end

  def parse_usage(_), do: %{input_tokens: 0, output_tokens: 0, total_tokens: 0}

  # xAI uses standard OpenAI finish reasons
  def parse_finish_reason("stop"), do: :stop
  def parse_finish_reason("length"), do: :length
  def parse_finish_reason("tool_calls"), do: :tool_calls
  def parse_finish_reason("content_filter"), do: :content_filter
  def parse_finish_reason(reason) when is_binary(reason), do: reason
  def parse_finish_reason(_), do: nil
end
