defmodule ReqLLM.Providers.Anthropic.Response do
  @moduledoc false
  defstruct [:payload]
  @type t :: %__MODULE__{payload: term()}
end

# Protocol implementation for Anthropic-specific response decoding
defimpl ReqLLM.Response.Codec, for: ReqLLM.Providers.Anthropic.Response do
  alias ReqLLM.{Response, Context, Message, StreamChunk, Model}

  @doc """
  Decode wrapped Anthropic response struct.

  This handles tagged wrapper structs created by wrap_response.
  """
  def decode_response(%{payload: _data} = _wrapped_response) do
    # Wrapped responses without model should use decode_response/2 instead
    {:error, :not_implemented}
  end

  @doc """
  Decode wrapped Anthropic response struct with model information.
  """
  def decode_response(%{payload: data} = wrapped_response, %Model{provider: :anthropic} = model)
      when is_map(data) do
    IO.puts("🔍 Wrapped response in protocol: #{inspect(wrapped_response)}")
    IO.puts("🔍 Data extracted: #{inspect(data)}")
    IO.puts("🔍 Pattern match result: data keys = #{inspect(Map.keys(data))}")
    
    try do
      result = ReqLLM.Providers.Anthropic.ResponseDecoder.decode_anthropic_json(
        data,
        model.model || "unknown"
      )
      IO.puts("🔧 Protocol decode result: #{inspect(result |> elem(0))}")
      case result do
        {:ok, response} ->
          IO.puts("🔧 Protocol decoded message: #{inspect(response.message != nil)}")
          if response.message do
            IO.puts("🔧 Protocol content parts: #{length(response.message.content)}")
          end
        {:error, _} -> IO.puts("🔧 Protocol decode had error")
      end
      result
    rescue
      error ->
        IO.puts("🚨 Protocol decode error: #{inspect(error)}")
        {:error, error}
    end
  end

  def decode_response(
        %{payload: stream} = _wrapped_response,
        %Model{provider: :anthropic} = model
      )
      when is_struct(stream, Stream) do
    response = %Response{
      id: "streaming-response",
      model: model.model || "unknown",
      context: %Context{messages: []},
      message: nil,
      stream?: true,
      stream: stream,
      usage: %{input_tokens: 0, output_tokens: 0, total_tokens: 0},
      finish_reason: nil,
      provider_meta: %{}
    }

    {:ok, response}
  end

  def decode_response(wrapped_response, model) do
    IO.puts("🚨 Fallback decode_response called!")
    IO.puts("   Response: #{inspect(wrapped_response)}")
    IO.puts("   Model: #{inspect(model)}")
    {:error, :unsupported_provider}
  end
  def encode_request(_), do: {:error, :not_implemented}
end

# Protocol implementation for direct Map decoding (zero-ceremony API)
defimpl ReqLLM.Response.Codec, for: Map do
  alias ReqLLM.{Response, Context, Message, StreamChunk, Model}

  @doc """
  Direct decoding from raw Anthropic Map response data.

  Only handles Anthropic provider maps; other providers will get not_implemented.
  """
  def decode_response(_data), do: {:error, :not_implemented}

  def decode_response(data, %Model{provider: :anthropic} = model) when is_map(data) do
    # Only handle maps that look like Anthropic responses (have id, model, or content keys)
    if Map.has_key?(data, "id") or Map.has_key?(data, "model") or Map.has_key?(data, "content") do
      IO.puts("🗺️  Map protocol decode called!")
      try do
        result = ReqLLM.Providers.Anthropic.ResponseDecoder.decode_anthropic_json(
          data,
          model.model || "unknown"
        )
        IO.puts("🗺️  Map protocol result: #{inspect(result |> elem(0))}")
        case result do
          {:ok, response} ->
            IO.puts("🗺️  Map decoded message: #{inspect(response.message != nil)}")
            if response.message do
              IO.puts("🗺️  Map content parts: #{length(response.message.content)}")
            end
          {:error, _} -> IO.puts("🗺️  Map decode had error")
        end
        result
      rescue
        error -> {:error, error}
      end
    else
      {:error, :not_implemented}
    end
  end

  def decode_response(_data, _model), do: {:error, :unsupported_provider}
  def encode_request(_), do: {:error, :not_implemented}

  # Use shared implementation
  defp decode_anthropic_json(data, model),
    do: ReqLLM.Providers.Anthropic.ResponseDecoder.decode_anthropic_json(data, model)
end

