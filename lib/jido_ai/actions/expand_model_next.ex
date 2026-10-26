defmodule Jido.AI.Actions.ExpandModelNext do
  @moduledoc """
  Completes a model outcome or expands its guarded tool round.
  """

  use Jido.Action,
    name: "jido_ai_expand_model_next",
    description: "Expand the next graph after a model call",
    schema: Zoi.map(),
    output_schema: Zoi.map()

  @impl Jido.Action
  def run(%{kind: :complete, result: result}, _context), do: {:ok, result}

  def run(%{kind: :continue, input: input}, _context) do
    {:continue, input, Jido.AI.Flows.ToolRound}
  end
end
