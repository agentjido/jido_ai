defmodule Jido.AI.Provider.Response.Stream do
  @moduledoc """
  Utilities for parsing streaming API responses.
  """

  alias Jido.AI.{Model, TokenCounter}

  require Logger

  @doc """
  Parses stream events based on the model's provider type.

  Supports different stream formats:
  - OpenAI/OpenRouter: delta format with content and reasoning fields
  - Anthropic: content_block_delta format with thinking and text deltas
  """
  @spec parse_events([map()], Model.t()) :: [String.t()]
  def parse_events(events, _model) do
    {content_chunks, _total_tokens} =
      events
      |> Enum.reduce({[], 0}, fn event, {chunks, token_count} ->
        case event do
          %{data: "[DONE]"} ->
            if token_count > 0 do
              Logger.debug("🔢 Stream response tokens: #{token_count}")

              # Note: For streaming, we'll calculate cost after the stream completes
              # since we need the request_body which isn't available here
            end

            {chunks, token_count}

          %{data: data} when is_binary(data) ->
            case Jason.decode(data) do
              # OpenAI/OpenRouter format
              {:ok, %{"choices" => [%{"delta" => delta} | _]}} ->
                parse_openai_delta(delta, chunks, token_count)

              # Anthropic format with content_block deltas
              {:ok, %{"type" => "content_block_delta", "delta" => delta}} ->
                parse_anthropic_delta(delta, chunks, token_count)

              {:ok, _} ->
                {chunks, token_count}

              {:error, _} ->
                {chunks, token_count}
            end

          _ ->
            {chunks, token_count}
        end
      end)

    Enum.reverse(content_chunks)
  end

  # Parse OpenAI/OpenRouter delta format
  defp parse_openai_delta(delta, chunks, token_count) do
    content = Map.get(delta, "content", "")
    reasoning = Map.get(delta, "reasoning", "")

    # Combine reasoning and content chunks
    combined_chunk =
      case {reasoning, content} do
        {"", ""} -> ""
        {"", content} -> content
        {reasoning, ""} -> "🧠 #{reasoning}"
        {reasoning, content} -> "🧠 #{reasoning}\n#{content}"
      end

    if combined_chunk == "" do
      {chunks, token_count}
    else
      chunk_tokens = TokenCounter.count_stream_tokens(combined_chunk)
      {[combined_chunk | chunks], token_count + chunk_tokens}
    end
  end

  # Parse Anthropic delta format
  defp parse_anthropic_delta(delta, chunks, token_count) do
    combined_chunk =
      case delta do
        %{"type" => "text_delta", "text" => text} ->
          text

        %{"type" => "thinking_delta", "thinking" => thinking} ->
          "🧠 #{thinking}"

        _ ->
          ""
      end

    if combined_chunk == "" do
      {chunks, token_count}
    else
      chunk_tokens = TokenCounter.count_stream_tokens(combined_chunk)
      {[combined_chunk | chunks], token_count + chunk_tokens}
    end
  end
end
