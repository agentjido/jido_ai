defmodule JidoAI.Examples.TypedSignals.Publisher do
  use Jido.Agent, name: "typed_signal_publisher"

  agent do
    schema Zoi.object(%{published: Zoi.integer() |> Zoi.default(0)})
    plugin JidoAI.Examples.TypedSignals.Outbound
  end

  routes do
    route "ai.event", JidoAI.Examples.TypedSignals.Publish
  end
end
