defmodule Jido.AI.Agents.Internal.ReActWorkerAgent do
  @moduledoc false

  use Jido.Agent,
    name: "react_worker_agent",
    description: "Internal delegated ReAct runtime worker",
    strategy: {Jido.AI.Strategies.ReActWorker, []},
    schema:
      Zoi.object(%{
        __strategy__: Zoi.map() |> Zoi.default(%{})
      })
end
