defmodule Jido.AI.Signal.EmbedError do
  @moduledoc """
  Signal for structured embedding errors.
  """

  use Jido.Signal,
    type: "ai.embed.error",
    default_source: "/ai/embed",
    schema: [
      call_id: [type: :string, required: true, doc: "Correlation ID for the embedding call"],
      error_type: [type: :atom, required: true, doc: "Error classification"],
      message: [type: :string, required: true, doc: "Human-readable error message"],
      details: [type: :map, default: %{}, doc: "Additional error details"],
      retry_after: [type: :integer, doc: "Seconds to wait before retry"]
    ]
end
