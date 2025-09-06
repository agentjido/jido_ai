defmodule ReqAI.HTTP.Default do
  @moduledoc """
  Default HTTP pipeline for ReqAI providers.
  
  Provides basic HTTP request execution with minimal configuration.
  """

  @doc """
  Executes an HTTP request with basic configuration.
  
  ## Parameters
  
    * `request` - A `Req.Request` struct
    * `opts` - Options (unused in this basic implementation)
  
  ## Returns
  
    * `{:ok, response}` - On successful request
    * `{:error, reason}` - On request failure
  """
  def run(request, _opts \\ []) do
    request
    |> add_user_agent()
    |> Req.run()
  end

  defp add_user_agent(request) do
    Req.Request.put_header(request, "user-agent", "req_ai/0.1.0")
  end
end
