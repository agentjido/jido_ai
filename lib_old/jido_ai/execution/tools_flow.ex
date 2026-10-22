defmodule Jido.AI.Execution.ToolsFlow do
  @moduledoc false
  use Jido.Flow, name: "ai_tools"

  flow do
    map("tools", collection: input(:batch), action: Jido.AI.Execution.ExecuteTool, params: item())

    dispatch("continue",
      decision: Jido.AI.Execution.Continue,
      expander: Jido.AI.Execution.NextBatch,
      params: %{state: input(), results: result("tools")}
    )

    output(result("continue"))
  end
end
