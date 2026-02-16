defmodule Jido.AI.Signal.RequestError do
  @moduledoc """
  Signal for request rejection.
  """

  use Jido.Signal,
    type: "ai.request.error",
    default_source: "/ai/strategy",
    schema: [
      request_id: [type: :string, required: true, doc: "Correlation ID for the request"],
      reason: [type: :atom, required: true, doc: "Error reason atom"],
      message: [type: :string, required: true, doc: "Human-readable error message"]
    ]
end
