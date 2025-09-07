defmodule ReqAI.Response.Parser do
  @moduledoc """
  Utilities for parsing non-streaming API responses with reasoning token support.

  This module handles the extraction of text content from AI provider responses,
  including reasoning tokens when present. It supports multiple provider formats:

  - OpenAI/OpenRouter: `reasoning` field in message
  - Anthropic: `thinking` content blocks

  ## Examples

      iex> response = %Req.Response{
      ...>   status: 200,
      ...>   body: %{
      ...>     "choices" => [
      ...>       %{"message" => %{
      ...>         "content" => "Hello there!",
      ...>         "reasoning" => "The user greeted me, so I should respond politely."
      ...>       }}
      ...>     ]
      ...>   }
      ...> }
      iex> ReqAI.Response.Parser.extract_text(response)
      {:ok, "🧠 **Reasoning:**\\nThe user greeted me, so I should respond politely.\\n\\n**Response:**\\nHello there!"}

  """

  alias ReqAI.Error.API

  @type response :: %Req.Response{status: non_neg_integer(), body: any()}

  @doc """
  Extracts text content from a chat completion response.

  Returns `{:ok, text}` for successful responses, where text may include
  reasoning tokens formatted with visual indicators. Returns `{:error, exception}`
  for error responses or invalid formats.
  """
  @spec extract_text(response()) :: {:ok, String.t()} | {:error, struct()}
  def extract_text(%Req.Response{status: 200, body: body}) do
    extract_text_from_body(body)
  end

  def extract_text(%Req.Response{status: status, body: body}) when status >= 400 do
    {:error, format_http_error(status, body)}
  end

  def extract_text(response) do
    {:error, API.Request.exception(reason: "Unexpected response: #{inspect(response)}")}
  end

  @doc """
  Extracts object content from a chat completion response.

  Attempts to parse the content as JSON and returns the parsed object.
  """
  @spec extract_object(response()) :: {:ok, map()} | {:error, struct()}
  def extract_object(%Req.Response{status: 200, body: body}) do
    extract_object_from_body(body)
  end

  def extract_object(%Req.Response{status: status, body: body}) when status >= 400 do
    {:error, format_http_error(status, body)}
  end

  def extract_object(response) do
    {:error, API.Request.exception(reason: "Unexpected response: #{inspect(response)}")}
  end

  # Private implementation

  defp extract_text_from_body(body) do
    case body do
      # OpenAI/OpenRouter format with choices
      %{"choices" => [%{"message" => message} | _]} ->
        content = Map.get(message, "content", "")
        reasoning = Map.get(message, "reasoning")

        response =
          if reasoning && reasoning != "" do
            "🧠 **Reasoning:**\n#{reasoning}\n\n**Response:**\n#{content}"
          else
            content
          end

        {:ok, response}

      # Anthropic format with content blocks
      %{"content" => content_blocks} when is_list(content_blocks) ->
        {thinking_parts, text_parts} =
          Enum.reduce(content_blocks, {[], []}, fn block, {thinking, text} ->
            case block do
              %{"type" => "thinking", "thinking" => thinking_content} ->
                {[thinking_content | thinking], text}

              %{"type" => "text", "text" => text_content} ->
                {thinking, [text_content | text]}

              _ ->
                {thinking, text}
            end
          end)

        thinking_text = thinking_parts |> Enum.reverse() |> Enum.join("\n")
        content_text = text_parts |> Enum.reverse() |> Enum.join("\n")

        response =
          if thinking_text != "" do
            "🧠 **Thinking:**\n#{thinking_text}\n\n**Response:**\n#{content_text}"
          else
            content_text
          end

        {:ok, response}

      _ ->
        {:error, API.Request.exception(reason: "Invalid response format")}
    end
  end

  defp extract_object_from_body(body) do
    case body do
      %{"choices" => [%{"message" => %{"content" => content}} | _]} ->
        parse_json_content(content)

      _ ->
        {:error, API.Request.exception(reason: "Invalid response format")}
    end
  end

  defp parse_json_content(content) when is_binary(content) do
    case Jason.decode(content) do
      {:ok, parsed} when is_map(parsed) ->
        {:ok, parsed}

      {:ok, _} ->
        {:error, API.Request.exception(reason: "Response is not a JSON object")}

      {:error, reason} ->
        {:error, API.Request.exception(reason: "Invalid JSON: #{inspect(reason)}")}
    end
  end

  defp format_http_error(status, body) when is_map(body) do
    case get_in(body, ["error", "message"]) do
      nil ->
        case get_in(body, ["error"]) do
          error_msg when is_binary(error_msg) -> 
            API.Request.exception(reason: error_msg, status: status)
          _ -> 
            API.Request.exception(reason: "HTTP #{status}", status: status)
        end

      error_msg when is_binary(error_msg) ->
        error_type = get_in(body, ["error", "type"]) || "unknown"
        API.Request.exception(reason: "#{error_msg} (#{error_type})", status: status)
    end
  end

  defp format_http_error(status, body) when is_binary(body) do
    API.Request.exception(
      reason: "HTTP #{status}: #{String.slice(body, 0, 200)}",
      status: status
    )
  end

  defp format_http_error(status, _) do
    API.Request.exception(reason: "HTTP #{status}", status: status)
  end
end
