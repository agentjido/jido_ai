defmodule ReqAI.HTTP do
  @moduledoc """
  HTTP transport layer for ReqAI requests.

  Handles common HTTP operations including authentication injection
  and request execution.
  """

  @doc """
  Sends an HTTP request with authentication and common error handling.

  ## Parameters

  - `request` - The Req.Request.t() struct to send
  - `opts` - Additional options (currently unused)

  ## Returns

  `{:ok, response}` on success, `{:error, reason}` on failure.
  """
  @spec send(Req.Request.t(), keyword()) :: {:ok, Req.Response.t()} | {:error, term()}
  def send(request, _opts \\ []) do
    # Inject provider spec into request private data for Kagi plugin
    case Req.Request.get_private(request, :req_ai_provider_spec) do
      nil ->
        # No provider spec found, send without authentication
        execute_request(request)

      _provider_spec ->
        # Provider spec found, attach authentication
        request
        |> ReqAI.Plugins.Kagi.attach()
        |> execute_request()
    end
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
