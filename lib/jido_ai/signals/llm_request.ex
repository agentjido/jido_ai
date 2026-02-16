defmodule Jido.AI.Signal.LLMRequest do
  @moduledoc """
  Signal for LLM call initiation.
  """

  use Jido.Signal,
    type: "ai.llm.request",
    default_source: "/ai/llm",
    schema: [
      call_id: [type: :string, required: true, doc: "Correlation ID for the LLM call"],
      model: [type: :string, required: true, doc: "Model identifier"],
      message_count: [type: :integer, doc: "Number of messages in conversation"],
      tool_count: [type: :integer, doc: "Number of tools available"],
      params: [type: :map, default: %{}, doc: "Request parameters"],
      trace_id: [type: :string, doc: "Parent trace ID for distributed tracing"]
    ]
end
