defmodule Jido.AI.Flows.ToolRound do
  @moduledoc """
  Applies tool guardrails before any requested tool Action runs.
  """

  use Jido.Flow,
    name: "jido_ai_tool_round",
    schema: Zoi.map(),
    output_schema: Zoi.map()

  flow do
    dispatch "tool_guard",
      decision: Jido.AI.Actions.CheckToolCalls,
      expander: Jido.AI.Actions.ExpandToolCalls,
      params: input()

    output result("tool_guard")
  end
end
