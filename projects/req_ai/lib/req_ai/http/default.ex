defmodule ReqAI.HTTP.Default do
  @moduledoc """
  Default HTTP pipeline configuration for AI providers.

  This module provides a standard HTTP pipeline using Req with common
  plugins and configuration that most AI providers can use. Streaming
  support is conditionally enabled based on options.
  """

  @doc """
  Creates a default HTTP pipeline for the given base URL.

  The pipeline includes:
  - Base URL configuration
  - JSON request/response handling
  - Retry logic for transient failures
  - Streaming support (when requested)

  ## Parameters
    - `base_url` - The base URL for the API
    - `opts` - Additional options
      - `:stream?` - Enable streaming support (default: false)
      - `:provider_spec` - Provider specification for auth injection

  ## Returns
    - `Req.Request.t()` - Configured request pipeline

  ## Examples

      iex> ReqAI.HTTP.Default.http_pipeline("https://api.openai.com")
      %Req.Request{...}

      iex> ReqAI.HTTP.Default.http_pipeline("https://api.openai.com", stream?: true)
      %Req.Request{...}

      iex> provider_spec = %{id: :anthropic, auth: {:header, "x-api-key", :plain}}
      iex> ReqAI.HTTP.Default.http_pipeline("https://api.anthropic.com", provider_spec: provider_spec)
      %Req.Request{...}
  """
  @spec http_pipeline(String.t(), keyword()) :: Req.Request.t()
  def http_pipeline(base_url, opts \\ []) do
    pipeline =
      Req.new(base_url: base_url)
      |> Req.Request.append_request_steps(put_content_type: &put_json_content_type/1)
      |> Req.Request.append_response_steps(decode_json: &decode_json_response/1)
      |> Req.Request.append_error_steps(retry: &retry_transient_errors/1)

    # Optionally inject provider spec if provided
    pipeline =
      case Keyword.get(opts, :provider_spec) do
        %{} = provider_spec ->
          pipeline
          |> Req.Request.put_private(:req_ai_provider_spec, provider_spec)
          |> ReqAI.Plugins.Kagi.attach()

        _ ->
          pipeline
      end

    if Keyword.get(opts, :stream?, false) do
      pipeline
      |> Req.Request.append_response_steps(decode_stream: &decode_stream_response/1)
    else
      pipeline
    end
  end

  # Private helper functions

  defp put_json_content_type({request, _opts}) do
    request = Req.Request.put_header(request, "content-type", "application/json")
    {request, []}
  end

  defp decode_json_response({request, response}) do
    case Req.Response.get_header(response, "content-type") do
      ["application/json" <> _] ->
        case Jason.decode(response.body) do
          {:ok, json} ->
            response = %{response | body: json}
            {request, response}

          {:error, _} ->
            {request, response}
        end

      _ ->
        {request, response}
    end
  end

  defp decode_stream_response({request, response}) do
    # Streaming response handling - simplified for Phase 1
    # Will be expanded in Phase 2 with full SSE support
    {request, response}
  end

  defp retry_transient_errors({request, _response_or_error}) do
    # Basic retry logic - will be expanded in Phase 2
    # For now, don't retry to keep it simple
    {request, []}
  end
end
