defmodule Jido.AI.Signal.LLMDelta do
  @moduledoc """
  Signal for streaming LLM token chunks.
  """

  use Jido.AI.Signal.Definition,
    type: "ai.llm.delta",
    default_source: "/ai/llm",
    schema: [
      call_id: [type: :string, required: true, doc: "Correlation ID for the LLM call"],
      delta: [type: :any, required: true, doc: "Text or complete content part from the stream"],
      chunk_type: [
        type: :atom,
        default: :content,
        doc: "Type: :content, :content_part, or :thinking"
      ],
      metadata: [type: :map, default: %{}, doc: "Optional request/run metadata for correlation"],
      seq: [type: :integer, doc: "Monotonic runtime sequence number for this delta, when available"],
      run_id: [type: :string, doc: "Runtime run identifier, when available"],
      request_id: [type: :string, doc: "Request correlation identifier, when available"],
      iteration: [type: :integer, doc: "ReAct/runtime iteration number, when available"]
    ]
end
