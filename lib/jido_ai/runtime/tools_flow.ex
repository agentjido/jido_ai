defmodule Jido.AI.Runtime.ToolsFlow do
  @moduledoc false
  use Jido.Flow, name: "ai_tools"

  flow do
    map("tools", collection: input(:batch), action: Jido.AI.Runtime.ExecuteTool, params: item())

    dispatch("continue",
      decision: Jido.AI.Runtime.Continue,
      expander: Jido.AI.Runtime.NextBatch,
      params: %{state: input(), results: result("tools")}
    )

    output(result("continue"))
  end
end
