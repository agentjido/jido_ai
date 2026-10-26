defmodule Jido.AI.Tools.Add do
  @moduledoc """
  Adds two numbers as one explicit Agent graph node.
  """

  use Jido.Action,
    name: "jido_ai_add",
    description: "Add two numbers.",
    schema: Zoi.object(%{left: Zoi.number(), right: Zoi.number()}),
    output_schema: Zoi.object(%{value: Zoi.number()})

  @impl Jido.Action
  def run(%{left: left, right: right}, _context), do: {:ok, %{value: left + right}}
end
