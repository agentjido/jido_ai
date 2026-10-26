defmodule Jido.AI.Actions.ExpandInput do
  @moduledoc "Completes a blocked request or expands the first model round."

  use Jido.Action,
    name: "jido_ai_expand_input",
    description: "Expand the accepted Agent input",
    schema: Zoi.map(),
    output_schema: Zoi.map()

  @impl Jido.Action
  def run(%{kind: :complete, output: output}, _context),
    do: {:continue, output, Jido.AI.Flows.Finalize}

  def run(%{kind: :continue, input: input}, _context),
    do: {:continue, input, Jido.AI.Flows.ModelRound}
end
