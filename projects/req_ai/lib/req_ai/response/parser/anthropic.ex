defmodule ReqAI.Response.Parser.Anthropic do
  @moduledoc """
  Response parser for Anthropic Claude API.

  Parses Anthropic API responses and extracts text content from the response format.
  Handles both successful responses and API errors with proper error mapping.
  """

  alias ReqAI.Error

  @doc """
  Parses an Anthropic API response and extracts the generated text.

  Handles:
  - Successful 200 responses with content extraction
  - API errors (4xx/5xx) with proper error mapping
  - Network and parsing errors

  ## Parameters

  - `response` - Req.Response struct from the API call
  - `context` - Additional context (model, request info, etc.)
  - `opts` - Parsing options

  ## Examples

      # Successful response
      response = %Req.Response{status: 200, body: %{"content" => [%{"text" => "Hello!"}]}}
      {:ok, "Hello!"} = ReqAI.Response.Parser.Anthropic.parse_response(response, %{}, [])
      
      # API error
      error_response = %Req.Response{status: 400, body: %{"error" => %{"message" => "Invalid request"}}}
      {:error, %ReqAI.Error{}} = ReqAI.Response.Parser.Anthropic.parse_response(error_response, %{}, [])

  """
  @spec parse_response(Req.Response.t(), map(), keyword()) ::
          {:ok, String.t()} | {:error, ReqAI.Error.t()}
  def parse_response(%Req.Response{status: 200, body: body}, _context, _opts) do
    extract_text_from_body(body)
  end

  def parse_response(%Req.Response{status: status, body: body}, _context, _opts)
      when status >= 400 do
    reason = extract_error_message(body)
    {:error, Error.API.Request.exception(status: status, reason: reason, response_body: body)}
  end

  def parse_response(%Req.Response{} = response, _context, _opts) do
    {:error,
     Error.API.Request.exception(
       reason: "Unexpected response status: #{response.status}",
       status: response.status,
       response_body: response.body
     )}
  end

  defp extract_text_from_body(%{"content" => [%{"text" => text} | _]}) do
    {:ok, text}
  end

  defp extract_text_from_body(%{"content" => content}) when is_list(content) do
    text =
      content
      |> Enum.filter(&(Map.get(&1, "type") == "text"))
      |> Enum.map(&Map.get(&1, "text", ""))
      |> Enum.join("")

    {:ok, text}
  end

  defp extract_text_from_body(body) do
    {:error,
     Error.API.Request.exception(
       reason: "Unexpected response format: #{inspect(body)}",
       response_body: body
     )}
  end

  defp extract_error_message(%{"error" => %{"message" => message}}) when is_binary(message) do
    message
  end

  defp extract_error_message(%{"error" => error}) when is_map(error) do
    inspect(error)
  end

  defp extract_error_message(body) do
    inspect(body)
  end
end
