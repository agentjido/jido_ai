defmodule JidoAI.Examples.ModelOptions.HttpAdapter do
  @moduledoc "Runs a request-scoped callback and sends the real HTTP request through Finch."
  def run(request) do
    callback = request.options.finch_private[:example_callback]
    request |> callback.() |> Req.Finch.run()
  end
end
