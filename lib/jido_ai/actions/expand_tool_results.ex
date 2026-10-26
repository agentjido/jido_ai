defmodule Jido.AI.Actions.ExpandToolResults do
  @moduledoc """
  Expands the next model round after the Parallel tool calls complete.
  """

  use Jido.Action,
    name: "jido_ai_expand_tool_results",
    description: "Return completed tool results to the model graph",
    schema: Zoi.map(),
    output_schema: Zoi.map()

  @impl Jido.Action
  def run(%{kind: :continue, input: input}, _context) do
    {:continue, input, Jido.AI.Flows.ModelRound}
  end
end
