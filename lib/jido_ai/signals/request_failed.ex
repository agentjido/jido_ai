defmodule Jido.AI.Signal.RequestFailed do
  @moduledoc """
  Signal for request lifecycle failure.
  """

  use Jido.Signal,
    type: "ai.request.failed",
    default_source: "/ai/request",
    schema: [
      request_id: [type: :string, required: true, doc: "Request correlation ID"],
      error: [type: :any, required: true, doc: "Failure reason payload"],
      run_id: [type: :string, doc: "Request-scoped run ID"]
    ]
end
