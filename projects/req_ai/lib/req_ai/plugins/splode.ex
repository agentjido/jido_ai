defmodule ReqAI.Plugins.Splode do
  @moduledoc """
  Req plugin that integrates with Splode error handling.

  This plugin converts HTTP error responses to structured ReqAI.Error exceptions
  and handles common API error patterns. It processes both regular HTTP errors
  and API-specific error responses.

  ## Usage

      iex> req = Req.new() |> ReqAI.Plugins.Splode.attach()

  The plugin handles various HTTP status codes and converts them to appropriate
  ReqAI.Error types:

  - 400: Bad Request → API.Request error
  - 401: Unauthorized → API.Request error with authentication context
  - 403: Forbidden → API.Request error with authorization context
  - 404: Not Found → API.Request error
  - 429: Rate Limited → API.Request error with rate limit context
  - 500+: Server Error → API.Request error with server context

  ## Error Structure

  All errors include:
  - `status` - HTTP status code
  - `reason` - Human-readable error description
  - `response_body` - Raw API response (if available)
  - `request_body` - Original request body (if available)
  - `cause` - Underlying error cause (if available)

  """

  @doc """
  Attaches the Splode error handling plugin to a Req request struct.

  ## Parameters
    - `req` - The Req request struct

  ## Returns
    - Updated Req request struct with the plugin attached

  """
  @spec attach(Req.Request.t()) :: Req.Request.t()
  def attach(req) do
    Req.Request.append_error_steps(req, splode_errors: &handle_error_response/1)
  end

  @doc false
  @spec handle_error_response({Req.Request.t(), Req.Response.t() | Exception.t()}) ::
          {Req.Request.t(), ReqAI.Error.t()}
  def handle_error_response({request, %Req.Response{} = response}) do
    error = convert_response_to_error(request, response)
    {request, error}
  end

  def handle_error_response({request, exception}) when is_exception(exception) do
    error = convert_exception_to_error(request, exception)
    {request, error}
  end

  @spec convert_response_to_error(Req.Request.t(), Req.Response.t()) :: ReqAI.Error.t()
  defp convert_response_to_error(request, response) do
    reason = determine_error_reason(response)

    ReqAI.Error.API.Request.exception(
      reason: reason,
      status: response.status,
      response_body: response.body,
      request_body: request.body,
      cause: nil
    )
  end

  @spec convert_exception_to_error(Req.Request.t(), Exception.t()) :: ReqAI.Error.t()
  defp convert_exception_to_error(request, exception) do
    reason = Exception.message(exception)

    ReqAI.Error.API.Request.exception(
      reason: reason,
      status: nil,
      response_body: nil,
      request_body: request.body,
      cause: exception
    )
  end

  @spec determine_error_reason(Req.Response.t()) :: String.t()
  defp determine_error_reason(response) do
    case response.status do
      400 ->
        extract_api_error_message(response.body) ||
          "Bad Request - Invalid parameters or malformed request"

      401 ->
        extract_api_error_message(response.body) || "Unauthorized - Invalid or missing API key"

      403 ->
        extract_api_error_message(response.body) ||
          "Forbidden - Insufficient permissions or quota exceeded"

      404 ->
        extract_api_error_message(response.body) || "Not Found - Endpoint or resource not found"

      429 ->
        extract_api_error_message(response.body) || "Rate Limited - Too many requests"

      status when status >= 500 ->
        extract_api_error_message(response.body) || "Server Error - Internal API error"

      status ->
        extract_api_error_message(response.body) || "HTTP Error #{status}"
    end
  end

  @spec extract_api_error_message(any()) :: String.t() | nil
  defp extract_api_error_message(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} -> extract_api_error_message(decoded)
      {:error, _} -> nil
    end
  end

  defp extract_api_error_message(%{"error" => %{"message" => message}}) when is_binary(message) do
    message
  end

  defp extract_api_error_message(%{"error" => message}) when is_binary(message) do
    message
  end

  defp extract_api_error_message(%{"message" => message}) when is_binary(message) do
    message
  end

  defp extract_api_error_message(%{"detail" => message}) when is_binary(message) do
    message
  end

  defp extract_api_error_message(%{"details" => message}) when is_binary(message) do
    message
  end

  defp extract_api_error_message(%{"error_description" => message}) when is_binary(message) do
    message
  end

  defp extract_api_error_message(_), do: nil
end
