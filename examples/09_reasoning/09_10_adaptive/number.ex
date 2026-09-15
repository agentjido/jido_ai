defmodule JidoAI.Examples.Adaptive.Number do
  @moduledoc "A small named tool used by methods that support tool calls."
  use Jido.Action, name: "tree_work", schema: Zoi.object(%{n: Zoi.integer()})

  def run(%{n: n}, _context), do: {:ok, %{n: n}}
end
