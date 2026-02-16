defmodule Jido.AI.Signal.LLMDelta do
  @moduledoc """
  Signal for streaming LLM token chunks.
  """

  use Jido.Signal,
    type: "ai.llm.delta",
    default_source: "/ai/llm",
    schema: [
      call_id: [type: :string, required: true, doc: "Correlation ID for the LLM call"],
      delta: [type: :string, required: true, doc: "Text chunk from the stream"],
      chunk_type: [type: :atom, default: :content, doc: "Type: :content or :thinking"]
    ]
end