defmodule ReqLLM.Providers.Anthropic.ResponseDecoder do
  @moduledoc false
  alias ReqLLM.{Response, Context, Message, StreamChunk, Model}

  # Shared implementation for decoding Anthropic JSON
  def decode_anthropic_json(data, model) when is_map(data) do
    IO.puts("🔧 decode_anthropic_json called with data keys: #{inspect(Map.keys(data))}")
    
    # Extract basic response information
    id = Map.get(data, "id", "unknown")
    model_name = Map.get(data, "model", model || "unknown")
    usage = parse_usage(Map.get(data, "usage"))
    finish_reason = parse_finish_reason(Map.get(data, "stop_reason"))

    # Convert Anthropic content to StreamChunks using Context.Codec
    IO.puts("🧩 Content extraction starting...")
    raw_content = Map.get(data, "content")
    IO.puts("   Raw content: #{inspect(raw_content)}")
    
    content_chunks =
      case raw_content do
        content when is_list(content) ->
          IO.puts("   Content is list with #{length(content)} items")
          # Call decode_content_blocks directly since we just need to convert content blocks
          chunks = content
          |> Enum.map(&decode_content_block/1)
          |> List.flatten()
          |> Enum.reject(&is_nil/1)
          
          IO.puts("   Decoded to #{length(chunks)} chunks")
          Enum.with_index(chunks)
          |> Enum.each(fn {chunk, idx} ->
            IO.puts("     Chunk #{idx}: #{inspect(chunk)}")
          end)
          chunks

        _ ->
          IO.puts("   Content is not a list: #{inspect(raw_content)}")
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

  def build_message_from_chunks(chunks) when is_list(chunks) do
    IO.puts("🔨 Building message from #{length(chunks)} chunks")
    Enum.with_index(chunks)
    |> Enum.each(fn {chunk, idx} ->
      IO.puts("   Chunk #{idx}: #{inspect(chunk)}")
    end)
    
    case chunks do
      [] ->
        IO.puts("🔨 No chunks, returning nil")
        nil

      _ ->
        # Convert StreamChunks to Message.ContentPart structs
        content_parts =
          chunks
          |> Enum.map(&chunk_to_content_part/1)
          |> Enum.reject(&is_nil/1)

        IO.puts("🔨 Converted to #{length(content_parts)} content parts")
        Enum.with_index(content_parts)
        |> Enum.each(fn {part, idx} ->
          IO.puts("   Part #{idx}: #{inspect(part)}")
        end)

        if content_parts != [] do
          message = %Message{
            role: :assistant,
            content: content_parts,
            metadata: %{}
          }
          IO.puts("🔨 Created message: #{inspect(message != nil)}")
          message
        else
          IO.puts("🔨 No content parts, returning nil")
          nil
        end
    end
  end

  def chunk_to_content_part(%StreamChunk{type: :content, text: text}) do
    %ReqLLM.Message.ContentPart{type: :text, text: text}
  end

  def chunk_to_content_part(%StreamChunk{type: :thinking, text: text}) do
    %ReqLLM.Message.ContentPart{type: :reasoning, text: text}
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

  def parse_usage(%{"input_tokens" => input, "output_tokens" => output} = usage_map) do
    # Handle both simple and complex Anthropic usage structures
    %{
      input_tokens: input,
      output_tokens: output,
      total_tokens: input + output,
      # Preserve additional usage metadata from Anthropic
      cache_creation_input_tokens: Map.get(usage_map, "cache_creation_input_tokens", 0),
      cache_read_input_tokens: Map.get(usage_map, "cache_read_input_tokens", 0),
      service_tier: Map.get(usage_map, "service_tier")
    }
  end

  def parse_usage(_), do: %{input_tokens: 0, output_tokens: 0, total_tokens: 0}

  def parse_finish_reason("end_turn"), do: :stop
  def parse_finish_reason("max_tokens"), do: :length
  def parse_finish_reason("tool_use"), do: :tool_calls
  def parse_finish_reason("stop_sequence"), do: :stop
  def parse_finish_reason(reason) when is_binary(reason), do: reason
  def parse_finish_reason(_), do: nil

  # Helper functions for content decoding (copied from Context)
  def decode_content_block(%{"type" => "text", "text" => text}) do
    [ReqLLM.StreamChunk.text(text)]
  end

  def decode_content_block(%{"type" => "tool_use", "id" => id, "name" => name, "input" => input}) do
    [ReqLLM.StreamChunk.tool_call(name, input, %{id: id})]
  end

  def decode_content_block(%{"type" => "thinking", "text" => text}) do
    [ReqLLM.StreamChunk.thinking(text)]
  end

  def decode_content_block(_unknown), do: []
end
