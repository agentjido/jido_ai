defmodule Jido.AI.Signal.EmbedRequest do
  @moduledoc """
  Signal for embedding request initiation.
  """

  use Jido.Signal,
    type: "ai.embed.request",
    default_source: "/ai/embed",
    schema: [
      call_id: [type: :string, required: true, doc: "Correlation ID for the embedding call"],
      model: [type: :string, required: true, doc: "Embedding model identifier"],
      input_count: [type: :integer, required: true, doc: "Number of texts to embed"],
      dimensions: [type: :integer, doc: "Requested embedding dimensions"]
    ]
end
