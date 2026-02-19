defmodule Jido.AI.Signal.LLMError do
  @moduledoc """
  Signal for structured LLM errors.
  """

  use Jido.Signal,
    type: "ai.llm.error",
    default_source: "/ai/llm",
    schema: [
      call_id: [type: :string, required: true, doc: "Correlation ID for the LLM call"],
      error_type: [type: :atom, required: true, doc: "Error classification"],
      message: [type: :string, required: true, doc: "Human-readable error message"],
      details: [type: :map, default: %{}, doc: "Additional error details"],
      retry_after: [type: :integer, doc: "Seconds to wait before retry (for rate limits)"]
    ]
end
