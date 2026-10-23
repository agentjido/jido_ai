defmodule Jido.AI.Flow.ReAct do
  @moduledoc """
  The default AI reasoning Flow.

  One model-call Action decides if the request is complete or needs a tool
  round. Each tool round is a child Flow whose components are the selected
  Jido Actions and Flows. The final result contains only the shaped output,
  usage counters, and a sanitized execution trace.
  """

  use Jido.Flow,
    id: "jido.ai/flows/react",
    name: "jido_ai_react",
    description: "Run a bounded ReAct model and tool loop"

  flow do
    dispatch "react",
      decision: Jido.AI.Actions.CallModel,
      expander: Jido.AI.Flow.ReAct.Route,
      params: input(:request)

    output result("react")
  end
end
