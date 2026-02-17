defmodule Jido.AI.Signal.ReactEvent do
  @moduledoc """
  Signal envelope used by strategies/adapters to consume ReAct runtime events.
  """

  use Jido.Signal,
    type: "ai.react.event",
    default_source: "/ai/react",
    schema: [
      request_id: [type: :string, required: true, doc: "Request correlation ID"],
      event: [type: :map, required: true, doc: "ReAct runtime event envelope"]
    ]
end
