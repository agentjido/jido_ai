defmodule Jido.AI.Runtime.ReasonFlow do
  @moduledoc false
  use Jido.Flow, name: "ai_reason"

  flow do
    dispatch("reason",
      decision: Jido.AI.Runtime.CallModel,
      expander: Jido.AI.Runtime.Decide,
      params: input()
    )

    output(result("reason"))
  end
end
