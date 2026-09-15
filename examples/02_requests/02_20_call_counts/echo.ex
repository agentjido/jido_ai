defmodule JidoAI.Examples.CallCounts.Echo do
  use Jido.Action,
    name: "scope_echo",
    schema: Zoi.object(%{value: Zoi.integer()})

  def run(%{value: value}, _context), do: {:ok, %{value: value}}
end
