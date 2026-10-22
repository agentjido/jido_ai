defmodule Jido.AI.Execution.ModelFlow do
  @moduledoc false
  use Jido.Flow, name: "ai_reason"

  flow do
    dispatch("reason",
      decision: Jido.AI.Execution.CallModel,
      expander: Jido.AI.Execution.Decide,
      params: input()
    )

    output(result("reason"))
  end
end
