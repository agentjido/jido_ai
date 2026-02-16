defmodule Jido.AI.Signal.RequestStarted do
  @moduledoc """
  Signal for request lifecycle start.
  """

  use Jido.Signal,
    type: "ai.request.started",
    default_source: "/ai/request",
    schema: [
      request_id: [type: :string, required: true, doc: "Request correlation ID"],
      query: [type: :string, required: true, doc: "Original user query"],
      run_id: [type: :string, doc: "Request-scoped run ID"]
    ]
end
