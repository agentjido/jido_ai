defmodule Jido.AI.Actions.ToolCalling.ToolsFlow do
  @moduledoc false
  use Jido.Flow, name: "tool_calling_tools"

  flow do
    step("tools", action: Jido.AI.Actions.ToolCalling.RunTools, params: input())

    dispatch("model",
      decision: Jido.AI.Actions.ToolCalling.RequestModel,
      expander: Jido.AI.Actions.ToolCalling.Decide,
      params: result("tools")
    )

    output(result("model"))
  end
end
