defmodule JidoAI.Examples.Support.Multiply do
  @moduledoc "A reusable model-callable Action that multiplies two integers."
  use Jido.Action,
    name: "v3_example_multiply",
    description: "Multiply two integers",
    schema: Zoi.object(%{a: Zoi.integer(), b: Zoi.integer()}, coerce: true)

  @impl true
  def run(%{a: a, b: b}, _context), do: {:ok, %{value: a * b}}
end
