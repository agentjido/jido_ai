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
  def decode_response(
        %{payload: stream} = _wrapped_response,
        %Model{provider: :anthropic} = model
      )
      when is_struct(stream, Stream) do
    # Use the new StreamDecoder to properly handle tool call accumulation
    chunk_stream = ReqLLM.Providers.Anthropic.StreamDecoder.build_stream(stream)

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

  def decode_response(%{payload: data} = _wrapped_response, %Model{provider: :anthropic} = model)
      when is_map(data) do
    result =
      ReqLLM.Providers.Anthropic.ResponseDecoder.decode_anthropic_json(
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

  def decode_response(_wrapped_response, _model) do
    {:error, :unsupported_provider}
  end

  def encode_request(_), do: {:error, :not_implemented}
end

# Protocol implementation for direct Map decoding (zero-ceremony API)
defimpl ReqLLM.Response.Codec, for: Map do
  alias ReqLLM.{Response, Context, Message, StreamChunk, Model}

  @doc """
  Direct decoding from raw Map response data.

  Handles both Anthropic and OpenAI provider maps; other providers will get not_implemented.
  """
  def decode_response(_data), do: {:error, :not_implemented}

  def decode_response(data, %Model{provider: :anthropic} = model) when is_map(data) do
    # Only handle maps that look like Anthropic responses (have id, model, or content keys)
    if Map.has_key?(data, "id") or Map.has_key?(data, "model") or Map.has_key?(data, "content") do
      try do
        result =
          ReqLLM.Providers.Anthropic.ResponseDecoder.decode_anthropic_json(
            data,
            model.model || "unknown"
          )

        result
      rescue
        error -> {:error, error}
      catch
        {:decode_error, reason} ->
          {:error, %ReqLLM.Error.API.Response{reason: reason}}
      end
    else
      {:error, :not_implemented}
    end
  end

  def decode_response(data, %Model{provider: :openai} = model) when is_map(data) do
    # Only handle maps that look like OpenAI responses
    if Map.has_key?(data, "choices") or Map.has_key?(data, "id") or Map.has_key?(data, "object") do
      try do
        result =
          ReqLLM.Providers.OpenAI.ResponseDecoder.decode_openai_json(
            data,
            model.model || "unknown"
          )

        result
      rescue
        error -> {:error, error}
      end
    else
      {:error, :not_implemented}
    end
  end

  def decode_response(data, %Model{provider: :google} = model) when is_map(data) do
    # Only handle maps that look like Google responses (have candidates or usageMetadata keys)
    if Map.has_key?(data, "candidates") or Map.has_key?(data, "usageMetadata") do
      try do
        result =
          ReqLLM.Providers.Google.ResponseDecoder.decode_google_json(
            data,
            model.model || "unknown"
          )

        result
      rescue
        error -> {:error, error}
      catch
        {:decode_error, reason} ->
          {:error, %ReqLLM.Error.API.Response{reason: reason}}
      end
    else
      {:error, :not_implemented}
    end
  end

  def decode_response(_data, _model), do: {:error, :unsupported_provider}
  def encode_request(_), do: {:error, :not_implemented}
end

defmodule ReqLLM.Providers.Anthropic.ResponseDecoder do
  @moduledoc false
  alias ReqLLM.{Response, Context, Message, StreamChunk}

  # Shared implementation for decoding Anthropic JSON
  def decode_anthropic_json(data, model) when is_map(data) do
    # Extract basic response information
    id = Map.get(data, "id", "unknown")
    model_name = Map.get(data, "model", model || "unknown")
    usage = parse_usage(Map.get(data, "usage"))
    finish_reason = parse_finish_reason(Map.get(data, "stop_reason"))

    # Convert Anthropic content to StreamChunks using Context.Codec
    raw_content = Map.get(data, "content")

    content_chunks =
      case raw_content do
        content when is_list(content) ->
          # Call decode_content_blocks directly since we just need to convert content blocks
          results = Enum.map(content, &decode_content_block/1)

          # Check for errors in results
          case Enum.find(results, &match?({:error, _}, &1)) do
            {:error, reason} ->
              throw({:decode_error, reason})

            nil ->
              chunks =
                results
                |> List.flatten()
                |> Enum.reject(&is_nil/1)

              chunks
          end

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
  def decode_content_block(%{"type" => "text", "text" => text}) when is_binary(text) do
    [ReqLLM.StreamChunk.text(text)]
  end

  def decode_content_block(%{"type" => "text", "text" => nil}) do
    {:error, "Text content cannot be nil"}
  end

  def decode_content_block(%{"type" => "text"}) do
    []
  end

  def decode_content_block(%{"type" => "tool_use", "id" => id, "name" => name, "input" => input}) do
    [ReqLLM.StreamChunk.tool_call(name, input, %{id: id})]
  end

  def decode_content_block(%{"type" => "thinking", "text" => text}) do
    [ReqLLM.StreamChunk.thinking(text)]
  end

  def decode_content_block(_unknown), do: []
end
