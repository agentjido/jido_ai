defmodule Jido.AI.Reasoning.ReAct.Worker.Agent do
  @moduledoc false

  use Jido.Agent,
    name: "react_worker_agent",
    description: "Internal delegated ReAct runtime worker",
    default_plugins: false,
    plugins: [],
    strategy: {Jido.AI.Reasoning.ReAct.Worker.Strategy, []},
    schema:
      Zoi.object(%{
        __strategy__: Zoi.map() |> Zoi.default(%{})
      })
end
