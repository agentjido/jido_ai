defmodule Jido.AI.Signal.LLMCancelled do
  @moduledoc """
  Signal for LLM call cancellation.
  """

  use Jido.Signal,
    type: "ai.llm.cancelled",
    default_source: "/ai/llm",
    schema: [
      call_id: [type: :string, required: true, doc: "Correlation ID for the LLM call"],
      reason: [type: :atom, required: true, doc: "Cancellation reason"],
      at_ms: [type: :integer, doc: "Timestamp when cancellation occurred"]
    ]
end
