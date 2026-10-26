defmodule Jido.AI.Actions.ExpandModelNext do
  @moduledoc "Expands completion, another model round, or a tool round."

  use Jido.Action,
    name: "jido_ai_expand_model_next",
    description: "Expand the next graph after a model call",
    schema: Zoi.map(),
    output_schema: Zoi.map()

  @impl Jido.Action
  def run(%{kind: :complete, output: output}, _context),
    do: {:continue, output, Jido.AI.Flows.Finalize}

  def run(%{kind: :model, input: input}, _context),
    do: {:continue, input, Jido.AI.Flows.ModelRound}

  def run(%{kind: :tools, input: input}, _context),
    do: {:continue, input, Jido.AI.Flows.ToolRound}
end
