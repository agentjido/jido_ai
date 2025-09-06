defmodule ReqAI.HTTP do
  @moduledoc """
  HTTP transport layer for ReqAI requests.

  Handles common HTTP operations including authentication injection
  and request execution.
  """

  @doc """
  Sends an HTTP request with authentication, token usage tracking, and error handling.

  ## Parameters

  - `request` - The Req.Request.t() struct to send
  - `opts` - Additional options (currently unused)

  ## Returns

  `{:ok, response}` on success, `{:error, reason}` on failure.
  """
  @spec send(Req.Request.t(), keyword()) :: {:ok, Req.Response.t()} | {:error, term()}
  def send(request, opts \\ []) do
    # Get model for token usage tracking
    model = Keyword.get(opts, :model) || Req.Request.get_private(request, :req_ai_model)

    # Build request with plugins
    request_with_plugins =
      case Req.Request.get_private(request, :req_ai_provider_spec) do
        nil ->
          # No provider spec found, send without authentication but with token tracking
          request
          |> ReqAI.Plugins.TokenUsage.attach(model)

        _provider_spec ->
          # Provider spec found, attach authentication and token tracking
          request
          |> ReqAI.Plugins.Kagi.attach()
          |> ReqAI.Plugins.TokenUsage.attach(model)
      end

    execute_request(request_with_plugins)
  end

  @doc """
  Attaches provider spec to request for authentication.

  This is used by providers to ensure their authentication spec
  is available to the Kagi plugin.
  """
  @spec with_provider_spec(Req.Request.t(), map()) :: Req.Request.t()
  def with_provider_spec(request, provider_spec) do
    Req.Request.put_private(request, :req_ai_provider_spec, provider_spec)
  end

  # Private implementation

  defp execute_request(request) do
    case Req.request(request) do
      {:ok, response} ->
        {:ok, response}

      {:error, reason} ->
        {:error, {:http_error, reason}}
    end
  end
end
