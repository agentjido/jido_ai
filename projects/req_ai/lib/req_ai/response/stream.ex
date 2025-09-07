defmodule ReqAI.Response.Stream do
  @moduledoc """
  Utilities for parsing streaming API responses with reasoning token support.

  This module handles the extraction of text content from streaming AI provider 
  responses, including reasoning tokens when present. It supports multiple 
  provider formats:

  - OpenAI/OpenRouter: delta format with `content` and `reasoning` fields
  - Anthropic: content_block_delta format with `thinking` and `text` deltas

  ## Examples

      iex> events = [
      ...>   %{data: ~s({"choices":[{"delta":{"reasoning":"I should be helpful"}}]})},
      ...>   %{data: ~s({"choices":[{"delta":{"content":"Hello!"}}]})},
      ...>   %{data: "[DONE]"}
      ...> ]
      iex> ReqAI.Response.Stream.parse_events(events)
      ["🧠 I should be helpful", "Hello!"]

  """

  @doc """
  Parses stream events into text chunks with reasoning token support.

  Takes a list of Server-Sent Event maps (with `:data` fields) and returns
  a list of text chunks. Reasoning tokens are prefixed with 🧠 for visual
  distinction.
  """
  @spec parse_events([map()]) :: [String.t()]
  def parse_events(events) do
    events
    |> Enum.reduce([], fn event, chunks ->
      case event do
        %{data: "[DONE]"} ->
          chunks

        %{data: data} when is_binary(data) ->
          case Jason.decode(data) do
            # OpenAI/OpenRouter format
            {:ok, %{"choices" => [%{"delta" => delta} | _]}} ->
              case parse_openai_delta(delta) do
                "" -> chunks
                chunk -> [chunk | chunks]
              end

            # Anthropic format with content_block deltas
            {:ok, %{"type" => "content_block_delta", "delta" => delta}} ->
              case parse_anthropic_delta(delta) do
                "" -> chunks
                chunk -> [chunk | chunks]
              end

            {:ok, _} ->
              chunks

            {:error, _} ->
              chunks
          end

        _ ->
          chunks
      end
    end)
    |> Enum.reverse()
  end

  # Private implementation

  # Parse OpenAI/OpenRouter delta format
  defp parse_openai_delta(delta) do
    content = Map.get(delta, "content", "")
    reasoning = Map.get(delta, "reasoning", "")

    case {reasoning, content} do
      {"", ""} -> ""
      {"", content} -> content
      {reasoning, ""} -> "🧠 #{reasoning}"
      {reasoning, content} -> "🧠 #{reasoning}\n#{content}"
    end
  end

  # Parse Anthropic delta format
  defp parse_anthropic_delta(delta) do
    case delta do
      %{"type" => "text_delta", "text" => text} ->
        text

      %{"type" => "thinking_delta", "thinking" => thinking} ->
        "🧠 #{thinking}"

      _ ->
        ""
    end
  end
end
