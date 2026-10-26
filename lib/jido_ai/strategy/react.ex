defmodule Jido.AI.Strategy.ReAct do
  @moduledoc """
  The default graph-first reasoning Flow.

  The root Dispatch checks the request before it expands the first model
  round. Later Dispatch components expand model and tool rounds until the
  graph returns a completed or blocked result.
  """

  use Jido.Flow,
    id: "jido.ai/strategy/react",
    vsn: 1,
    name: "jido_ai_react",
    description: "A guarded model and parallel tool reasoning graph",
    schema:
      Zoi.object(%{
        input: Zoi.string(),
        max_iterations: Zoi.integer(gte: 1, lte: 8) |> Zoi.default(4),
        max_tool_calls: Zoi.integer(gte: 1, lte: 16) |> Zoi.default(8)
      }),
    output_schema: Zoi.map()

  flow do
    dispatch "input_guard",
      decision: Jido.AI.Actions.CheckInput,
      expander: Jido.AI.Actions.ExpandInput,
      params: %{
        input: input(:input),
        max_iterations: input(:max_iterations),
        max_tool_calls: input(:max_tool_calls)
      }

    output result("input_guard")
  end
end
