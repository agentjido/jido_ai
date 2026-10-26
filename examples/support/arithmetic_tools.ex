defmodule JidoAI.Examples.Tools.Add do
  @moduledoc "Adds two numbers as one explicit Agent graph node."

  use Jido.Action,
    id: "jido.ai/examples/tools/add",
    name: "add",
    description: "Add two numbers.",
    schema: Zoi.object(%{left: Zoi.number(), right: Zoi.number()}),
    output_schema: Zoi.object(%{value: Zoi.number()})

  @impl Jido.Action
  def run(%{left: left, right: right}, _context), do: {:ok, %{value: left + right}}
end

defmodule JidoAI.Examples.Tools.Multiply do
  @moduledoc "Multiplies two numbers as one explicit Agent graph node."

  use Jido.Action,
    id: "jido.ai/examples/tools/multiply",
    name: "multiply",
    description: "Multiply two numbers.",
    schema: Zoi.object(%{left: Zoi.number(), right: Zoi.number()}),
    output_schema: Zoi.object(%{value: Zoi.number()})

  @impl Jido.Action
  def run(%{left: left, right: right}, _context), do: {:ok, %{value: left * right}}
end
