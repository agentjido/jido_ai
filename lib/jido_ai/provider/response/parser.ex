defmodule Jido.AI.Provider.Response.Parser do
  @moduledoc """
  Utilities for parsing API responses.
  """

  alias Jido.AI.Error.API

  @doc """
  Extracts the text content from a chat completion response.

  Returns a tuple with the text content and optional metadata (usage, cost).

  ## Examples

      iex> response = %Req.Response{
      ...>   status: 200,
      ...>   body: %{
      ...>     "choices" => [
      ...>       %{"message" => %{"content" => "Hello there!"}}
      ...>     ]
      ...>   }
      ...> }
      iex> Jido.AI.Provider.Response.Parser.extract_text_response(response)
      {:ok, "Hello there!", nil}

  """
  @spec extract_text_response(struct()) :: {:ok, String.t(), map() | nil} | {:error, struct()}
  def extract_text_response(%{status: 200, jido_meta: meta} = response) when is_map(meta) do
    extract_text_with_meta(response.body, meta)
  end

  def extract_text_response(%{status: 200, body: body}) do
    extract_text_with_meta(body, nil)
  end

  def extract_text_response(%{status: status, body: body}) when status >= 400 do
    {:error,
     API.Request.exception(
       reason: format_http_error(status, body),
       status: status,
       response_body: body
     )}
  end

  def extract_text_response(response) do
    {:error, API.Request.exception(reason: "Unexpected response: #{inspect(response)}")}
  end

  defp extract_text_with_meta(body, meta) do
    case body do
      # OpenAI/OpenRouter format with choices
      %{"choices" => [%{"message" => message} | _]} ->
        content = Map.get(message, "content", "")
        reasoning = Map.get(message, "reasoning")

        # If reasoning is present and non-empty, combine it with content
        response =
          if reasoning != nil and reasoning != "" do
            "🧠 **Reasoning:**\n#{reasoning}\n\n**Response:**\n#{content}"
          else
            content
          end

        {:ok, response, meta}

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
          if thinking_text == "" do
            content_text
          else
            "🧠 **Thinking:**\n#{thinking_text}\n\n**Response:**\n#{content_text}"
          end

        {:ok, response, meta}

      _ ->
        {:error, API.Request.exception(reason: "Invalid response format")}
    end
  end

  @doc """
  Extracts structured data from a chat completion response.

  ## Examples

      iex> response = %Req.Response{
      ...>   status: 200,
      ...>   body: %{
      ...>     "choices" => [
      ...>       %{"message" => %{"content" => "{\"name\": \"John\", \"age\": 30}"}}
      ...>     ]
      ...>   }
      ...> }
      iex> Jido.AI.Provider.Response.Parser.extract_object_response(response)
      {:ok, %{"name" => "John", "age" => 30}, nil}

  """
  @spec extract_object_response(struct()) :: {:ok, map(), map() | nil} | {:error, struct()}
  def extract_object_response(%{status: 200, jido_meta: meta} = response) when is_map(meta) do
    extract_object_with_meta(response.body, meta)
  end

  def extract_object_response(%{status: 200, body: body}) do
    extract_object_with_meta(body, nil)
  end

  def extract_object_response(%{status: status, body: body}) when status >= 400 do
    {:error,
     API.Request.exception(
       reason: format_http_error(status, body),
       status: status,
       response_body: body
     )}
  end

  def extract_object_response(response) do
    {:error, API.Request.exception(reason: "Unexpected response: #{inspect(response)}")}
  end

  defp extract_object_with_meta(body, meta) do
    case body do
      %{"choices" => [%{"message" => %{"content" => content}} | _]} ->
        case parse_json_response(content) do
          {:ok, parsed} -> {:ok, parsed, meta}
          error -> error
        end

      _ ->
        {:error, API.Request.exception(reason: "Invalid response format")}
    end
  end

  # Private helpers

  # Parses JSON content from API response, returning appropriate errors for invalid JSON.
  @spec parse_json_response(String.t()) :: {:ok, map()} | {:error, struct()}
  defp parse_json_response(content) when is_binary(content) do
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
          error_msg when is_binary(error_msg) -> error_msg
          _ -> "HTTP #{status}"
        end

      error_msg when is_binary(error_msg) ->
        error_type = get_in(body, ["error", "type"]) || "unknown"
        "#{error_msg} (#{error_type})"
    end
  end

  defp format_http_error(status, body) when is_binary(body) do
    "HTTP #{status}: #{String.slice(body, 0, 200)}"
  end

  defp format_http_error(status, _), do: "HTTP #{status}"
end
