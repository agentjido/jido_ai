defmodule Jido.AI.Reasoning.ReAct.Signal do
  @moduledoc """
  Signal envelope used by strategies/adapters to consume ReAct runtime events.
  """

  use Jido.Signal,
    type: "ai.react.worker.event",
    default_source: "/ai/react/worker",
    schema:
      Zoi.object(
        %{
          request_id: Zoi.string(),
          event: Zoi.any() |> Zoi.refine({Jido.AI.Signal.Definition, :map_value, []})
        },
        unrecognized_keys: :error
      )
end
