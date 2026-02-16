defmodule Jido.AI.Signal.EmbedResult do
  @moduledoc """
  Signal for embedding generation completion.
  """

  use Jido.Signal,
    type: "ai.embed.result",
    default_source: "/ai/embed",
    schema: [
      call_id: [type: :string, required: true, doc: "Correlation ID for the embedding call"],
      result: [type: :any, required: true, doc: "{:ok, result} | {:error, reason}"]
    ]
end
