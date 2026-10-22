defmodule JidoAI.Examples.RoutingPolicy.Capture do
  use Jido.Action, name: "routing_policy_capture", schema: Zoi.map()

  def run(params, context),
    do: {:ok, %{context.agent_state | observed: %{type: context.signal.type, data: params}}}
end
