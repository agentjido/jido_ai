defmodule Jido.AI.Flow.Reason do
  @moduledoc """
  Selects and runs the reasoning Flow configured by the AI Plugin.

  This Flow is the common composition boundary for direct AI requests and
  routed Agent turns. Its Dispatch selects a normal Jido Flow. It does not
  start another `Jido.Exec` execution.
  """

  use Jido.Flow,
    name: "jido_ai_reason",
    description: "Prepare and run one configured AI reasoning Flow"

  flow do
    dispatch "reason",
      decision: Jido.AI.Flow.Reason.Prepare,
      expander: Jido.AI.Flow.Reason.Compose,
      params: input()

    output result("reason")
  end
end
