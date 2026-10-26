defmodule Jido.AI.Flows.ToolRound do
  @moduledoc "Applies tool guards before requested tool Actions run."

  use Jido.Flow,
    name: "jido_ai_tool_round",
    schema: Zoi.object(%{turn: Zoi.any()}),
    output_schema: Zoi.map()

  flow do
    dispatch "tool_guard",
      decision: Jido.AI.Actions.CheckToolCalls,
      expander: Jido.AI.Actions.ExpandToolCalls,
      params: %{turn: input(:turn)}

    output result("tool_guard")
  end
end
