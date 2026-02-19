defmodule Jido.AI.Signal.RequestCompleted do
  @moduledoc """
  Signal for request lifecycle completion.
  """

  use Jido.Signal,
    type: "ai.request.completed",
    default_source: "/ai/request",
    schema: [
      request_id: [type: :string, required: true, doc: "Request correlation ID"],
      result: [type: :any, required: true, doc: "Final result payload"],
      run_id: [type: :string, doc: "Request-scoped run ID"]
    ]
end
