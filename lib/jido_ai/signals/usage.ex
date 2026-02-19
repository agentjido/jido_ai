defmodule Jido.AI.Signal.Usage do
  @moduledoc """
  Signal for token usage and cost tracking.
  """

  use Jido.Signal,
    type: "ai.usage",
    default_source: "/ai/usage",
    schema: [
      call_id: [type: :string, required: true, doc: "Correlation ID for the LLM call"],
      model: [type: :string, required: true, doc: "Model identifier"],
      input_tokens: [type: :integer, required: true, doc: "Number of input tokens"],
      output_tokens: [type: :integer, required: true, doc: "Number of output tokens"],
      total_tokens: [type: :integer, doc: "Total tokens (input + output)"],
      duration_ms: [type: :integer, doc: "Request duration in milliseconds"],
      metadata: [type: :map, default: %{}, doc: "Additional tracking metadata"]
    ]
end
