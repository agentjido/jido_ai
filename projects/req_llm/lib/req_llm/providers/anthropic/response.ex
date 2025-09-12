defmodule ReqLLM.Providers.Anthropic.Response do
  @moduledoc false
  defstruct [:payload]
  @type t :: %__MODULE__{payload: term()}
end

# Protocol implementation for Anthropic-specific response decoding
defimpl ReqLLM.Response.Codec, for: ReqLLM.Providers.Anthropic.Response do
  alias ReqLLM.{Response, Context, Message, StreamChunk, Model}

  @doc """
  Direct decoding from Anthropic response data (Map or Stream).

  This allows zero-ceremony API usage by handling both Map and Stream
  payloads within a single protocol implementation.
  """
  def decode(%{payload: data}, %Model{provider: :anthropic} = model) when is_map(data) do
    try do
      decode_anthropic_json(data, model.model || "unknown")
    rescue
      error -> {:error, error}
    end
  end

  def decode(%{payload: stream}, %Model{provider: :anthropic} = model)
      when is_struct(stream, Stream) do
    response = %Response{
      id: "streaming-response",
      model: model.model || "unknown",
      # Empty context initially for streaming
      context: %Context{messages: []},
      # Message built from stream
      message: nil,
      stream?: true,
      stream: stream,
      usage: %{input_tokens: 0, output_tokens: 0, total_tokens: 0},
      finish_reason: nil,
      provider_meta: %{}
    }

    {:ok, response}
  end

  def decode(_data, _model), do: {:error, :unsupported_provider}
  def decode(_data), do: {:error, :not_implemented}
  def encode(_), do: {:error, :not_implemented}

  # Private helpers for decoding Anthropic JSON
  defp decode_anthropic_json(data, model) when is_map(data) do
    # Extract basic response information
    id = Map.get(data, "id", "unknown")
    model_name = Map.get(data, "model", model || "unknown")
    usage = parse_usage(Map.get(data, "usage"))
    finish_reason = parse_finish_reason(Map.get(data, "stop_reason"))

    # Convert Anthropic content to StreamChunks using Context.Codec
    content_chunks =
      case Map.get(data, "content") do
        content when is_list(content) ->
          # Call decode_content_blocks directly since we just need to convert content blocks
          content
          |> Enum.map(&decode_content_block/1)
          |> List.flatten()
          |> Enum.reject(&is_nil/1)

        _ ->
          []
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
      model: model_name,
      context: context,
      message: message,
      stream?: false,
      stream: nil,
      usage: usage,
      finish_reason: finish_reason,
      provider_meta: Map.drop(data, ["id", "model", "content", "usage", "stop_reason"])
    }

    {:ok, response}
  end

  defp build_message_from_chunks(chunks) when is_list(chunks) do
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

  defp chunk_to_content_part(%StreamChunk{type: :content, text: text}) do
    %ReqLLM.Message.ContentPart{type: :text, text: text}
  end

  defp chunk_to_content_part(%StreamChunk{type: :thinking, text: text}) do
    %ReqLLM.Message.ContentPart{type: :reasoning, text: text}
  end

  defp chunk_to_content_part(%StreamChunk{
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

  defp chunk_to_content_part(_), do: nil

  defp parse_usage(%{"input_tokens" => input, "output_tokens" => output}) do
    %{
      input_tokens: input,
      output_tokens: output,
      total_tokens: input + output
    }
  end

  defp parse_usage(_), do: %{input_tokens: 0, output_tokens: 0, total_tokens: 0}

  defp parse_finish_reason("end_turn"), do: :stop
  defp parse_finish_reason("max_tokens"), do: :length
  defp parse_finish_reason("tool_use"), do: :tool_calls
  defp parse_finish_reason("stop_sequence"), do: :stop
  defp parse_finish_reason(reason) when is_binary(reason), do: reason
  defp parse_finish_reason(_), do: nil

  # Helper functions for content decoding (copied from Context)
  defp decode_content_block(%{"type" => "text", "text" => text}) do
    [ReqLLM.StreamChunk.text(text)]
  end

  defp decode_content_block(%{"type" => "tool_use", "id" => id, "name" => name, "input" => input}) do
    [ReqLLM.StreamChunk.tool_call(name, input, %{id: id})]
  end

  defp decode_content_block(%{"type" => "thinking", "text" => text}) do
    [ReqLLM.StreamChunk.thinking(text)]
  end

  defp decode_content_block(_unknown), do: []
end
