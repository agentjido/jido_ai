defmodule Jido.AI.Actions.ToolCalling.ModelFlow do
  @moduledoc false
  use Jido.Flow, name: "tool_calling_model"

  flow do
    dispatch("model",
      decision: Jido.AI.Actions.ToolCalling.RequestModel,
      expander: Jido.AI.Actions.ToolCalling.Decide,
      params: input()
    )

    output(result("model"))
  end
end
