defmodule Jido.AI.Flows.Finalize do
  @moduledoc "Builds the terminal Agent state and reply envelope."

  use Jido.Flow,
    name: "jido_ai_finalize",
    schema: Zoi.object(%{turn: Zoi.any(), result: Zoi.map()}),
    output_schema: Zoi.object(%{state: Zoi.map(), response: Zoi.map()})

  flow do
    step "finalize",
      action: Jido.AI.Actions.FinalizeTurn,
      params: %{outcome: input()}

    output result("finalize")
  end
end
