defmodule Jido.AI.Agents.Internal.CoTWorkerAgent do
  @moduledoc false

  use Jido.Agent,
    name: "cot_worker_agent",
    description: "Internal delegated CoT runtime worker",
    strategy: {Jido.AI.Strategies.CoTWorker, []},
    schema:
      Zoi.object(%{
        __strategy__: Zoi.map() |> Zoi.default(%{})
      })
end
