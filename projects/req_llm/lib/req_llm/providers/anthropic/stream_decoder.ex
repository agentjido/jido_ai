defmodule ReqLLM.Providers.Anthropic.StreamDecoder do
  @moduledoc """
  Handles streaming SSE events from Anthropic and properly accumulates JSON deltas
  for tool calls before emitting complete StreamChunk structs.

  This module fixes the issue where streaming tool calls return empty `%{}` arguments
  by accumulating `input_json_delta` events until a `content_block_stop` event
  signals that the JSON is complete.
  """

  alias ReqLLM.StreamChunk

  @doc """
  Builds a stream that properly accumulates tool call arguments from SSE events.

  Takes a raw stream of SSE events and returns a stream of complete StreamChunk structs
  with properly populated tool call arguments.
  """
  def build_stream(raw_stream) do
    Stream.transform(raw_stream, %{tool_calls: %{}}, &handle_event/2)
  end

  # Handle content block start for tool calls
  defp handle_event(
         %{event: "content_block_start", data: %{"content_block" => %{"type" => "tool_use", "id" => id, "name" => name}}},
         state
       ) do
    # Initialize tool call in state but don't emit yet
    new_state = put_in(state, [:tool_calls, id], %{name: name, args: %{}, accumulated_json: ""})
    {[], new_state}
  end

  # Handle input JSON delta events for tool calls
  defp handle_event(
         %{event: "content_block_delta", data: %{"delta" => %{"type" => "input_json_delta", "partial_json" => partial_json}}},
         state
       ) do
    # Find the active tool call - assumes single active tool call for now
    # In practice, Anthropic sends tool calls sequentially, not concurrently
    case find_active_tool_call(state) do
      {id, tool_call} ->
        # Accumulate the partial JSON string
        existing_json = Map.get(tool_call, :accumulated_json, "")
        updated_json = existing_json <> partial_json
        new_state = put_in(state, [:tool_calls, id, :accumulated_json], updated_json)
        {[], new_state}

      nil ->
        # No active tool call, ignore this delta
        {[], state}
    end
  end

  # Handle content block stop for tool calls - this is when we emit the complete tool call
  defp handle_event(
         %{event: "content_block_stop"},
         state
       ) do
    # Find the active tool call and emit it with complete arguments
    case find_active_tool_call(state) do
      {id, tool_call} ->
        # Parse the accumulated JSON
        case parse_accumulated_json(tool_call) do
          {:ok, args} ->
            chunk = StreamChunk.tool_call(tool_call.name, args, %{id: id})
            # Remove this tool call from state
            new_state = update_in(state, [:tool_calls], &Map.delete(&1, id))
            {[chunk], new_state}

          {:error, _reason} ->
            # If JSON parsing fails, emit with empty args as fallback
            chunk = StreamChunk.tool_call(tool_call.name, %{}, %{id: id, error: :json_parse_failed})
            new_state = update_in(state, [:tool_calls], &Map.delete(&1, id))
            {[chunk], new_state}
        end

      nil ->
        # No active tool call, just pass through
        {[], state}
    end
  end

  # Handle regular text content deltas
  defp handle_event(%{event: "content_block_delta", data: %{"delta" => %{"text" => text}}}, state) do
    {[StreamChunk.text(text)], state}
  end

  # Handle thinking block deltas
  defp handle_event(%{event: "thinking_block_delta", data: %{"delta" => %{"text" => text}}}, state) do
    {[StreamChunk.thinking(text)], state}
  end

  # Handle message stop events
  # Skip meta chunks for now to avoid fixture serialization issues
  defp handle_event(%{event: "message_stop"}, state) do
    {[], state}
  end

  # Handle message delta events with usage information
  # Skip usage for now to avoid fixture serialization issues
  defp handle_event(%{event: "message_delta", data: %{"usage" => _usage}}, state) do
    {[], state}
  end

  # Catch-all for other events
  defp handle_event(_event, state) do
    {[], state}
  end

  # Helper to find the currently active tool call (assumes single active call)
  defp find_active_tool_call(%{tool_calls: tool_calls}) when tool_calls == %{}, do: nil

  defp find_active_tool_call(%{tool_calls: tool_calls}) do
    # Return the first tool call (Anthropic processes them sequentially)
    case Enum.to_list(tool_calls) do
      [{id, tool_call} | _] -> {id, tool_call}
      [] -> nil
    end
  end

  # Helper to parse accumulated JSON string
  defp parse_accumulated_json(%{accumulated_json: json_str}) when is_binary(json_str) do
    case Jason.decode(json_str) do
      {:ok, parsed} -> {:ok, parsed}
      {:error, _} = error -> error
    end
  end

  defp parse_accumulated_json(tool_call) when is_map(tool_call) do
    # If no accumulated_json field, check for existing args or return empty
    case Map.get(tool_call, :accumulated_json) do
      nil -> {:ok, Map.get(tool_call, :args, %{})}
      json_str when is_binary(json_str) ->
        case Jason.decode(json_str) do
          {:ok, parsed} -> {:ok, parsed}
          {:error, _} = error -> error
        end
    end
  end

  defp parse_accumulated_json(_), do: {:ok, %{}}

  # Helper to parse usage from message delta
  defp parse_usage(%{"input_tokens" => input, "output_tokens" => output}) do
    %{
      input_tokens: input,
      output_tokens: output,
      total_tokens: input + output
    }
  end

  defp parse_usage(_), do: %{input_tokens: 0, output_tokens: 0, total_tokens: 0}
end
