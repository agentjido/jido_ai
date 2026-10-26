defmodule Jido.AI.Tools.Multiply do
  @moduledoc """
  Multiplies two numbers as one explicit Agent graph node.
  """

  use Jido.Action,
    name: "jido_ai_multiply",
    description: "Multiply two numbers.",
    schema: Zoi.object(%{left: Zoi.number(), right: Zoi.number()}),
    output_schema: Zoi.object(%{value: Zoi.number()})

  @impl Jido.Action
  def run(%{left: left, right: right}, _context), do: {:ok, %{value: left * right}}
end
